import 'package:flutter/material.dart';
import '../../widgets/app_icons.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../l10n/app_localizations.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../returns/returns_models.dart';
import '../sales/sales_models.dart';
import '../shared/async_section.dart';
import 'warranties_models.dart';
import 'warranties_repository.dart';

/// One warranty claim with its history. While it is open: add a note, and (owner or manager)
/// close it with an outcome: repair, replacement (stock moves), refund (a return is made) or
/// rejection. Closing goes through the [OperationRunner] so a lost answer never closes it twice.
class WarrantyDetailScreen extends StatefulWidget {
  const WarrantyDetailScreen({
    super.key,
    required this.claimId,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
  });

  final String claimId;
  final SessionController session;
  final WarrantiesRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;

  @override
  State<WarrantyDetailScreen> createState() => _WarrantyDetailScreenState();
}

class _WarrantyDetailScreenState extends State<WarrantyDetailScreen> {
  final _section = GlobalKey<AsyncSectionState<WarrantyClaim>>();
  final _note = TextEditingController();
  final _closeNote = TextEditingController();
  String _outcome = 'repair';
  bool _changed = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _note.dispose();
    _closeNote.dispose();
    super.dispose();
  }

  Future<void> _addNote(WarrantyClaim claim) async {
    final text = _note.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.addNote(claim.id, text);
      if (!mounted) return;
      _note.clear();
      _changed = true;
      _section.currentState?.reload();
    } on ApiException catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _closeReady() =>
      _outcome != 'rejected' || _closeNote.text.trim().isNotEmpty;

  Future<void> _close(WarrantyClaim claim) async {
    if (_busy || !_closeReady()) return;
    final l = strings(context);
    final sure = await confirmAction(
      context,
      l.warrantyClose,
      l.warrantyCloseConfirm(
        warrantyNumber(claim.number),
        warrantyOutcomeLabel(l, _outcome),
      ),
    );
    if (!sure || !mounted) return;
    final repo = widget.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.runner.submit(
      action: 'warranty_resolve',
      businessId: widget.session.membership!.businessId,
      path: repo.closePath(claim.id),
      body: repo.closeBody(outcome: _outcome, note: _closeNote.text.trim()),
      subject: warrantyNumber(claim.number),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case OperationCompleted():
        _changed = true;
        showFeedback(context, l.warrantyClosedDone);
        _closeNote.clear();
        _section.currentState?.reload();
      case OperationUnknown():
        showFeedback(context, l.outcomeUnknownNotice);
        Navigator.of(context).popUntil((r) => r.isFirst); // where the banner is
      case OperationRejected(:final error):
        setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.warrantiesTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AsyncSection<WarrantyClaim>(
                  key: _section,
                  load: () => widget.repository.claim(widget.claimId),
                  builder: (context, claim) => _body(context, claim),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _eventText(AppLocalizations l, WarrantyEvent e) => switch (e.kind) {
    'opened' => l.warrantyEventOpened,
    'closed' => l.warrantyEventClosed(warrantyOutcomeLabel(l, e.outcome)),
    _ => l.warrantyEventNote,
  };

  String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  Widget _timeline(AppLocalizations l, WarrantyClaim c) {
    AppIconData icon(WarrantyEvent e) => switch (e.kind) {
      'opened' => AppIcons.shield,
      'closed' => AppIcons.check,
      _ => AppIcons.edit,
    };
    return Column(
      children: [
        for (var i = 0; i < c.events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Center(
                          child: AppIcon(
                            icon(c.events[i]),
                            size: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      if (i < c.events.length - 1)
                        Expanded(
                          child: Container(width: 1, color: AppColors.line),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eventText(l, c.events[i]),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${formatStamp(c.events[i].createdAt)} · ${c.events[i].actor}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        if (c.events[i].note.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            c.events[i].note,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context, WarrantyClaim c) {
    final l = strings(context);
    final canResolve = c.isOpen && widget.session.can('warranty.resolve');
    final divider = const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(),
    );
    final left = SurfaceCard(
      padding: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(l.warrantyProductAndBuyer),
          const SizedBox(height: 8),
          Text(
            c.productName,
            style: const TextStyle(
              fontSize: 16,
              fontVariations: [FontVariation.weight(650)],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatQuantity(c.quantityMilli, c.unitDecimals)} ${c.unitSymbol} · ${saleNumber(c.saleNumber)}',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              letterSpacing: -0.28,
              color: AppColors.muted,
              fontSize: 14,
            ),
          ),
          if (c.customerName.isNotEmpty) ...[
            divider,
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _initials(c.customerName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (c.customerPhone.isNotEmpty) c.customerPhone,
                          if (c.warrantyUntil != null)
                            l.warrantyUntilLine(c.warrantyUntil!),
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (c.warrantyUntil != null) ...[
            const SizedBox(height: 8),
            Text(
              l.warrantyUntilLine(c.warrantyUntil!),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
          if (c.outOfWarranty) ...[
            const SizedBox(height: 12),
            Text(
              l.warrantyOutOfWarranty,
              key: const ValueKey('wd-out'),
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ],
          divider,
          Text(c.problem, style: const TextStyle(fontSize: 14, height: 1.55)),
          if (c.returnNumber != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.warrantyReturnLine(returnNumber(c.returnNumber!)),
                key: const ValueKey('wd-return'),
              ),
            ),
          if (canResolve) ...[
            divider,
            Text(
              l.warrantyOutcomeLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in warrantyOutcomes)
                  ChoiceChip(
                    key: ValueKey('wd-outcome-$o'),
                    label: Text(warrantyOutcomeLabel(l, o)),
                    selected: _outcome == o,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _outcome = o),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: LabeledField(
                label: l.warrantyCloseNote,
                child: TextField(
                  key: const ValueKey('wd-close-note'),
                  controller: _closeNote,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: widget.monitor,
              builder: (context, _) => PrimaryButton(
                key: const ValueKey('wd-close'),
                label: l.warrantyClose,
                icon: AppIcons.check,
                onPressed: _busy || !widget.monitor.online || !_closeReady()
                    ? null
                    : () => _close(c),
              ),
            ),
          ],
        ],
      ),
    );
    final right = SurfaceCard(
      padding: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(l.warrantyEvents),
          const SizedBox(height: 16),
          _timeline(l, c),
          if (c.isOpen && widget.session.can('warranty.open')) ...[
            const SizedBox(height: 8),
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: LabeledField(
                label: l.warrantyNoteLabel,
                child: TextField(
                  key: const ValueKey('wd-note'),
                  controller: _note,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('wd-add-note'),
                onPressed: _busy || _note.text.trim().isEmpty
                    ? null
                    : () => _addNote(c),
                icon: const AppIcon(AppIcons.noteAdd, size: 20),
                label: Text(l.warrantyAddNote),
              ),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: warrantyNumber(c.number),
          title: l.warrantyCaseTitle,
          subtitle: formatStamp(c.openedAt),
          actions: [
            StatusPill(
              key: const ValueKey('wd-status'),
              label: c.isOpen
                  ? l.warrantyStatusOpen
                  : warrantyOutcomeLabel(l, c.outcome),
              tone: c.isOpen ? StatusTone.warning : StatusTone.success,
              icon: c.isOpen ? AppIcons.clock : AppIcons.check,
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 700
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 16), right],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: left),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: right),
                  ],
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              apiErrorText(l, _error!),
              key: const ValueKey('wd-error'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ],
    );
  }
}
