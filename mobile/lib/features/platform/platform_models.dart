import 'package:flutter/foundation.dart';

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// One client in a list: a shop and where its subscription stands.
@immutable
class ClientRow {
  const ClientRow({
    required this.id,
    required this.storeName,
    required this.state,
    required this.isTrial,
    required this.plan,
    required this.endsAt,
    required this.graceEndsAt,
    required this.daysLeft,
    required this.ownerLogin,
    required this.ownerName,
    required this.phone,
    required this.lastPaymentAt,
    required this.lastSignIn,
    required this.staff,
    required this.sales30d,
  });

  final String id;
  final String storeName;

  /// free, active, expiring, grace, read_only or suspended.
  final String state;
  final bool isTrial;
  final String? plan;
  final DateTime? endsAt;
  final DateTime? graceEndsAt;
  final int? daysLeft;
  final String ownerLogin;
  final String ownerName;
  final String phone;
  final DateTime? lastPaymentAt;
  final DateTime? lastSignIn;
  final int staff;
  final int sales30d;

  factory ClientRow.fromJson(Map<String, dynamic> j) => ClientRow(
    id: j['id'] as String,
    storeName: j['store_name'] as String,
    state: j['state'] as String,
    isTrial: (j['is_trial'] as bool?) ?? false,
    plan: j['plan'] as String?,
    endsAt: _time(j['ends_at']),
    graceEndsAt: _time(j['grace_ends_at']),
    daysLeft: j['days_left'] as int?,
    ownerLogin: (j['owner_login'] as String?) ?? '',
    ownerName: (j['owner_name'] as String?) ?? '',
    phone: (j['phone'] as String?) ?? '',
    lastPaymentAt: _time(j['last_payment_at']),
    lastSignIn: _time(j['last_sign_in']),
    staff: (j['staff'] as int?) ?? 0,
    sales30d: (j['sales_30d'] as int?) ?? 0,
  );
}

@immutable
class PaymentRow {
  const PaymentRow({
    required this.clientId,
    required this.storeName,
    required this.amount,
    required this.currency,
    required this.method,
    required this.at,
  });
  final String clientId;
  final String storeName;
  final String amount;
  final String currency;
  final String method;
  final DateTime? at;

  factory PaymentRow.fromJson(Map<String, dynamic> j) => PaymentRow(
    clientId: j['client_id'] as String,
    storeName: j['store_name'] as String,
    amount: '${j['amount']}',
    currency: (j['currency'] as String?) ?? '',
    method: (j['method'] as String?) ?? '',
    at: _time(j['at']),
  );
}

@immutable
class Overview {
  const Overview({
    required this.total,
    required this.counts,
    required this.attention,
    required this.income,
    required this.new30,
    required this.payments,
  });
  final int total;
  final Map<String, int> counts;
  final List<ClientRow> attention;
  final Map<String, String> income;
  final int new30;
  final List<PaymentRow> payments;

  factory Overview.fromJson(Map<String, dynamic> j) => Overview(
    total: j['total'] as int,
    counts: {
      for (final e in (j['counts'] as Map).entries) '${e.key}': e.value as int,
    },
    attention: [
      for (final r in j['attention'] as List)
        ClientRow.fromJson((r as Map).cast<String, dynamic>()),
    ],
    income: {
      for (final e in (j['income_this_month'] as Map).entries)
        '${e.key}': '${e.value}',
    },
    new30: (j['new_30_days'] as int?) ?? 0,
    payments: [
      for (final r in j['recent_payments'] as List)
        PaymentRow.fromJson((r as Map).cast<String, dynamic>()),
    ],
  );
}

@immutable
class HistoryEvent {
  const HistoryEvent({
    required this.kind,
    required this.plan,
    required this.days,
    required this.newUntil,
    required this.amount,
    required this.currency,
    required this.method,
    required this.reference,
    required this.note,
    required this.by,
    required this.at,
  });
  final String kind;
  final String? plan;
  final int? days;
  final DateTime? newUntil;
  final String? amount;
  final String currency;
  final String method;
  final String reference;
  final String note;
  final String by;
  final DateTime? at;

  factory HistoryEvent.fromJson(Map<String, dynamic> j) => HistoryEvent(
    kind: j['kind'] as String,
    plan: j['plan'] as String?,
    days: j['days'] as int?,
    newUntil: _time(j['new_until']),
    amount: j['amount'] == null ? null : '${j['amount']}',
    currency: (j['currency'] as String?) ?? '',
    method: (j['method'] as String?) ?? '',
    reference: (j['reference'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    by: (j['by'] as String?) ?? '',
    at: _time(j['at']),
  );
}

@immutable
class ClientNoteRow {
  const ClientNoteRow({required this.text, required this.by, required this.at});
  final String text;
  final String by;
  final DateTime? at;
}

@immutable
class PersonRow {
  const PersonRow({
    required this.username,
    required this.name,
    required this.role,
    required this.active,
    required this.lastSignIn,
  });
  final String username;
  final String name;
  final String role;
  final bool active;
  final DateTime? lastSignIn;
}

@immutable
class TicketRef {
  const TicketRef({
    required this.id,
    required this.subject,
    required this.status,
  });
  final String id;
  final String subject;
  final String status;
}

/// A client in full: the row, contacts, the history, notes, people and open questions.
@immutable
class ClientDetail {
  const ClientDetail({
    required this.row,
    required this.contactName,
    required this.contactPhone,
    required this.contactEmail,
    required this.suspended,
    required this.free,
    required this.events,
    required this.notes,
    required this.people,
    required this.tickets,
  });
  final ClientRow row;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
  final bool suspended;
  final bool free;
  final List<HistoryEvent> events;
  final List<ClientNoteRow> notes;
  final List<PersonRow> people;
  final List<TicketRef> tickets;

  factory ClientDetail.fromJson(Map<String, dynamic> j) {
    final contact = (j['contact'] as Map).cast<String, dynamic>();
    return ClientDetail(
      row: ClientRow.fromJson(j),
      contactName: (contact['name'] as String?) ?? '',
      contactPhone: (contact['phone'] as String?) ?? '',
      contactEmail: (contact['email'] as String?) ?? '',
      suspended: (j['suspended'] as bool?) ?? false,
      free: (j['free'] as bool?) ?? false,
      events: [
        for (final e in j['events'] as List)
          HistoryEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
      notes: [
        for (final n in j['notes'] as List)
          ClientNoteRow(
            text: (n as Map)['text'] as String,
            by: (n['by'] as String?) ?? '',
            at: _time(n['at']),
          ),
      ],
      people: [
        for (final p in j['people'] as List)
          PersonRow(
            username: (p as Map)['username'] as String,
            name: (p['name'] as String?) ?? '',
            role: p['role'] as String,
            active: (p['active'] as bool?) ?? true,
            lastSignIn: _time(p['last_sign_in']),
          ),
      ],
      tickets: [
        for (final t in j['support'] as List)
          TicketRef(
            id: (t as Map)['id'] as String,
            subject: t['subject'] as String,
            status: t['status'] as String,
          ),
      ],
    );
  }
}

@immutable
class PlanRow {
  const PlanRow({
    required this.id,
    required this.name,
    required this.months,
    required this.price,
    required this.currency,
    required this.isActive,
  });
  final String id;
  final String name;
  final int? months;
  final String? price;
  final String currency;
  final bool isActive;

  /// A package that adds whole months (the free-form "custom days" one has none).
  bool get sellable => isActive && months != null;

  factory PlanRow.fromJson(Map<String, dynamic> j) => PlanRow(
    id: j['id'] as String,
    name: j['name'] as String,
    months: j['months'] as int?,
    price: j['price'] == null ? null : '${j['price']}',
    currency: (j['currency'] as String?) ?? 'TMT',
    isActive: (j['is_active'] as bool?) ?? true,
  );
}

/// What a button would do (the "review" step): the dates it changes.
@immutable
class ActionPreview {
  const ActionPreview({this.oldEnd, this.newEnd});
  final DateTime? oldEnd;
  final DateTime? newEnd;
}

@immutable
class ActionOutcome {
  const ActionOutcome({required this.detail, this.secret});
  final ClientDetail detail;

  /// A password made by "reset the owner's password": shown once.
  final String? secret;
}

@immutable
class NewClientResult {
  const NewClientResult({
    required this.detail,
    required this.login,
    required this.password,
  });
  final ClientDetail detail;
  final String login;
  final String password;
}

@immutable
class TicketRow {
  const TicketRow({
    required this.id,
    required this.storeName,
    required this.subject,
    required this.status,
    required this.askedBy,
    required this.at,
    this.clientId,
    this.messages = const [],
  });
  final String id;
  final String storeName;
  final String subject;
  final String status;
  final String askedBy;
  final DateTime? at;
  final String? clientId;
  final List<TicketMessage> messages;

  factory TicketRow.fromJson(Map<String, dynamic> j) => TicketRow(
    id: j['id'] as String,
    storeName: j['store_name'] as String,
    subject: j['subject'] as String,
    status: j['status'] as String,
    askedBy: (j['asked_by'] as String?) ?? '',
    at: _time(j['at']),
    clientId: j['client_id'] as String?,
    messages: [
      for (final m in (j['messages'] as List?) ?? const [])
        TicketMessage(
          fromStore: (m as Map)['from_store'] as bool,
          by: (m['by'] as String?) ?? '',
          text: m['text'] as String,
          at: _time(m['at']),
        ),
    ],
  );
}

@immutable
class TicketMessage {
  const TicketMessage({
    required this.fromStore,
    required this.by,
    required this.text,
    required this.at,
  });
  final bool fromStore;
  final String by;
  final String text;
  final DateTime? at;
}

@immutable
class NoticeRow {
  const NoticeRow({
    required this.id,
    required this.messageRu,
    required this.messageTk,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });
  final String id;
  final String messageRu;
  final String messageTk;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  factory NoticeRow.fromJson(Map<String, dynamic> j) => NoticeRow(
    id: j['id'] as String,
    messageRu: j['message_ru'] as String,
    messageTk: (j['message_tk'] as String?) ?? '',
    startsAt: _time(j['starts_at'])!,
    endsAt: _time(j['ends_at'])!,
    isActive: (j['is_active'] as bool?) ?? true,
  );
}
