import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_ledger.dart';

/// A tiny in-memory stand-in for the real API, with the same idempotency rules:
/// the same key replays the stored outcome, a different body with the same key is
/// refused, and an action is performed once per key.
class FakeServer {
  FakeServer() {
    client = MockClient(_handle);
  }

  late final MockClient client;

  /// Stock ledger, suppliers and purchase orders (see fake_ledger.dart).
  late final FakeLedger ledger = FakeLedger(this);

  // --- configuration -------------------------------------------------------
  String accessToken = 'access-1';
  String refreshToken = 'refresh-1';
  int tokenCounter = 1;
  bool refreshRejected = false;
  bool reachable = true;

  /// The next N operation POSTs are performed, then the answer is lost.
  int dropResponseAfterCommit = 0;

  /// The next N operation POSTs fail with 500 before doing anything.
  int failBeforeCommit = 0;

  /// The next operation POST is refused with this 4xx error code.
  String? rejectWith;

  /// Make the next authenticated call answer 401 (expired access token).
  bool expireAccess = false;

  // --- recorded state ------------------------------------------------------
  final List<Map<String, dynamic>> performed =
      []; // actions that really happened
  final Map<
    String,
    ({String fingerprint, int status, Map<String, dynamic> body})
  >
  records = {};
  final List<String> log = [];
  int refreshCalls = 0;
  final List<Map<String, String>> requestHeaders = [];

  /// What the signed-in user's role may do (returned by /me).
  List<String> permissions = [
    'business.view',
    'business.manage',
    'location.view',
    'location.manage',
    'staff.view',
    'staff.manage',
    'catalog.view',
    'stock.view',
    'stock.history.view',
    'stock.cost.view',
    'stock.opening.post',
    'stock.adjust',
    'supplier.view',
    'supplier.manage',
    'purchasing.view',
    'purchasing.manage',
    'purchasing.receive',
    'purchasing.cost.view',
    'sales.view',
    'sales.create',
    'sales.cost.view',
    'customer.view',
    'customer.manage',
    'catalog.manage',
    'catalog.cost.view',
    'exchange_rate.view',
    'exchange_rate.manage',
  ];
  String role = 'owner';

  final Map<String, dynamic> businessData = {
    'id': 'b-1',
    'name': 'Täze Dükan',
    'currency': 'TMT',
    'default_language': 'ru',
    'document_language': 'ru',
    'timezone': 'Asia/Ashgabat',
    'address': '',
    'phone': '',
    'is_active': true,
  };
  final List<Map<String, dynamic>> locationsData = [
    {'id': 'l-1', 'name': 'Esasy dükan', 'kind': 'store', 'is_active': true},
    {'id': 'l-2', 'name': 'Ammar', 'kind': 'warehouse', 'is_active': true},
  ];
  final List<Map<String, dynamic>> staffData = [
    {
      'id': 'm-1',
      'user': {
        'id': 'u-1',
        'username': 'aman',
        'full_name': 'Aman Ataýew',
        'email': 'aman@example.test',
        'preferred_language': 'ru',
        'is_active': true,
      },
      'role': 'owner',
      'all_locations': true,
      'locations': <String>[],
      'is_active': true,
    },
    {
      'id': 'm-2',
      'user': {
        'id': 'u-2',
        'username': 'sata',
        'full_name': 'Satyjy Täç',
        'email': 'sata@example.test',
        'preferred_language': 'tk',
        'is_active': true,
      },
      'role': 'sales',
      'all_locations': false,
      'locations': ['l-1'],
      'is_active': true,
    },
  ];
  final List<String> codesSent = [];

  // --- catalog -------------------------------------------------------------
  final List<Map<String, dynamic>> unitsData = [
    {
      'id': 'un-1',
      'name': 'Штука',
      'symbol': 'шт',
      'decimal_places': 0,
      'is_active': true,
    },
    {
      'id': 'un-2',
      'name': 'Litr',
      'symbol': 'l',
      'decimal_places': 2,
      'is_active': true,
    },
  ];
  final List<Map<String, dynamic>> categoriesData = [
    {'id': 'c-1', 'name': 'Тормоза', 'is_active': true},
  ];
  final List<Map<String, dynamic>> brandsData = [
    {'id': 'br-1', 'name': 'Brembo', 'is_active': true},
  ];
  final List<Map<String, dynamic>> productsData = [];
  final List<Map<String, dynamic>> ratesData = []; // newest last
  int productCounter = 0;

  /// Products the server was asked to create or change (to prove scans save nothing).
  int productWrites = 0;

  final List<String> resetRequests = [];
  String? passwordResetTo;

  Map<String, dynamic> me = {
    'user': {
      'id': 'u-1',
      'username': 'aman',
      'full_name': 'Aman Ataýew',
      'email': 'aman@example.test',
      'preferred_language': 'ru',
    },
    'memberships': [
      {
        'id': 'm-1',
        'business': {'id': 'b-1', 'name': 'Täze Dükan', 'currency': 'TMT'},
        'role': 'owner',
        'permissions': ['business.view', 'purchasing.receive'],
        'locations': [
          {'id': 'l-1', 'name': 'Esasy dükan', 'kind': 'store'},
          {'id': 'l-2', 'name': 'Ammar', 'kind': 'warehouse'},
        ],
      },
    ],
  };

  http.Response _json(
    int status,
    Object? body, {
    Map<String, String>? headers,
  }) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    // like Django: JSON without a charset parameter
    headers: {'content-type': 'application/json', ...?headers},
  );

  http.Response _error(
    int status,
    String code, {
    Map<String, dynamic>? fields,
  }) => _json(status, {
    'error': {
      'code': code,
      'message': 'diagnostic',
      'request_id': 'req-1',
      'fields': ?fields,
    },
  });

  http.Response jsonResponse(int status, Object? body) => _json(status, body);

  /// A product as the catalog API presents it (price_tmt at the current rate, and so on).
  Map<String, dynamic> presentProduct(Map<String, dynamic> raw) =>
      _present(raw);

  http.Response errorResponse(
    int status,
    String code, {
    Map<String, dynamic>? fields,
    Map<String, dynamic>? params,
  }) => _json(status, {
    'error': {
      'code': code,
      'message': 'diagnostic',
      'request_id': 'req-1',
      'fields': ?fields,
      'params': ?params,
    },
  });

  /// A stock-changing command with the server's idempotency rules: the same key
  /// replays the stored outcome, another body under the same key is refused, and
  /// the action runs once. [perform] returns the outcome, or an [http.Response]
  /// to refuse (nothing is recorded then, as on the real server).
  http.Response runCommand(
    http.Request request,
    Map<String, dynamic> body,
    Object Function() perform,
  ) {
    final key = request.headers['Idempotency-Key'];
    if (key == null) return _error(400, 'idempotency_key_required');
    final fingerprint = jsonEncode(body);
    final existing = records[key];
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        return _error(422, 'idempotency_key_reused');
      }
      return _json(
        existing.status,
        existing.body,
        headers: {'idempotent-replay': 'true'},
      );
    }
    if (rejectWith != null) {
      final code = rejectWith!;
      rejectWith = null;
      return _error(409, code);
    }
    if (failBeforeCommit > 0) {
      failBeforeCommit--;
      return _error(500, 'server_error');
    }
    final outcome = perform();
    if (outcome is http.Response) return outcome;
    final result = outcome as ({int status, Map<String, dynamic> body});
    records[key] = (
      fingerprint: fingerprint,
      status: result.status,
      body: result.body,
    );
    if (dropResponseAfterCommit > 0) {
      dropResponseAfterCommit--;
      throw http.ClientException('connection lost after the server committed');
    }
    return _json(result.status, result.body);
  }

  Future<http.Response> _handle(http.Request request) async {
    if (!reachable) throw http.ClientException('offline');
    final path = request.url.path;
    requestHeaders.add(Map.of(request.headers));
    log.add('${request.method} $path');
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;

    if (path == '/api/v1/auth/login/') {
      if (body['password'] != 'right-password') {
        return _error(401, 'invalid_credentials');
      }
      return _json(200, {
        'access': accessToken,
        'refresh': refreshToken,
        'user': me['user'],
      });
    }
    if (path == '/api/v1/auth/refresh/') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (refreshRejected || body['refresh'] != refreshToken) {
        return _error(401, 'invalid_token');
      }
      tokenCounter++;
      accessToken = 'access-$tokenCounter';
      refreshToken = 'refresh-$tokenCounter';
      expireAccess = false;
      return _json(200, {'access': accessToken, 'refresh': refreshToken});
    }
    if (path == '/api/v1/auth/password/reset/request/') {
      resetRequests.add('${body['identifier']}');
      return _json(202, {'status': 'accepted'});
    }
    if (path == '/api/v1/auth/password/reset/confirm/') {
      if (body['code'] != 'ABCD2345') return _error(400, 'invalid_reset_code');
      if ('${body['new_password']}'.length < 10) {
        return _error(
          400,
          'validation_error',
          fields: {
            'new_password': [
              {'code': 'password_too_short', 'message': 'short'},
            ],
          },
        );
      }
      passwordResetTo = '${body['new_password']}';
      return _json(200, {'status': 'ok'});
    }
    if (path == '/api/v1/auth/logout/') {
      if (body['refresh'] == refreshToken) refreshRejected = true;
      return http.Response('', 204);
    }

    // everything below needs a valid access token
    final auth = request.headers['Authorization'];
    if (expireAccess || auth != 'Bearer $accessToken') {
      return _error(401, 'invalid_token');
    }
    if (path == '/api/v1/me/' && request.method == 'GET') {
      final memberships = me['memberships'] as List;
      if (memberships.isNotEmpty) {
        final membership = memberships.first as Map;
        membership['permissions'] = permissions;
        membership['role'] = role;
      }
      return _json(200, me);
    }
    if (path == '/api/v1/me/' && request.method == 'PATCH') {
      (me['user'] as Map)['preferred_language'] = body['preferred_language'];
      return _json(200, me);
    }

    final base = RegExp(r'^/api/v1/businesses/b-1/(.*)$').firstMatch(path);
    if (base != null) {
      final admin = _admin(request, base.group(1)!, body);
      if (admin != null) return admin;
      final catalog = _catalog(request, base.group(1)!, body);
      if (catalog != null) return catalog;
      final inventory = ledger.handle(request, base.group(1)!, body);
      if (inventory != null) return inventory;
    }

    final status = RegExp(
      r'^/api/v1/businesses/([^/]+)/operations/([^/]+)/([^/]+)/$',
    ).firstMatch(path);
    if (status != null) {
      final record = records[status.group(3)];
      if (record == null) return _error(404, 'operation_not_found');
      return _json(200, {
        'status': 'completed',
        'response_status': record.status,
        'response': record.body,
      });
    }

    if (RegExp(r'^/api/v1/businesses/[^/]+/demo/$').hasMatch(path)) {
      return runCommand(request, body, () {
        performed.add(body);
        return (
          status: 201,
          body: {'ok': true, 'n': body['n'], 'note': body['note']},
        );
      });
    }
    return _error(404, 'not_found');
  }

  http.Response? _admin(
    http.Request request,
    String rest,
    Map<String, dynamic> body,
  ) {
    final method = request.method;
    http.Response page(List<Map<String, dynamic>> items) => _json(200, {
      'count': items.length,
      'next': null,
      'previous': null,
      'results': items,
    });
    if (rest == '') {
      if (method == 'GET') return _json(200, businessData);
      if (method == 'PATCH') {
        businessData.addAll(body);
        return _json(200, businessData);
      }
    }
    if (rest == 'locations/') {
      if (method == 'GET') {
        final all = request.url.queryParameters['include_inactive'] == '1';
        return page([
          for (final l in locationsData)
            if (all || l['is_active'] == true) l,
        ]);
      }
      if (method == 'POST') {
        final name = '${body['name']}'.trim();
        if (name.isEmpty) {
          return _error(
            400,
            'validation_error',
            fields: {
              'name': [
                {'code': 'blank', 'message': 'blank'},
              ],
            },
          );
        }
        if (locationsData.any(
          (l) => '${l['name']}'.toLowerCase() == name.toLowerCase(),
        )) {
          return _error(
            400,
            'validation_error',
            fields: {
              'name': [
                {'code': 'name_taken', 'message': 'taken'},
              ],
            },
          );
        }
        final created = {
          'id': 'l-${locationsData.length + 1}',
          'name': name,
          'kind': body['kind'] ?? 'store',
          'is_active': true,
        };
        locationsData.add(created);
        return _json(201, created);
      }
    }
    final loc = RegExp(r'^locations/([^/]+)/$').firstMatch(rest);
    if (loc != null && method == 'PATCH') {
      final item = locationsData.firstWhere((l) => l['id'] == loc.group(1));
      item.addAll(body);
      return _json(200, item);
    }
    if (rest == 'staff/') {
      if (method == 'GET') return page(staffData);
      if (method == 'POST') {
        final username = '${body['username']}'.toLowerCase();
        if (username == 'taken') {
          return _error(
            400,
            'validation_error',
            fields: {
              'username': [
                {'code': 'username_taken', 'message': 'taken'},
              ],
            },
          );
        }
        if ((body['password'] as String?)?.isNotEmpty ?? false) {
          if ((body['password'] as String).length < 10) {
            return _error(
              400,
              'validation_error',
              fields: {
                'password': [
                  {'code': 'password_too_short', 'message': 'short'},
                ],
              },
            );
          }
        }
        final created = {
          'id': 'm-${staffData.length + 1}',
          'user': {
            'id': 'u-${staffData.length + 1}',
            'username': username,
            'full_name': body['full_name'],
            'email': body['email'],
            'preferred_language': body['preferred_language'],
            'is_active': true,
          },
          'role': body['role'],
          'all_locations': body['all_locations'],
          'locations': body['locations'],
          'is_active': true,
        };
        staffData.add(created);
        return _json(201, created);
      }
    }
    final staff = RegExp(r'^staff/([^/]+)/(send-code/)?$').firstMatch(rest);
    if (staff != null) {
      final item = staffData.firstWhere((m) => m['id'] == staff.group(1));
      if (staff.group(2) != null && method == 'POST') {
        codesSent.add('${staff.group(1)}');
        return _json(202, {'status': 'accepted'});
      }
      if (method == 'PATCH') {
        if (item['role'] == 'owner' &&
            (body['is_active'] == false ||
                (body['role'] != null && body['role'] != 'owner'))) {
          return _error(409, 'last_owner');
        }
        item.addAll(body);
        return _json(200, item);
      }
    }
    return null;
  }

  // ---- catalog -------------------------------------------------------------
  Map<String, dynamic>? _ref(List<Map<String, dynamic>> list, Object? id) {
    if (id == null) return null;
    final found = list.where((e) => e['id'] == id).firstOrNull;
    return found == null ? null : {'id': found['id'], 'name': found['name']};
  }

  Map<String, dynamic> _present(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    final currency = raw['price_currency'];
    final amount = '${raw['price_amount']}';
    out['price'] = {'amount': amount, 'currency': currency};
    final rate = ratesData.isEmpty ? null : '${ratesData.last['rate']}';
    String? tmt;
    if (currency == 'TMT') {
      tmt = amount;
    } else if (rate != null) {
      final minor = (double.parse(amount) * 100).round();
      final rate6 = (double.parse(rate) * 1000000).round();
      final value = (minor * rate6 + 500000) ~/ 1000000;
      tmt = '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
    }
    out['price_tmt'] = tmt;
    out['price_rate_missing'] = currency != 'TMT' && rate == null;
    out['category'] = _ref(categoriesData, raw['category']);
    out['brand'] = _ref(brandsData, raw['brand']);
    out['unit'] = unitsData.firstWhere((u) => u['id'] == raw['unit']);
    if (!permissions.contains('catalog.cost.view')) {
      out.remove('default_purchase_cost');
    }
    out.remove('price_amount');
    out.remove('price_currency');
    return out;
  }

  http.Response? _catalog(
    http.Request request,
    String rest,
    Map<String, dynamic> body,
  ) {
    final method = request.method;
    http.Response page(List<Map<String, dynamic>> items, {int? count}) =>
        _json(200, {
          'count': count ?? items.length,
          'next': null,
          'previous': null,
          'results': items,
        });
    List<Map<String, dynamic>> paged(List<Map<String, dynamic>> all) {
      final q = request.url.queryParameters;
      final offset = int.tryParse(q['offset'] ?? '') ?? 0;
      final limit = int.tryParse(q['limit'] ?? '') ?? 50;
      return all.skip(offset).take(limit).toList();
    }

    if (rest == 'units/' && method == 'GET') return page(unitsData);
    if (rest == 'units/' && method == 'POST') {
      final created = {
        'id': 'un-${unitsData.length + 1}',
        'name': body['name'],
        'symbol': body['symbol'],
        'decimal_places': body['decimal_places'],
        'is_active': true,
      };
      unitsData.add(created);
      return _json(201, created);
    }
    for (final kind in ['categories', 'brands']) {
      final list = kind == 'categories' ? categoriesData : brandsData;
      if (rest == '$kind/' && method == 'GET') return page(list);
      if (rest == '$kind/' && method == 'POST') {
        final name = '${body['name']}'.trim();
        if (list.any(
          (e) => '${e['name']}'.toLowerCase() == name.toLowerCase(),
        )) {
          return _error(
            400,
            'validation_error',
            fields: {
              'name': [
                {'code': 'name_taken', 'message': 'taken'},
              ],
            },
          );
        }
        final created = {
          'id': '$kind-${list.length + 1}',
          'name': name,
          'is_active': true,
        };
        list.add(created);
        return _json(201, created);
      }
    }

    if (rest == 'exchange-rates/' && method == 'GET') {
      final newestFirst = ratesData.reversed.toList();
      return page(paged(newestFirst), count: newestFirst.length);
    }
    if (rest == 'exchange-rates/' && method == 'POST') {
      final rate = double.tryParse('${body['rate']}');
      if (rate == null || rate <= 0) {
        return _error(
          400,
          'validation_error',
          fields: {
            'rate': [
              {'code': 'min_value', 'message': 'bad'},
            ],
          },
        );
      }
      final entry = {
        'id': 'r-${ratesData.length + 1}',
        'currency': 'USD',
        'rate': '${body['rate']}',
        'set_by': 'aman',
        'created_at': DateTime.utc(
          2026,
          10,
          6,
          12,
          ratesData.length,
        ).toIso8601String(),
      };
      ratesData.add(entry);
      return _json(201, entry);
    }

    if (rest == 'barcodes/lookup/' && method == 'GET') {
      final code = request.url.queryParameters['code'] ?? '';
      final found = productsData
          .where(
            (p) =>
                p['is_active'] == true &&
                (p['barcodes'] as List).contains(code),
          )
          .firstOrNull;
      if (found == null) return _error(404, 'barcode_not_found');
      return _json(200, _present(found));
    }

    if (rest == 'products/' && method == 'GET') {
      final q = request.url.queryParameters;
      final active = q['active'] ?? '1';
      var items = productsData.where((p) {
        if (active == '1' && p['is_active'] != true) return false;
        if (active == '0' && p['is_active'] == true) return false;
        if (q['category'] != null && p['category'] != q['category']) {
          return false;
        }
        final haystack =
            '${p['name']} ${p['sku']} ${(p['barcodes'] as List).join(' ')}'
                .toLowerCase();
        for (final token in (q['q'] ?? '').toLowerCase().split(' ')) {
          if (token.isNotEmpty && !haystack.contains(token)) return false;
        }
        return true;
      }).toList();
      return page([
        for (final p in paged(items)) _present(p),
      ], count: items.length);
    }
    if (rest == 'products/' && method == 'POST') {
      productWrites++;
      final err = _validateProduct(body, null);
      if (err != null) return err;
      final id = 'p-${++productCounter}';
      final created = {
        'id': id,
        ...body,
        'barcodes': [...?(body['barcodes'] as List?)],
        'is_active': true,
        'created_at': '2026-10-06T10:00:00Z',
        'updated_at': '2026-10-06T10:00:00Z',
      };
      productsData.add(created);
      return _json(201, _present(created));
    }
    final one = RegExp(r'^products/([^/]+)/$').firstMatch(rest);
    if (one != null) {
      final existing = productsData
          .where((p) => p['id'] == one.group(1))
          .firstOrNull;
      if (existing == null) return _error(404, 'not_found');
      if (method == 'GET') return _json(200, _present(existing));
      if (method == 'PATCH') {
        productWrites++;
        final err = _validateProduct(body, existing);
        if (err != null) return err;
        existing.addAll(body);
        return _json(200, _present(existing));
      }
    }
    return null;
  }

  http.Response? _validateProduct(
    Map<String, dynamic> body,
    Map<String, dynamic>? existing,
  ) {
    final sku = body['sku'] as String?;
    if (sku != null &&
        productsData.any(
          (p) =>
              p != existing && '${p['sku']}'.toLowerCase() == sku.toLowerCase(),
        )) {
      return _error(
        400,
        'validation_error',
        fields: {
          'sku': [
            {'code': 'sku_taken', 'message': 'taken'},
          ],
        },
      );
    }
    final codes = (body['barcodes'] as List?)?.cast<String>() ?? const [];
    for (final other in productsData) {
      if (other == existing) {
        continue;
      }
      if ((other['barcodes'] as List).any(codes.contains)) {
        return _error(
          400,
          'validation_error',
          fields: {
            'barcodes': [
              {'code': 'barcode_taken', 'message': 'taken'},
            ],
          },
        );
      }
    }
    return null;
  }
}
