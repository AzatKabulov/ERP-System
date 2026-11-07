import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/format/format_stamp.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../admin/administration_screen.dart' show roleLabel;
import '../shared/async_section.dart';
import 'client_action_dialog.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_support_screen.dart';
import 'platform_widgets.dart';

/// One client: where the subscription stands, the buttons that change it, contacts, the history
/// of every payment and change, our own notes, their people and their questions to us.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.repository,
    required this.clientId,
    this.initial,
  });

  final PlatformRepository repository;
  final String clientId;
  final ClientDetail? initial;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  ClientDetail? _detail;
  Object? _loadError;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  ApiException? _error;
  bool _savedContact = false;

  PlatformRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _adopt(widget.initial!);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  void _adopt(ClientDetail d) {
    _detail = d;
    _name.text = d.contactName;
    _phone.text = d.contactPhone;
    _email.text = d.contactEmail;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await repo.client(widget.clientId);
      if (mounted) setState(() => _adopt(d));
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _run(PlatformAction action) async {
    final detail = _detail;
    if (detail == null) return;
    final updated = await showClientAction(
      context,
      repository: repo,
      detail: detail,
      action: action,
    );
    if (updated != null && mounted) setState(() => _adopt(updated));
  }

  Future<void> _saveContact() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _savedContact = false;
    });
    try {
      final d = await repo.saveContact(
        widget.clientId,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
      );
      if (mounted) {
        setState(() {
          _adopt(d);
          _savedContact = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final d = await repo.addNote(widget.clientId, text);
      if (mounted) {
        _note.clear();
        setState(() => _detail = d);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- sections --------------------------------------------------------------------------

  Widget _status(ClientDetail d) {
    final l = strings(context);
    final r = d.row;
    return SurfaceCard(
      featured: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.storeName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StateBadge(r),
            ],
          ),
          const SizedBox(height: 14),
          FactRow(l.pfPlan, r.plan ?? l.pfNoPlan),
          FactRow(
            l.pfPaidUntil,
            r.endsAt == null || r.state == 'free' ? l.pfNoEnd : endsText(l, r),
          ),
          if (r.graceEndsAt != null && r.state != 'free')
            FactRow(l.pfGraceUntil, formatDay(r.graceEndsAt!)),
          FactRow(
            l.pfLastPayment,
            r.lastPaymentAt == null ? l.pfNever : formatStamp(r.lastPaymentAt!),
          ),
          FactRow(
            l.pfLastSignIn,
            r.lastSignIn == null ? l.pfNever : formatStamp(r.lastSignIn!),
          ),
          FactRow(l.pfSales30, '${r.sales30d}'),
        ],
      ),
    );
  }

  Widget _actions(ClientDetail d) {
    final l = strings(context);
    final list = <PlatformAction>[
      PlatformAction.renew,
      PlatformAction.extend,
      PlatformAction.correct,
      d.suspended ? PlatformAction.resume : PlatformAction.suspend,
      d.free ? PlatformAction.freeOff : PlatformAction.freeOn,
      PlatformAction.resetPassword,
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardTitle(l.pfActions),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in list)
                a == PlatformAction.renew
                    ? PrimaryButton(
                        key: ValueKey('pf-act-${a.server}'),
                        label: a.title(l),
                        icon: a.icon,
                        onPressed: () => _run(a),
                      )
                    : OutlinedButton.icon(
                        key: ValueKey('pf-act-${a.server}'),
                        onPressed: () => _run(a),
                        style: a.dangerous
                            ? OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: BorderSide(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              )
                            : null,
                        icon: AppIcon(a.icon, size: 18),
                        label: Text(a.title(l)),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contact(ClientDetail d) {
    final l = strings(context);
    Widget field(String label, TextEditingController c, String key) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledField(
        label: label,
        child: TextField(
          key: ValueKey(key),
          controller: c,
          enabled: !_busy,
          onChanged: (_) => setState(() => _savedContact = false),
        ),
      ),
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cardTitle(l.pfContact),
          field(l.pfContactName, _name, 'pf-contact-name'),
          field(l.pfContactPhone, _phone, 'pf-contact-phone'),
          field(l.pfContactEmail, _email, 'pf-contact-email'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                fieldProblem(l, _error, 'email') ?? generalProblem(l, _error),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          Row(
            children: [
              OutlinedButton(
                key: const ValueKey('pf-contact-save'),
                onPressed: _busy ? null : _saveContact,
                child: Text(l.save),
              ),
              if (_savedContact) ...[
                const SizedBox(width: 12),
                Text(
                  l.pfContactSaved,
                  key: const ValueKey('pf-contact-saved'),
                  style: TextStyle(color: AppColors.success),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _notes(ClientDetail d) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cardTitle(l.pfNotes),
          TextField(
            key: const ValueKey('pf-note-field'),
            controller: _note,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l.pfNoteHint,
              suffixIcon: IconButton(
                key: const ValueKey('pf-note-add'),
                tooltip: l.pfAddNote,
                icon: AppIcon(AppIcons.send, color: AppColors.blue),
                onPressed: _busy ? null : _addNote,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final n in d.notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.text, style: const TextStyle(height: 1.4)),
                  Text(
                    '${n.by} · ${n.at == null ? '' : formatStamp(n.at!)}',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _history(ClientDetail d) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cardTitle(l.pfHistory),
          if (d.events.isEmpty)
            Text(l.pfNoHistory, style: TextStyle(color: AppColors.muted)),
          for (final e in d.events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            eventLabel(l, e.kind),
                            if (e.plan != null) e.plan!,
                            if (e.days != null) '+${e.days}',
                          ].join(' · '),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            if (e.newUntil != null)
                              l.pfEndsOn(formatDay(e.newUntil!)),
                            if (e.note.isNotEmpty) e.note,
                            if (e.reference.isNotEmpty) e.reference,
                          ].join(' · '),
                          style: TextStyle(
                            color: AppColors.neutral,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${e.by} · ${e.at == null ? '' : formatStamp(e.at!)}',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (e.amount != null)
                    Text(
                      '${e.amount} ${e.currency}'
                      '${e.method.isEmpty ? '' : ' · ${methodLabel(l, e.method)}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _people(ClientDetail d) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cardTitle(l.pfPeople),
          for (final p in d.people)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name.isEmpty ? p.username : '${p.name} (${p.username})',
                      style: TextStyle(
                        color: p.active ? null : AppColors.muted,
                      ),
                    ),
                  ),
                  Text(
                    roleLabel(l, p.role),
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tickets(ClientDetail d) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cardTitle(l.pfTickets),
          for (final t in d.tickets)
            InkWell(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      TicketScreen(repository: repo, ticketId: t.id),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(t.subject)),
                    StatusPill(
                      label: ticketLabel(l, t.status),
                      tone: ticketTone(t.status),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final gap = const SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(title: Text(d?.row.storeName ?? '')),
      body: d == null
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
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _status(d),
                        gap,
                        _actions(d),
                        gap,
                        _contact(d),
                        gap,
                        _notes(d),
                        gap,
                        _history(d),
                        gap,
                        _people(d),
                        if (d.tickets.isNotEmpty) ...[gap, _tickets(d)],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
