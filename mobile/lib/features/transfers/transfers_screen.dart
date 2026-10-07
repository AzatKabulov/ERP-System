import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../admin/admin_repository.dart';
import '../catalog/catalog_repository.dart';
import '../inventory/stock_entry_screen.dart' show EntryResult;
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'transfer_detail_screen.dart';
import 'transfer_form_screen.dart';
import 'transfers_models.dart';
import 'transfers_repository.dart';

/// Transfers between locations, newest first, with a status filter. From here: send goods,
/// or open a transfer to receive or cancel it.
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.admin,
    required this.catalog,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final TransfersRepository repository;
  final AdminRepository admin;
  final CatalogRepository catalog;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  static const _pageSize = 30;
  List<TransferSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  String? _status; // null = all
  int _request = 0;

  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.transfers(
        status: _status,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open(String id) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferDetailScreen(
          transferId: id,
          session: session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<EntryResult>(
      MaterialPageRoute(
        builder: (_) => TransferFormScreen(
          session: session,
          repository: widget.repository,
          admin: widget.admin,
          catalog: widget.catalog,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final l = strings(context);
    showFeedback(
      context,
      result == EntryResult.posted
          ? l.transferSentDone
          : l.outcomeUnknownNotice,
    );
    if (result == EntryResult.posted) {
      _load(reset: true);
    } else {
      // the pending-operations banner lives in the workspace, under these pages
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.transfersTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (session.can('transfer.create'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GradientButton(
                      key: const ValueKey('transfer-new'),
                      label: l.transferNew,
                      icon: Icons.add,
                      onPressed: _create,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('transfer-filter-all'),
                      label: Text(l.statusAll),
                      selected: _status == null,
                      onSelected: (_) {
                        _status = null;
                        _load(reset: true);
                      },
                    ),
                    for (final status in transferStatuses)
                      ChoiceChip(
                        key: ValueKey('transfer-filter-$status'),
                        label: Text(transferStatusLabel(l, status)),
                        selected: _status == status,
                        onSelected: (_) {
                          _status = status;
                          _load(reset: true);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
                else if (_loading && _items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_items.isEmpty)
                  SurfaceCard(
                    child: EmptyState(
                      key: const ValueKey('transfers-empty'),
                      title: l.transfersEmpty,
                      subtitle: '',
                      icon: Icons.swap_horiz,
                    ),
                  )
                else ...[
                  for (final t in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('transfer-${transferNumber(t.number)}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _open(t.id),
                          child: SurfaceCard(
                            padding: 16,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        transferNumber(t.number),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        l.transferRoute(t.fromName, t.toName),
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        formatStamp(t.createdAt),
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: StatusPill(
                                    label: transferStatusLabel(l, t.status),
                                    warning: t.status != 'received',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_items.length < _count)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('transfers-load-more'),
                        onPressed: _loading ? null : () => _load(reset: false),
                        child: Text(l.loadMore),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
