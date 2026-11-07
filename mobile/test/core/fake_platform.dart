import 'dart:convert';

import 'package:http/http.dart' as http;

/// The platform owner's side of the API for the widget tests (`/api/v1/platform/`): a few clients
/// in different states, with the same two-step rule as the real server (a button is "reviewed"
/// before it is done) and a temporary password shown once.
class FakePlatform {
  final DateTime now = DateTime.now().toUtc();

  late final List<Map<String, dynamic>> clients = [
    _client('c-1', 'Willy Wonka', 'active', daysLeft: 20, plan: 'Месяц'),
    _client('c-2', 'Late Shop', 'grace', daysLeft: -2, plan: 'Месяц'),
    _client('c-3', 'Soon Shop', 'expiring', daysLeft: 3, plan: 'Месяц'),
  ];

  final Map<String, List<Map<String, dynamic>>> events = {};
  final Map<String, List<Map<String, dynamic>>> notes = {};

  final List<Map<String, dynamic>> plans = [
    {
      'id': 'p-1',
      'code': 'monthly',
      'name': 'Месяц',
      'months': 1,
      'price': '150.00',
      'currency': 'TMT',
      'is_active': true,
    },
    {
      'id': 'p-2',
      'code': 'custom',
      'name': 'Свои дни',
      'months': null,
      'price': null,
      'currency': 'TMT',
      'is_active': true,
    },
  ];

  final List<Map<String, dynamic>> tickets = [
    {
      'id': 't-1',
      'store_name': 'Willy Wonka',
      'subject': 'Принтер не печатает',
      'status': 'open',
      'asked_by': 'Willy',
      'screen': 'sales',
      'at': DateTime.now().toUtc().toIso8601String(),
      'client_id': 'c-1',
      'messages': <Map<String, dynamic>>[
        {
          'from_store': true,
          'by': 'Willy',
          'text': 'Чек не выходит',
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    },
  ];

  final List<Map<String, dynamic>> notices = [];

  /// Every request the app made, as "METHOD path", for tests to look at.
  final List<String> calls = [];

  Map<String, dynamic> _client(
    String id,
    String name,
    String state, {
    required int daysLeft,
    required String plan,
  }) => {
    'id': id,
    'business_id': 'biz-$id',
    'store_name': name,
    'state': state,
    'is_trial': false,
    'plan': plan,
    'ends_at': now.add(Duration(days: daysLeft)).toIso8601String(),
    'grace_ends_at': now.add(Duration(days: daysLeft + 7)).toIso8601String(),
    'days_left': daysLeft,
    'owner_login': name.toLowerCase().replaceAll(' ', '-'),
    'owner_name': 'Owner of $name',
    'phone': '+993 65 000000',
    'last_payment_at': now.toIso8601String(),
    'last_sign_in': null,
    'staff': 1,
    'sales_30d': 4,
    'contact': {
      'name': 'Owner of $name',
      'phone': '+993 65 000000',
      'email': '',
    },
    'suspended': false,
    'free': false,
  };

  http.Response _json(int status, Object? body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response _invalid(Map<String, String> fields) => _json(400, {
    'error': {
      'code': 'validation_error',
      'message': 'diagnostic',
      'fields': {
        for (final e in fields.entries)
          e.key: [
            {'code': 'required', 'message': e.value},
          ],
      },
    },
  });

  Map<String, dynamic> _detail(Map<String, dynamic> c) => {
    ...c,
    'paid_until': c['ends_at'],
    'events': events[c['id']] ?? const [],
    'notes': notes[c['id']] ?? const [],
    'people': [
      {
        'username': c['owner_login'],
        'name': c['owner_name'],
        'role': 'owner',
        'active': true,
        'last_sign_in': null,
      },
    ],
    'support': [
      for (final t in tickets)
        if (t['client_id'] == c['id'])
          {'id': t['id'], 'subject': t['subject'], 'status': t['status']},
    ],
  };

  Map<String, dynamic> get overview {
    int n(bool Function(Map<String, dynamic>) f) => clients.where(f).length;
    final attention = clients
        .where((c) => ['expiring', 'grace', 'read_only'].contains(c['state']))
        .toList();
    return {
      'total': clients.length,
      'counts': {
        'active': n((c) => ['active', 'expiring'].contains(c['state'])),
        'trial': n((c) => c['is_trial'] == true),
        'expiring': n((c) => c['state'] == 'expiring'),
        'grace': n((c) => c['state'] == 'grace'),
        'read_only': n((c) => c['state'] == 'read_only'),
        'suspended': n((c) => c['state'] == 'suspended'),
        'free': n((c) => c['state'] == 'free'),
      },
      'attention': attention,
      'income_this_month': {'TMT': '150.00'},
      'new_30_days': 1,
      'lapsed_this_month': 1,
      'recent_payments': [
        {
          'client_id': 'c-1',
          'store_name': 'Willy Wonka',
          'amount': '150.00',
          'currency': 'TMT',
          'method': 'cash',
          'at': now.toIso8601String(),
        },
      ],
    };
  }

  DateTime _plusMonth(String endsAt) {
    final d = DateTime.parse(endsAt);
    return DateTime.utc(d.year, d.month + 1, d.day);
  }

  http.Response? handle(
    http.Request request,
    String path,
    Map<String, dynamic> body,
  ) {
    const base = '/api/v1/platform/';
    if (!path.startsWith(base)) return null;
    calls.add('${request.method} $path');
    final rest = path.substring(base.length);
    final get = request.method == 'GET';

    if (rest == 'overview/') return _json(200, overview);
    if (rest == 'plans/') return _json(200, {'results': plans});
    if (rest == 'clients/' && get) {
      final state = request.url.queryParameters['state'] ?? '';
      final q = (request.url.queryParameters['q'] ?? '').toLowerCase();
      final rows = clients.where((c) {
        if (q.isNotEmpty && !'${c['store_name']}'.toLowerCase().contains(q)) {
          return false;
        }
        return switch (state) {
          '' => true,
          'attention' => [
            'expiring',
            'grace',
            'read_only',
          ].contains(c['state']),
          'active' => ['active', 'expiring'].contains(c['state']),
          _ => c['state'] == state,
        };
      }).toList();
      return _json(200, {'results': rows});
    }
    if (rest == 'clients/') {
      if ('${body['store_name']}'.trim().isEmpty) {
        return _invalid({'store_name': 'Required'});
      }
      final c = _client(
        'c-${clients.length + 1}',
        '${body['store_name']}',
        'active',
        daysLeft: 14,
        plan: '',
      )..['is_trial'] = true;
      clients.add(c);
      return _json(201, {
        'client': _detail(c),
        'login': 'new-shop',
        'password': 'Temp-Pass-1234',
      });
    }
    final client = RegExp(r'^clients/([^/]+)/$').firstMatch(rest);
    if (client != null) {
      final c = clients.firstWhere((c) => c['id'] == client.group(1));
      if (get) return _json(200, _detail(c));
      final contact = c['contact'] as Map;
      if (body.containsKey('phone')) contact['phone'] = body['phone'];
      if (body.containsKey('name')) contact['name'] = body['name'];
      return _json(200, _detail(c));
    }
    final note = RegExp(r'^clients/([^/]+)/notes/$').firstMatch(rest);
    if (note != null) {
      (notes[note.group(1)!] ??= []).insert(0, {
        'text': body['text'],
        'by': 'boss',
        'at': now.toIso8601String(),
      });
      final c = clients.firstWhere((c) => c['id'] == note.group(1));
      return _json(201, _detail(c));
    }
    final action = RegExp(
      r'^clients/([^/]+)/actions/([^/]+)/$',
    ).firstMatch(rest);
    if (action != null) {
      final c = clients.firstWhere((c) => c['id'] == action.group(1));
      final name = action.group(2)!;
      final note = '${body['note'] ?? ''}'.trim();
      if ([
            'extend',
            'correct',
            'suspend',
            'free-on',
            'free-off',
          ].contains(name) &&
          note.isEmpty) {
        return _invalid({'note': 'This field is required.'});
      }
      if (body['step'] != 'confirm') {
        final preview = <String, dynamic>{};
        if (name == 'renew') {
          preview['new_end'] = _plusMonth(
            '${c['ends_at']}',
          ).toIso8601String().substring(0, 10);
        }
        return _json(200, {
          'step': 'review',
          'lines': ['review of $name'],
          'preview': preview,
          'old_end': c['ends_at'],
        });
      }
      String? secret;
      switch (name) {
        case 'renew':
          c['ends_at'] = _plusMonth('${c['ends_at']}').toIso8601String();
          c['state'] = 'active';
          c['days_left'] = 51;
          (events[c['id']] ??= []).insert(0, {
            'kind': 'renew',
            'plan': 'Месяц',
            'months': 1,
            'days': null,
            'old_until': null,
            'new_until': c['ends_at'],
            'amount': '150.00',
            'currency': 'TMT',
            'method': 'cash',
            'reference': '',
            'note': '',
            'by': 'boss',
            'at': now.toIso8601String(),
          });
        case 'suspend':
          c['state'] = 'suspended';
          c['suspended'] = true;
        case 'resume':
          c['state'] = 'active';
          c['suspended'] = false;
        case 'reset-password':
          secret = 'Reset-Pass-5678';
      }
      return _json(200, {
        'step': 'done',
        'secret': secret,
        'client': _detail(c),
      });
    }
    if (rest == 'support/') {
      final status = request.url.queryParameters['status'] ?? '';
      return _json(200, {
        'results': [
          for (final t in tickets)
            if (status.isEmpty || t['status'] == status) t,
        ],
      });
    }
    final ticket = RegExp(
      r'^support/([^/]+)/(reply/|close/)?$',
    ).firstMatch(rest);
    if (ticket != null) {
      final t = tickets.firstWhere((t) => t['id'] == ticket.group(1));
      if (ticket.group(2) == 'reply/') {
        (t['messages'] as List).add({
          'from_store': false,
          'by': 'boss',
          'text': body['text'],
          'at': now.toIso8601String(),
        });
        t['status'] = body['close'] == true ? 'closed' : 'answered';
      } else if (ticket.group(2) == 'close/') {
        t['status'] = 'closed';
      }
      return _json(ticket.group(2) == 'reply/' ? 201 : 200, t);
    }
    if (rest == 'announcements/') {
      if (!get) {
        final n = {
          'id': 'n-${notices.length + 1}',
          'message_ru': body['message_ru'],
          'message_tk': body['message_tk'],
          'starts_at': body['starts_at'],
          'ends_at': body['ends_at'],
          'is_active': true,
        };
        notices.insert(0, n);
        return _json(201, n);
      }
      return _json(200, {'results': notices});
    }
    final notice = RegExp(r'^announcements/([^/]+)/$').firstMatch(rest);
    if (notice != null) {
      final n = notices.firstWhere((n) => n['id'] == notice.group(1));
      n['is_active'] = body['is_active'];
      return _json(200, n);
    }
    return _json(404, {
      'error': {'code': 'not_found', 'message': 'diagnostic'},
    });
  }
}
