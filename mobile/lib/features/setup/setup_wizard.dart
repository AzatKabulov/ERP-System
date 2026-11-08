import '../shared/loading_skeletons.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';

/// Talks to the shop and team routes of the server.
class SetupRepository {
  SetupRepository(this.api, this.businessId);
  final ApiClient api;
  final String businessId;

  String get _shop => '/api/v1/businesses/$businessId/';
  String get _team => '/api/v1/businesses/$businessId/team/';

  Future<Map<String, dynamic>> shop() async => (await api.get(_shop)).map;

  Future<void> saveShop(Map<String, Object?> fields) async {
    await api.patch(_shop, body: fields);
  }

  Future<List<Map<String, dynamic>>> team() async {
    final json = (await api.get(_team)).json;
    final rows = json is Map ? json['results'] as List : json as List;
    return [for (final r in rows) (r as Map).cast<String, dynamic>()];
  }

  Future<void> addPerson(Map<String, Object?> fields) async {
    await api.post(_team, body: fields);
  }

  Future<void> changePerson(String id, Map<String, Object?> fields) async {
    await api.patch('$_team$id/', body: fields);
  }

  Future<void> removePerson(String id) async {
    await api.send('DELETE', '$_team$id/');
  }
}

class _Person {
  _Person({
    this.id,
    String name = '',
    String phone = '',
    String title = '',
    String pay = '',
  }) : name = TextEditingController(text: name),
       phone = TextEditingController(text: phone),
       title = TextEditingController(text: title),
       pay = TextEditingController(text: pay);

  final String? id;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController title;
  final TextEditingController pay;

  void dispose() {
    name.dispose();
    phone.dispose();
    title.dispose();
    pay.dispose();
  }
}

/// The questions an owner is asked the first time they sign in to a shop we set up: the shop, who
/// works there and what they are paid, and the fixed monthly costs. Every step can be skipped and
/// the whole thing can be opened again later from Settings.
class SetupWizard extends StatefulWidget {
  const SetupWizard({
    super.key,
    required this.session,
    required this.repository,
    required this.firstRun,
    required this.onClose,
  });

  final SessionController session;
  final SetupRepository repository;

  /// True at the first sign-in (welcome page, "Skip"); false when opened from Settings.
  final bool firstRun;

  /// Called when the owner finishes, skips or (from Settings) leaves.
  final VoidCallback onClose;

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  late int _step = widget.firstRun ? 0 : 1;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _rent = TextEditingController();
  final _costs = TextEditingController();
  final List<_Person> _people = [];
  final List<String> _removed = [];
  bool _loading = true;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _name.text = widget.session.membership?.businessName ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _rent, _costs]) {
      c.dispose();
    }
    for (final p in _people) {
      p.dispose();
    }
    super.dispose();
  }

  String _plain(Object? v) => v == null ? '' : '$v';

  Future<void> _load() async {
    try {
      final shop = await widget.repository.shop();
      final team = await widget.repository.team();
      if (!mounted) return;
      setState(() {
        _name.text = _plain(shop['name']);
        _phone.text = _plain(shop['phone']);
        _address.text = _plain(shop['address']);
        _rent.text = _plain(shop['monthly_rent']);
        _costs.text = _plain(shop['monthly_costs']);
        for (final t in team) {
          _people.add(
            _Person(
              id: t['id'] as String,
              name: _plain(t['name']),
              phone: _plain(t['phone']),
              title: _plain(t['job_title']),
              pay: _plain(t['monthly_pay']),
            ),
          );
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Map<String, Object?> _personBody(_Person p) => {
    'name': p.name.text.trim(),
    'phone': p.phone.text.trim(),
    'job_title': p.title.text.trim(),
    'monthly_pay': p.pay.text.trim().isEmpty ? null : p.pay.text.trim(),
  };

  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = widget.repository;
      await repo.saveShop({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'monthly_rent': _rent.text.trim().isEmpty ? null : _rent.text.trim(),
        'monthly_costs': _costs.text.trim().isEmpty ? null : _costs.text.trim(),
        'setup_status': 'done',
      });
      for (final id in _removed) {
        await repo.removePerson(id);
      }
      for (final p in _people) {
        if (p.name.text.trim().isEmpty) continue;
        if (p.id == null) {
          await repo.addPerson(_personBody(p));
        } else {
          await repo.changePerson(p.id!, _personBody(p));
        }
      }
      await widget.session.refreshProfile();
      if (mounted) {
        setState(() => _step = 4);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveShop({'setup_status': 'skipped'});
      await widget.session.refreshProfile();
      if (mounted) {
        showFeedback(context, strings(context).suSkipped);
        widget.onClose();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- steps -----------------------------------------------------------------------------

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    String? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: LabeledField(
      label: label,
      child: TextField(
        key: key == null ? null : ValueKey(key),
        controller: c,
        enabled: !_busy,
        keyboardType: keyboard,
      ),
    ),
  );

  Widget _title(String title, [String? body]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: AppColors.muted, height: 1.5)),
        ],
      ],
    ),
  );

  Widget _welcome(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          gradient: AppGradients.spotlight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const AppIcon(AppIcons.checklist, size: 30, color: Colors.white),
      ),
      _title(l.suWelcomeTitle, l.suWelcomeBody),
    ],
  );

  Widget _shopStep(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(l.suShopTitle),
      _field(l.suShopName, _name, key: 'setup-name'),
      _field(
        l.suShopPhone,
        _phone,
        keyboard: TextInputType.phone,
        key: 'setup-phone',
      ),
      _field(l.suShopAddress, _address, key: 'setup-address'),
    ],
  );

  Widget _teamStep(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(l.suTeamTitle, l.suTeamHint),
      if (_people.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(l.suNoTeam, style: TextStyle(color: AppColors.muted)),
        ),
      for (var i = 0; i < _people.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SurfaceCard(
            flat: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  l.suPersonName,
                  _people[i].name,
                  key: 'setup-person-name-$i',
                ),
                _field(
                  l.suPersonPhone,
                  _people[i].phone,
                  keyboard: TextInputType.phone,
                ),
                _field(l.suPersonTitle, _people[i].title),
                _field(
                  l.suPersonPay,
                  _people[i].pay,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  key: 'setup-person-pay-$i',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: ValueKey('setup-person-remove-$i'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            final gone = _people.removeAt(i);
                            if (gone.id != null) _removed.add(gone.id!);
                            gone.dispose();
                          }),
                    child: Text(l.suRemove),
                  ),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        key: const ValueKey('setup-add-person'),
        onPressed: _busy ? null : () => setState(() => _people.add(_Person())),
        icon: const AppIcon(AppIcons.personAdd, size: 18),
        label: Text(l.suAddPerson),
      ),
    ],
  );

  Widget _costsStep(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(l.suCostsTitle, l.suCostsHint),
      _field(
        l.suRent,
        _rent,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        key: 'setup-rent',
      ),
      _field(
        l.suCosts,
        _costs,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        key: 'setup-costs',
      ),
    ],
  );

  Widget _doneStep(AppLocalizations l) {
    final pay = _people.fold<double>(
      0,
      (sum, p) =>
          sum + (double.tryParse(p.pay.text.trim().replaceAll(',', '.')) ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppColors.successTint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: AppIcon(
            AppIcons.checkCircle,
            size: 32,
            color: AppColors.success,
          ),
        ),
        _title(l.suDoneTitle, l.suDoneBody),
        if (pay > 0)
          Text(
            l.suPayTotal(pay.toStringAsFixed(2)),
            style: TextStyle(color: AppColors.neutral),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final done = _step == 4;
    final body = switch (_step) {
      0 => _welcome(l),
      1 => _shopStep(l),
      2 => _teamStep(l),
      3 => _costsStep(l),
      _ => _doneStep(l),
    };
    final lastQuestion = _step == 3;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: Row(
                    children: [
                      if (!done && _step > 0)
                        Text(
                          l.suStepOf(_step, 3),
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      const Spacer(),
                      if (!done)
                        TextButton(
                          key: const ValueKey('setup-skip'),
                          onPressed: _busy
                              ? null
                              : widget.firstRun
                              ? _skip
                              : widget.onClose,
                          child: Text(widget.firstRun ? l.suSkip : l.close),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const FormLoadingSkeleton(fields: 5, maxWidth: 560)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              body,
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    apiErrorText(l, _error!),
                                    key: const ValueKey('setup-error'),
                                    style: TextStyle(color: AppColors.danger),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    children: [
                      if (!done && _step > (widget.firstRun ? 0 : 1)) ...[
                        OutlinedButton(
                          key: const ValueKey('setup-back'),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step--),
                          child: Text(l.pfBack),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: PrimaryButton(
                          key: const ValueKey('setup-next'),
                          label: done
                              ? l.suStart
                              : lastQuestion
                              ? l.pfDone
                              : l.suNext,
                          trailingIcon: AppIcons.arrow,
                          onPressed: _busy || _loading
                              ? null
                              : done
                              ? widget.onClose
                              : lastQuestion
                              ? _finish
                              : () => setState(() => _step++),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
