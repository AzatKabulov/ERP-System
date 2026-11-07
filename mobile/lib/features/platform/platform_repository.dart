import '../../core/api/api_client.dart';
import 'platform_models.dart';

/// Everything the platform owner's pages ask of the server (`/api/v1/platform/`, which only an
/// operator may open). Plain requests: a subscription change is confirmed on screen first, so no
/// operation key is needed.
class PlatformRepository {
  PlatformRepository(this.api);

  final ApiClient api;

  static const _base = '/api/v1/platform';

  List<T> _list<T>(ApiResponse r, T Function(Map<String, dynamic>) make) => [
    for (final item in r.map['results'] as List)
      make((item as Map).cast<String, dynamic>()),
  ];

  Future<Overview> overview() async =>
      Overview.fromJson((await api.get('$_base/overview/')).map);

  Future<List<ClientRow>> clients({
    String state = '',
    String query = '',
  }) async => _list(
    await api.get(
      '$_base/clients/',
      query: {
        if (state.isNotEmpty) 'state': state,
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    ),
    ClientRow.fromJson,
  );

  Future<ClientDetail> client(String id) async =>
      ClientDetail.fromJson((await api.get('$_base/clients/$id/')).map);

  Future<ClientDetail> saveContact(
    String id, {
    required String name,
    required String phone,
    required String email,
  }) async => ClientDetail.fromJson(
    (await api.patch(
      '$_base/clients/$id/',
      body: {'name': name, 'phone': phone, 'email': email},
    )).map,
  );

  Future<ClientDetail> addNote(String id, String text) async =>
      ClientDetail.fromJson(
        (await api.post('$_base/clients/$id/notes/', body: {'text': text})).map,
      );

  Future<NewClientResult> createClient(Map<String, Object?> fields) async {
    final map = (await api.post('$_base/clients/', body: fields)).map;
    return NewClientResult(
      detail: ClientDetail.fromJson((map['client'] as Map).cast()),
      login: map['login'] as String,
      password: map['password'] as String,
    );
  }

  /// The review step: nothing changes; says which dates would.
  Future<ActionPreview> review(
    String id,
    String action,
    Map<String, Object?> fields,
  ) async {
    final map = (await api.post(
      '$_base/clients/$id/actions/$action/',
      body: {...fields, 'step': 'review'},
    )).map;
    final preview = (map['preview'] as Map?) ?? const {};
    DateTime? day(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return ActionPreview(
      oldEnd: day(map['old_end'])?.toLocal(),
      newEnd: day(preview['new_end']),
    );
  }

  Future<ActionOutcome> perform(
    String id,
    String action,
    Map<String, Object?> fields,
  ) async {
    final map = (await api.post(
      '$_base/clients/$id/actions/$action/',
      body: {...fields, 'step': 'confirm'},
    )).map;
    return ActionOutcome(
      detail: ClientDetail.fromJson((map['client'] as Map).cast()),
      secret: map['secret'] as String?,
    );
  }

  Future<List<PlanRow>> plans() async =>
      _list(await api.get('$_base/plans/'), PlanRow.fromJson);

  Future<PlanRow> savePlan(String id, {String? price, bool? isActive}) async =>
      PlanRow.fromJson(
        (await api.patch(
          '$_base/plans/$id/',
          body: {
            if (price != null) 'price': price.isEmpty ? null : price,
            'is_active': ?isActive,
          },
        )).map,
      );

  Future<List<TicketRow>> tickets({String status = ''}) async => _list(
    await api.get(
      '$_base/support/',
      query: {if (status.isNotEmpty) 'status': status},
    ),
    TicketRow.fromJson,
  );

  Future<TicketRow> ticket(String id) async =>
      TicketRow.fromJson((await api.get('$_base/support/$id/')).map);

  Future<TicketRow> reply(String id, String text, {bool close = false}) async =>
      TicketRow.fromJson(
        (await api.post(
          '$_base/support/$id/reply/',
          body: {'text': text, 'close': close},
        )).map,
      );

  Future<TicketRow> closeTicket(String id) async =>
      TicketRow.fromJson((await api.post('$_base/support/$id/close/')).map);

  Future<List<NoticeRow>> notices() async =>
      _list(await api.get('$_base/announcements/'), NoticeRow.fromJson);

  Future<NoticeRow> createNotice({
    required String messageRu,
    required String messageTk,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async => NoticeRow.fromJson(
    (await api.post(
      '$_base/announcements/',
      body: {
        'message_ru': messageRu,
        'message_tk': messageTk,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'is_active': true,
      },
    )).map,
  );

  Future<NoticeRow> setNoticeActive(String id, bool active) async =>
      NoticeRow.fromJson(
        (await api.patch(
          '$_base/announcements/$id/',
          body: {'is_active': active},
        )).map,
      );
}
