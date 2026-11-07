import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../shared/async_section.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';
import '../../widgets/app_route.dart';

/// The questions the shops wrote to us, waiting ones first.
class PlatformSupportScreen extends StatefulWidget {
  const PlatformSupportScreen({
    super.key,
    required this.repository,
    required this.onOpenClient,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onOpenClient;

  @override
  State<PlatformSupportScreen> createState() => _PlatformSupportScreenState();
}

class _PlatformSupportScreenState extends State<PlatformSupportScreen> {
  String _status = '';
  int _reload = 0;

  Future<void> _open(TicketRow t) async {
    await Navigator.of(context).push<void>(
      appRoute(
        builder: (_) => TicketScreen(
          repository: widget.repository,
          ticketId: t.id,
          onOpenClient: widget.onOpenClient,
        ),
      ),
    );
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768;
    final filters = <(String, String)>[
      ('', l.pfFilterAll),
      ('open', l.pfTicketOpen),
      ('answered', l.pfTicketAnswered),
      ('closed', l.pfTicketClosed),
    ];
    return SingleChildScrollView(
      padding: pagePadding(context, compact: narrow),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(title: l.pfSupport),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in filters)
                    AppPill(
                      key: ValueKey(
                        'pf-ticket-filter-${value.isEmpty ? 'all' : value}',
                      ),
                      label: label,
                      selected: _status == value,
                      onTap: () => setState(() => _status = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              AsyncSection<List<TicketRow>>(
                key: ValueKey('tickets-$_status-$_reload'),
                load: () => widget.repository.tickets(status: _status),
                builder: (context, rows) {
                  if (rows.isEmpty) {
                    return SurfaceCard(
                      child: EmptyState(
                        key: const ValueKey('pf-no-tickets'),
                        title: l.pfNoTickets,
                        icon: AppIcons.chat,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final t in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SurfaceCard(
                            key: ValueKey('ticket-${t.id}'),
                            flat: true,
                            padding: 16,
                            onTap: () => _open(t),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.subject,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${t.storeName} · '
                                        '${t.at == null ? '' : formatStamp(t.at!)}',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                StatusPill(
                                  label: ticketLabel(l, t.status),
                                  tone: ticketTone(t.status),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One conversation: what the shop wrote, our answers, and the reply box.
class TicketScreen extends StatefulWidget {
  const TicketScreen({
    super.key,
    required this.repository,
    required this.ticketId,
    this.onOpenClient,
  });

  final PlatformRepository repository;
  final String ticketId;

  /// Opens the shop's own page (after closing this one).
  final ValueChanged<String>? onOpenClient;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  TicketRow? _ticket;
  Object? _loadError;
  final _reply = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final t = await widget.repository.ticket(widget.ticketId);
      if (mounted) setState(() => _ticket = t);
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _send({bool close = false}) async {
    final text = _reply.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await widget.repository.reply(
        widget.ticketId,
        text,
        close: close,
      );
      if (mounted) {
        _reply.clear();
        setState(() => _ticket = t);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final t = await widget.repository.closeTicket(widget.ticketId);
      if (mounted) setState(() => _ticket = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(title: Text(t?.subject ?? '')),
      body: t == null
          ? Center(
              child: _loadError != null
                  ? ErrorPanel(error: _loadError!, onRetry: _load)
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t.storeName} · ${l.pfAskedBy(t.askedBy)}',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                            StatusPill(
                              label: ticketLabel(l, t.status),
                              tone: ticketTone(t.status),
                            ),
                          ],
                        ),
                        if (t.clientId != null && widget.onOpenClient != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const ValueKey('pf-ticket-client'),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onOpenClient!(t.clientId!);
                              },
                              child: Text(l.pfOpenClient),
                            ),
                          ),
                        const SizedBox(height: 12),
                        for (final m in t.messages)
                          Align(
                            alignment: m.fromStore
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(maxWidth: 520),
                              decoration: BoxDecoration(
                                color: m.fromStore
                                    ? AppColors.surfaceSoft
                                    : AppColors.tint,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${m.fromStore ? l.pfFromStore : l.pfFromYou}'
                                    ' · ${m.at == null ? '' : formatStamp(m.at!)}',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.text,
                                    style: const TextStyle(height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (t.status != 'closed') ...[
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('pf-reply-field'),
                            controller: _reply,
                            enabled: !_busy,
                            minLines: 2,
                            maxLines: 6,
                            maxLength: 4000,
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: l.pfReplyHint,
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                generalProblem(l, _error),
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              PrimaryButton(
                                key: const ValueKey('pf-reply-send'),
                                label: l.pfSendReply,
                                icon: AppIcons.send,
                                onPressed: _busy ? null : () => _send(),
                              ),
                              OutlinedButton(
                                key: const ValueKey('pf-reply-close'),
                                onPressed: _busy
                                    ? null
                                    : () => _send(close: true),
                                child: Text(l.pfReplyClose),
                              ),
                              TextButton(
                                key: const ValueKey('pf-ticket-close'),
                                onPressed: _busy ? null : _close,
                                child: Text(l.pfCloseTicket),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
