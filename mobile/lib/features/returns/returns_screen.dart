import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connectivity/connection_monitor.dart';
import '../../core/format/format_stamp.dart';
import '../../core/money/decimal_math.dart';
import '../../core/operations/operation_runner.dart';
import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../sales/sales_models.dart';
import '../shared/async_section.dart';
import '../workspace/unsaved_work.dart';
import 'return_detail_screen.dart';
import 'returns_models.dart';
import 'returns_repository.dart';

/// Customer returns, newest first, searchable by number. Open one to see what came back and,
/// for goods that were set aside, to decide whether they are sellable or damaged.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.runner,
    required this.monitor,
    required this.unsaved,
  });

  final SessionController session;
  final ReturnsRepository repository;
  final OperationRunner runner;
  final ConnectionMonitor monitor;
  final UnsavedWork unsaved;

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  static const _pageSize = 30;
  final _search = TextEditingController();
  Timer? _debounce;
  List<ReturnSummary> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _items = const [];
    });
    try {
      final page = await widget.repository.returns(
        query: _search.text,
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
        builder: (_) => ReturnDetailScreen(
          returnId: id,
          session: widget.session,
          repository: widget.repository,
          runner: widget.runner,
          monitor: widget.monitor,
          unsaved: widget.unsaved,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.returnsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  key: const ValueKey('returns-search'),
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(reset: true),
                    );
                  },
                  decoration: InputDecoration(
                    labelText: l.returnSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
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
                      key: const ValueKey('returns-empty'),
                      title: l.returnsEmpty,
                      subtitle: '',
                      icon: Icons.assignment_return_outlined,
                    ),
                  )
                else ...[
                  for (final r in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('return-${returnNumber(r.number)}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _open(r.id),
                          child: SurfaceCard(
                            padding: 14,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${returnNumber(r.number)} · ${formatStamp(r.createdAt)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${l.returnFromSale(saleNumber(r.saleNumber))} · ${r.locationName}',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        r.reason,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatMoney(r.refundMinor, 'TMT'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (r.awaitingInspection)
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 170,
                                        ),
                                        child: StatusPill(
                                          label: l.conditionInspection,
                                          warning: true,
                                        ),
                                      ),
                                  ],
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
                        key: const ValueKey('returns-load-more'),
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
