import '../../widgets/skeleton.dart';
import '../shared/async_section.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';

/// The buttons on a client's page. Each one is filled in, then shown as a plain sentence of what
/// is about to happen (the "review"), and only then done.
enum PlatformAction {
  renew('renew', AppIcons.plus),
  extend('extend', AppIcons.clock),
  correct('correct', AppIcons.edit),
  suspend('suspend', AppIcons.block),
  resume('resume', AppIcons.retry),
  freeOn('free-on', AppIcons.tag),
  freeOff('free-off', AppIcons.tag),
  resetPassword('reset-password', AppIcons.lock);

  const PlatformAction(this.server, this.icon);

  /// The name in the server's address.
  final String server;
  final AppIconData icon;

  String title(AppLocalizations l) => switch (this) {
    renew => l.pfActRenew,
    extend => l.pfActExtend,
    correct => l.pfActCorrect,
    suspend => l.pfActSuspend,
    resume => l.pfActResume,
    freeOn => l.pfActFreeOn,
    freeOff => l.pfActFreeOff,
    resetPassword => l.pfActResetPassword,
  };

  bool get dangerous => this == suspend || this == resetPassword;

  bool get takesPayment => this == renew || this == extend;

  /// A reason must be given (the server insists too).
  bool get needsNote =>
      this == extend ||
      this == correct ||
      this == suspend ||
      this == freeOn ||
      this == freeOff;

  bool get hasForm => this != resetPassword;
}

/// Opens the dialog for [action] on [detail]. Answers the updated client, or null if cancelled.
Future<ClientDetail?> showClientAction(
  BuildContext context, {
  required PlatformRepository repository,
  required ClientDetail detail,
  required PlatformAction action,
}) => showDialog<ClientDetail>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _ActionDialog(repository: repository, detail: detail, action: action),
);

enum _Step { form, review, secret }

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.repository,
    required this.detail,
    required this.action,
  });
  final PlatformRepository repository;
  final ClientDetail detail;
  final PlatformAction action;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: 'TMT');
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _days = TextEditingController();
  String _method = 'cash';
  String? _planId;
  DateTime? _newEnd;
  List<PlanRow> _plans = const [];
  bool _plansLoading = true;
  Object? _plansError;
  _Step _step = _Step.form;
  bool _busy = false;
  ApiException? _error;
  ActionPreview? _preview;
  ActionOutcome? _outcome;

  PlatformAction get action => widget.action;
  String get _id => widget.detail.row.id;

  @override
  void initState() {
    super.initState();
    if (action == PlatformAction.renew) _loadPlans();
    if (!action.hasForm) {
      // nothing to fill in: go straight to "this is what will happen"
      WidgetsBinding.instance.addPostFrameCallback((_) => _review());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _reference.dispose();
    _note.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _plansLoading = true;
      _plansError = null;
    });
    try {
      final all = await widget.repository.plans();
      if (!mounted) return;
      setState(() {
        _plans = all.where((p) => p.sellable).toList();
        _planId ??= _plans.isEmpty ? null : _plans.first.id;
      });
    } catch (error) {
      if (mounted) setState(() => _plansError = error);
    } finally {
      if (mounted) setState(() => _plansLoading = false);
    }
  }

  PlanRow? get _plan => _plans.where((p) => p.id == _planId).firstOrNull;

  Map<String, Object?> _fields() {
    final payment = <String, Object?>{
      if (_amount.text.trim().isNotEmpty) 'amount': _amount.text.trim(),
      'currency': _currency.text.trim(),
      'method': _method,
      'reference': _reference.text.trim(),
    };
    return switch (action) {
      PlatformAction.renew => {
        'plan': _planId,
        ...payment,
        'note': _note.text.trim(),
      },
      PlatformAction.extend => {
        'days': int.tryParse(_days.text.trim()),
        'note': _note.text.trim(),
        ...payment,
      },
      PlatformAction.correct => {
        'new_end': _newEnd == null
            ? null
            : '${_newEnd!.year.toString().padLeft(4, '0')}-'
                  '${_newEnd!.month.toString().padLeft(2, '0')}-'
                  '${_newEnd!.day.toString().padLeft(2, '0')}',
        'note': _note.text.trim(),
      },
      PlatformAction.resetPassword => const {},
      _ => {'note': _note.text.trim()},
    };
  }

  Future<void> _review() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.review(
        _id,
        action.server,
        _fields(),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _step = _Step.review;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await widget.repository.perform(
        _id,
        action.server,
        _fields(),
      );
      if (!mounted) return;
      if (outcome.secret != null) {
        setState(() {
          _outcome = outcome;
          _step = _Step.secret;
        });
      } else {
        Navigator.of(context).pop(outcome.detail);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- form ------------------------------------------------------------------------------

  Widget _text(
    String label,
    TextEditingController controller,
    String field, {
    String? hint,
    TextInputType? keyboard,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final l = strings(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LabeledField(
        label: label,
        child: TextField(
          key: ValueKey('pf-field-$field'),
          controller: controller,
          enabled: !_busy,
          keyboardType: keyboard,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            errorText: fieldProblem(l, _error, field),
          ),
        ),
      ),
    );
  }

  Widget _paymentFields(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _text(
              l.pfFieldAmount,
              _amount,
              'amount',
              hint: action == PlatformAction.renew
                  ? l.pfAmountHintPackage
                  : null,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _text(l.pfFieldCurrency, _currency, 'currency'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: LabeledField(
          label: l.pfFieldMethod,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('pf-field-method'),
            initialValue: _method,
            items: [
              for (final m in const ['cash', 'card', 'transfer', 'other'])
                DropdownMenuItem(value: m, child: Text(methodLabel(l, m))),
            ],
            onChanged: _busy ? null : (v) => setState(() => _method = v!),
          ),
        ),
      ),
      _text(l.pfFieldReference, _reference, 'reference'),
    ],
  );

  Widget _form(AppLocalizations l) {
    final children = <Widget>[];
    if (action == PlatformAction.renew) {
      if (_plansError != null) {
        children.add(ErrorPanel(error: _plansError!, onRetry: _loadPlans));
      }
      children.add(
        _plansLoading
            ? const SkeletonForm(fields: 1, actions: false)
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: LabeledField(
                  label: l.pfFieldPackage,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('pf-field-plan'),
                    isExpanded: true,
                    initialValue: _planId,
                    items: [
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
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _planId = v),
                  ),
                ),
              ),
      );
    }
    if (action == PlatformAction.extend) {
      children.add(
        _text(l.pfFieldDays, _days, 'days', keyboard: TextInputType.number),
      );
    }
    if (action == PlatformAction.correct) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: LabeledField(
            label: l.pfFieldNewEnd,
            child: OutlinedButton.icon(
              key: const ValueKey('pf-field-new-end'),
              onPressed: _busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _newEnd ?? now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (picked != null) setState(() => _newEnd = picked);
                    },
              icon: const AppIcon(AppIcons.event, size: 18),
              label: Text(
                _newEnd == null ? l.pfFieldNewEnd : formatDay(_newEnd!),
              ),
            ),
          ),
        ),
      );
      final problem = fieldProblem(l, _error, 'new_end');
      if (problem != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(problem, style: TextStyle(color: AppColors.danger)),
          ),
        );
      }
    }
    if (action.takesPayment) children.add(_paymentFields(l));
    if (action == PlatformAction.renew || action == PlatformAction.resume) {
      children.add(
        _text(l.pfFieldNoteOptional, _note, 'note', minLines: 1, maxLines: 3),
      );
    } else if (action.needsNote) {
      children.add(
        _text(l.pfFieldNote, _note, 'note', minLines: 2, maxLines: 4),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---- review ----------------------------------------------------------------------------

  List<String> _lines(AppLocalizations l) {
    final store = widget.detail.row.storeName;
    final preview = _preview;
    String day(DateTime? d) => d == null ? '—' : formatDay(d);
    final lines = <String>[];
    switch (action) {
      case PlatformAction.renew:
        lines.add(l.pfReviewRenew(_plan?.name ?? '', store));
      case PlatformAction.extend:
        lines.add(
          l.pfReviewExtend(int.tryParse(_days.text.trim()) ?? 0, store),
        );
      case PlatformAction.correct:
        lines.add(l.pfReviewCorrect(store, day(preview?.newEnd)));
      case PlatformAction.suspend:
        lines.add(l.pfReviewSuspend(store));
      case PlatformAction.resume:
        lines.add(l.pfReviewResume(store));
      case PlatformAction.freeOn:
        lines.add(l.pfReviewFreeOn(store));
      case PlatformAction.freeOff:
        lines.add(l.pfReviewFreeOff(store));
      case PlatformAction.resetPassword:
        lines.add(l.pfReviewReset(store));
    }
    if (action == PlatformAction.renew || action == PlatformAction.extend) {
      lines.add(l.pfReviewDates(day(preview?.oldEnd), day(preview?.newEnd)));
    }
    if (action.takesPayment) {
      final typed = _amount.text.trim();
      final price = action == PlatformAction.renew ? _plan?.price : null;
      final amount = typed.isNotEmpty ? typed : price;
      lines.add(
        amount == null
            ? l.pfNoPaymentRecorded
            : l.pfPaymentRecorded(
                amount,
                typed.isNotEmpty
                    ? _currency.text.trim()
                    : (_plan?.currency ?? ''),
              ),
      );
    }
    final note = _note.text.trim();
    if (note.isNotEmpty) lines.add('«$note»');
    return lines;
  }

  Widget _reviewBody(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        l.pfReviewTitle,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      for (final line in _lines(l))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line, style: const TextStyle(height: 1.45)),
        ),
    ],
  );

  Widget _secret(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        l.pfSecretHint,
        style: TextStyle(color: AppColors.muted, height: 1.45),
      ),
      const SizedBox(height: 14),
      SecretLine(
        label: l.pfTempPasswordLabel,
        value: _outcome!.secret!,
        valueKey: const ValueKey('pf-secret'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final title = _step == _Step.secret ? l.pfSecretTitle : action.title(l);
    final Widget body = switch (_step) {
      _Step.form => _form(l),
      _Step.review => _reviewBody(l),
      _Step.secret => _secret(l),
    };
    // A problem that is not about one field (the server refused, no connection...).
    final general = _error != null && _error!.fields.isEmpty
        ? generalProblem(l, _error)
        : '';
    final actions = switch (_step) {
      _Step.form => [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pf-action-review'),
          onPressed: _busy ? null : _review,
          child: Text(l.confirm),
        ),
      ],
      _Step.review => [
        OutlinedButton(
          key: const ValueKey('pf-action-back'),
          onPressed: _busy
              ? null
              : () => action.hasForm
                    ? setState(() => _step = _Step.form)
                    : Navigator.of(context).pop(),
          child: Text(action.hasForm ? l.pfBack : l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pf-action-confirm'),
          style: action.dangerous
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: _busy ? null : _confirm,
          child: Text(l.pfDoIt),
        ),
      ],
      _Step.secret => [
        FilledButton(
          key: const ValueKey('pf-action-done'),
          onPressed: () => Navigator.of(context).pop(_outcome!.detail),
          child: Text(l.pfDone),
        ),
      ],
    };
    return AppDialog(
      title: title,
      icon: action.icon,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (general.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                general,
                key: const ValueKey('pf-action-error'),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
        ],
      ),
      actions: actions,
    );
  }
}
