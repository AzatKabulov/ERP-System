import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shared/async_section.dart';
import 'audit_labels.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

/// Who did what, and when: the activity history for owners and managers. Read-only; nothing
/// here can be edited or deleted, by anyone.
class ActivityView extends StatefulWidget {
  const ActivityView({
    super.key,
    required this.repository,
    required this.period,
  });

  final ReportsRepository repository;
  final ReportQuery period;

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  static const _pageSize = 30;
  final _search = TextEditingController();
  List<String> _actions = const [];
  String? _action;
  String _text = '';
  List<AuditEntry> _items = const [];
  int _count = 0;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    widget.repository
        .auditActions()
        .then((actions) {
          if (mounted) setState(() => _actions = actions);
        })
        .catchError((_) {}); // the filter just stays empty
  }

  @override
  void dispose() {
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
      final page = await widget.repository.audit(
        period: widget.period,
        action: _action,
        query: _text,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _count = page.count;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _submit() {
    _text = _search.text.trim();
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: DropdownButton<String?>(
                key: const ValueKey('activity-action'),
                isExpanded: true,
                value: _actions.contains(_action) ? _action : null,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l.activityAllActions),
                  ),
                  for (final a in _actions)
                    DropdownMenuItem<String?>(
                      value: a,
                      child: Text(
                        auditActionLabel(l, a),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  _action = v;
                  _load(reset: true);
                },
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: TextField(
                  key: const ValueKey('activity-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l.activitySearchHint,
                    suffixIcon: IconButton(
                      key: const ValueKey('activity-search-go'),
                      tooltip: l.activitySearchHint,
                      icon: const Icon(Icons.search),
                      onPressed: _submit,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
        else if (!_loading && _items.isEmpty)
          SurfaceCard(
            child: Text(l.activityEmpty, key: const ValueKey('activity-empty')),
          ),
        for (final e in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              padding: 12,
              child: Column(
                key: ValueKey('activity-row-${e.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auditActionLabel(l, e.action),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    l.activityLine(
                      e.actorName.isEmpty ? l.activitySystem : e.actorName,
                      formatStamp(e.createdAt),
                    ),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && _items.length < _count)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('activity-more'),
              onPressed: () => _load(reset: false),
              child: Text(l.activityLoadMore),
            ),
          ),
      ],
    );
  }
}
