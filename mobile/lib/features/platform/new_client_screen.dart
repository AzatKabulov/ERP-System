import '../../widgets/skeleton.dart';
import '../shared/async_section.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';

/// Makes a new client: the shop, its owner with a temporary password (shown once) and its start,
/// a free trial or a package that was just paid. Answers the created client when it closes.
class NewClientScreen extends StatefulWidget {
  const NewClientScreen({super.key, required this.repository});
  final PlatformRepository repository;

  @override
  State<NewClientScreen> createState() => _NewClientScreenState();
}

class _NewClientScreenState extends State<NewClientScreen> {
  final _store = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerLogin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _language = 'ru';
  String _method = 'cash';
  String _start = ''; // '' = free trial, otherwise a package id
  List<PlanRow> _plans = const [];
  bool _plansLoading = true;
  Object? _plansError;
  bool _busy = false;
  ApiException? _error;
  NewClientResult? _result;
  bool _discarded = false;
  bool _confirmingLeave = false;
  bool get _dirty =>
      [
        _store,
        _ownerName,
        _ownerLogin,
        _phone,
        _email,
        _amount,
        _reference,
      ].any((c) => c.text.isNotEmpty) ||
      _language != 'ru' ||
      _start.isNotEmpty ||
      _method != 'cash';
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _store,
      _ownerName,
      _ownerLogin,
      _phone,
      _email,
      _amount,
      _reference,
    ]) {
      c.addListener(_changed);
    }
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _plansLoading = true;
      _plansError = null;
    });
    try {
      final all = await widget.repository.plans();
      if (mounted) {
        setState(() => _plans = all.where((p) => p.sellable).toList());
      }
    } catch (error) {
      if (mounted) setState(() => _plansError = error);
    } finally {
      if (mounted) setState(() => _plansLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _store,
      _ownerName,
      _ownerLogin,
      _phone,
      _email,
      _amount,
      _reference,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.createClient({
        'store_name': _store.text.trim(),
        'owner_name': _ownerName.text.trim(),
        'owner_login': _ownerLogin.text.trim(),
        'owner_email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'language': _language,
        if (_start.isNotEmpty) 'start': _start,
        if (_start.isNotEmpty && _amount.text.trim().isNotEmpty)
          'amount': _amount.text.trim(),
        if (_start.isNotEmpty) 'currency': 'TMT',
        if (_start.isNotEmpty) 'method': _method,
        if (_start.isNotEmpty) 'reference': _reference.text.trim(),
      });
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController c,
    String name, {
    String? hint,
    TextInputType? keyboard,
  }) {
    final l = strings(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LabeledField(
        label: label,
        child: TextField(
          key: ValueKey('pf-new-$name'),
          controller: c,
          enabled: !_busy,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            errorText: fieldProblem(l, _error, name),
          ),
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(l.pfStoreName, _store, 'store_name'),
            _field(l.pfOwnerName, _ownerName, 'owner_name'),
            _field(
              l.pfOwnerLogin,
              _ownerLogin,
              'owner_login',
              hint: l.pfOwnerLoginHint,
            ),
            _field(
              l.pfContactPhone,
              _phone,
              'phone',
              keyboard: TextInputType.phone,
            ),
            _field(
              l.pfContactEmail,
              _email,
              'owner_email',
              keyboard: TextInputType.emailAddress,
            ),
            LabeledField(
              label: l.pfStoreLanguage,
              child: AppSegmented<String>(
                keyPrefix: 'pf-new-lang',
                options: [('ru', l.languageRussian), ('tk', l.languageTurkmen)],
                value: _language,
                onChanged: (v) => setState(() => _language = v),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_plansError != null)
              ErrorPanel(error: _plansError!, onRetry: _loadPlans),
            if (_plansLoading)
              const SkeletonForm(fields: 1, actions: false)
            else
              LabeledField(
                label: l.pfStartWith,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('pf-new-start'),
                  isExpanded: true,
                  initialValue: _start,
                  items: [
                    DropdownMenuItem(value: '', child: Text(l.pfFreeTrial)),
                    for (final p in _plans)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.price == null
                              ? p.name
                              : '${p.name} · ${p.price} ${p.currency}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _start = v!),
                ),
              ),
            if (_start.isNotEmpty) ...[
              const SizedBox(height: 14),
              _field(
                l.pfFieldAmount,
                _amount,
                'amount',
                hint: l.pfAmountHintPackage,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              LabeledField(
                label: l.pfFieldMethod,
                child: DropdownButtonFormField<String>(
                  initialValue: _method,
                  items: [
                    for (final m in const ['cash', 'card', 'transfer', 'other'])
                      DropdownMenuItem(
                        value: m,
                        child: Text(methodLabel(l, m)),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _method = v!),
                ),
              ),
              const SizedBox(height: 14),
              _field(l.pfFieldReference, _reference, 'reference'),
            ],
          ],
        ),
      ),
      if (_error != null && _error!.fields.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            generalProblem(l, _error),
            key: const ValueKey('pf-new-error'),
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      const SizedBox(height: 20),
      PrimaryButton(
        key: const ValueKey('pf-new-create'),
        label: l.pfCreateClient,
        icon: AppIcons.personAdd,
        onPressed: _busy ? null : _create,
      ),
    ],
  );

  Widget _done(AppLocalizations l, NewClientResult r) => SurfaceCard(
    featured: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.pfClientCreated,
          key: const ValueKey('pf-new-done'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(r.detail.row.storeName, style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        Text(
          l.pfClientCreatedHint,
          style: TextStyle(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        SecretLine(
          label: l.pfLoginLabel,
          value: r.login,
          valueKey: const ValueKey('pf-new-login'),
        ),
        const SizedBox(height: 10),
        SecretLine(
          label: l.pfTempPasswordLabel,
          value: r.password,
          valueKey: const ValueKey('pf-new-password'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          key: const ValueKey('pf-new-open'),
          label: l.pfOpenClient,
          trailingIcon: AppIcons.arrow,
          onPressed: () => Navigator.of(context).pop(r.detail),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final result = _result;
    return PopScope(
      canPop: !_busy && (_discarded || (result == null && !_dirty)),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy || _confirmingLeave) return;
        if (result != null) {
          Navigator.of(context).pop(result.detail);
          return;
        }
        _confirmingLeave = true;
        final leave = await confirmAction(
          context,
          l.pfNewClientTitle,
          l.unsavedChangeConflict,
        );
        _confirmingLeave = false;
        if (leave && context.mounted) {
          _discarded = true;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.pfNewClientTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: result == null ? _form(l) : _done(l, result),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
