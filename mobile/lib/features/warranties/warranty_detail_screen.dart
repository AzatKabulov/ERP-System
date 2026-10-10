import 'package:flutter/material.dart';

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
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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

  Widget _body(BuildContext context, WarrantyClaim c) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.warrantyNumberTitle(warrantyNumber(c.number)),
                      key: const ValueKey('wd-number'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: StatusPill(
                      key: const ValueKey('wd-status'),
                      label: c.isOpen
                          ? l.warrantyStatusOpen
                          : warrantyOutcomeLabel(l, c.outcome),
                      warning: c.isOpen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${c.productName} · ${formatQuantity(c.quantityMilli, c.unitDecimals)} ${c.unitSymbol}',
              ),
              Text(
                l.returnFromSale(saleNumber(c.saleNumber)),
                style: const TextStyle(color: AppColors.muted),
              ),
              if (c.customerName.isNotEmpty)
                Text(
                  '${l.customer}: ${c.customerName}${c.customerPhone.isEmpty ? '' : ' · ${c.customerPhone}'}',
                ),
              if (c.warrantyUntil != null)
                Text(l.warrantyUntilLine(c.warrantyUntil!)),
              if (c.outOfWarranty)
                Text(
                  l.warrantyOutOfWarranty,
                  key: const ValueKey('wd-out'),
                  style: const TextStyle(color: AppColors.warning),
                ),
              const SizedBox(height: 8),
              Text(c.problem),
              if (c.returnNumber != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.warrantyReturnLine(returnNumber(c.returnNumber!)),
                    key: const ValueKey('wd-return'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(l.warrantyEvents),
              const SizedBox(height: 8),
              for (final e in c.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_eventText(l, e)} · ${formatStamp(e.createdAt)} · ${e.actor}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (e.note.isNotEmpty) Text(e.note),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (c.isOpen && widget.session.can('warranty.open')) ...[
          const SizedBox(height: 16),
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: TextField(
              key: const ValueKey('wd-note'),
              controller: _note,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.warrantyNoteLabel),
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
              icon: const Icon(Icons.note_add_outlined),
              label: Text(l.warrantyAddNote),
            ),
          ),
        ],
        if (c.isOpen && widget.session.can('warranty.resolve')) ...[
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(l.warrantyOutcomeLabel),
                const SizedBox(height: 8),
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
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: TextField(
                    key: const ValueKey('wd-close-note'),
                    controller: _closeNote,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: l.warrantyCloseNote),
                  ),
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: widget.monitor,
                  builder: (context, _) => GradientButton(
                    key: const ValueKey('wd-close'),
                    label: l.warrantyClose,
                    icon: Icons.check,
                    onPressed: _busy || !widget.monitor.online || !_closeReady()
                        ? null
                        : () => _close(c),
                  ),
                ),
              ],
            ),
          ),
        ],
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
