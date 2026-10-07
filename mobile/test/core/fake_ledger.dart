import 'package:http/http.dart' as http;

import 'fake_server.dart';

String _dec(int value, int scale) {
  var p = 1;
  for (var i = 0; i < scale; i++) {
    p *= 10;
  }
  final abs = value.abs();
  final frac = (abs % p).toString().padLeft(scale, '0');
  return '${value < 0 ? '-' : ''}${abs ~/ p}.$frac';
}

int _milli(Object? text) => (double.parse('$text') * 1000).round();
int _minor(Object? text) => (double.parse('$text') * 100).round();

class _Layer {
  _Layer(this.remaining, this.costMinor);
  int remaining;
  final int costMinor;
}

class _Bucket {
  _Bucket(this.productId, this.locationId, this.condition);
  final String productId;
  final String locationId;
  final String condition;
  final List<_Layer> layers = [];
  int get quantity => layers.fold(0, (a, l) => a + l.remaining);
}

/// Stock ledger (FIFO cost layers), suppliers and purchase orders for the widget
/// tests: a small stand-in with the same rules as the real server (stock never
/// goes negative, receipts only at the order's location, no over-receipt, a
/// delivery is a command that runs once per operation key).
class FakeLedger {
  FakeLedger(this.server);
  final FakeServer server;

  final Map<String, _Bucket> _buckets = {};
  final List<Map<String, dynamic>> movements = []; // newest first
  final List<Map<String, dynamic>> suppliers = [];
  final List<Map<String, dynamic>> orders = [];
  int _ids = 0;
  int _orderNumber = 0;

  /// Deliveries the server actually recorded (to prove nothing is received twice).
  int deliveriesRecorded = 0;
  int stockWrites = 0;

  // ---- sales -----------------------------------------------------------------
  final List<Map<String, dynamic>> sales = []; // newest first
  final List<Map<String, dynamic>> customers = [];
  final List<Map<String, String>> documentRequests = [];
  int _saleNumber = 0;

  /// Sales the server actually recorded (to prove nothing is sold twice).
  int salesRecorded = 0;

  String _id(String prefix) => '$prefix-${++_ids}';

  bool _can(String code) => server.permissions.contains(code);

  List<Map<String, dynamic>> get _locations =>
      (((server.me['memberships'] as List).first as Map)['locations'] as List)
          .cast<Map<String, dynamic>>();

  Map<String, dynamic> _location(String id) =>
      _locations.firstWhere((l) => l['id'] == id);

  Map<String, dynamic> _productRef(String id) {
    final p = server.productsData.firstWhere((p) => p['id'] == id);
    return {
      'id': p['id'],
      'sku': p['sku'],
      'name': p['name'],
      'unit': server.unitsData.firstWhere((u) => u['id'] == p['unit']),
    };
  }

  /// Puts goods on a shelf directly (test set-up).
  void seedStock(
    String productId,
    String locationId,
    String quantity,
    String cost, {
    String condition = 'sellable',
  }) {
    final result = _post(
      productId: productId,
      locationId: locationId,
      condition: condition,
      milli: _milli(quantity),
      costMinor: _minor(cost),
      type: 'adjustment_in',
      reason: 'seed',
      documentType: 'adjustment',
      documentId: _id('doc'),
    );
    assert(result == null);
  }

  int quantityOf(
    String productId,
    String locationId, [
    String condition = 'sellable',
  ]) => _buckets['$productId|$locationId|$condition']?.quantity ?? 0;

  Map<String, dynamic> seedSupplier(String name) {
    final supplier = {
      'id': _id('s'),
      'name': name,
      'contact_name': '',
      'phone': '',
      'email': '',
      'address': '',
      'notes': '',
      'is_active': true,
      'created_at': '2026-10-06T10:00:00Z',
    };
    suppliers.add(supplier);
    return supplier;
  }

  /// A purchase order in the given state, for tests that start from one.
  Map<String, dynamic> seedOrder({
    required String supplierId,
    required String locationId,
    required List<({String productId, String quantity, String cost})> lines,
    String status = 'ordered',
  }) {
    final order = {
      'id': _id('po'),
      'number': ++_orderNumber,
      'status': status,
      'supplier': supplierId,
      'location': locationId,
      'expected_date': null,
      'notes': '',
      'cancel_reason': '',
      'created_at': '2026-10-06T10:00:00Z',
      'lines': [
        for (final l in lines)
          {
            'id': _id('pol'),
            'product': l.productId,
            'quantity': _milli(l.quantity),
            'received': 0,
            'cost': _minor(l.cost),
          },
      ],
      'deliveries': <Map<String, dynamic>>[],
    };
    orders.insert(0, order);
    return order;
  }

  // ---- posting ----------------------------------------------------------------

  Map<String, _Bucket> _snapshot() => {
    for (final e in _buckets.entries)
      e.key: (_Bucket(e.value.productId, e.value.locationId, e.value.condition)
        ..layers.addAll(
          e.value.layers.map((l) => _Layer(l.remaining, l.costMinor)),
        )),
  };

  /// Returns null on success or an error response; nothing is changed on failure.
  http.Response? _postAll(List<http.Response? Function()> steps) {
    final bucketsBefore = _snapshot();
    final movementsBefore = List.of(movements);
    for (final step in steps) {
      final error = step();
      if (error != null) {
        _buckets
          ..clear()
          ..addAll(bucketsBefore);
        movements
          ..clear()
          ..addAll(movementsBefore);
        return error;
      }
    }
    return null;
  }

  http.Response? _post({
    required String productId,
    required String locationId,
    required String condition,
    required int milli,
    int? costMinor,
    required String type,
    required String reason,
    required String documentType,
    required String documentId,
  }) {
    final key = '$productId|$locationId|$condition';
    final bucket = _buckets.putIfAbsent(
      key,
      () => _Bucket(productId, locationId, condition),
    );
    void record(int quantity, int cost) => movements.insert(0, {
      'id': _id('mv'),
      'created_at': DateTime.utc(
        2026,
        10,
        6,
        12,
        movements.length % 60,
      ).toIso8601String(),
      'movement_type': type,
      'product': _productRef(productId),
      'location': {'id': locationId, 'name': _location(locationId)['name']},
      'condition': condition,
      'quantity': _dec(quantity, 3),
      'unit_cost': _dec(cost, 2),
      'document_type': documentType,
      'document_id': documentId,
      'reason': reason,
      'actor': {'id': 'u-1', 'name': 'Aman Ataýew'},
    });
    if (milli > 0) {
      bucket.layers.add(_Layer(milli, costMinor ?? 0));
      record(milli, costMinor ?? 0);
      return null;
    }
    var need = -milli;
    if (bucket.quantity < need) {
      return server.errorResponse(
        409,
        'insufficient_stock',
        params: {
          'product': productId,
          'location': locationId,
          'available': _dec(bucket.quantity, 3),
          'requested': _dec(need, 3),
        },
      );
    }
    for (final layer in bucket.layers) {
      if (need == 0) break;
      final take = layer.remaining < need ? layer.remaining : need;
      if (take == 0) continue;
      layer.remaining -= take;
      need -= take;
      record(-take, layer.costMinor);
    }
    return null;
  }

  // ---- presentation -----------------------------------------------------------

  Map<String, dynamic> _stockRow(_Bucket b) {
    final qty = b.quantity;
    final value = b.layers.fold<int>(
      0,
      (a, l) => a + (l.remaining * l.costMinor / 1000).round(),
    );
    return {
      'id': 'sb-${b.productId}-${b.locationId}-${b.condition}',
      'product': _productRef(b.productId),
      'location': {'id': b.locationId, 'name': _location(b.locationId)['name']},
      'condition': b.condition,
      'quantity': _dec(qty, 3),
      'updated_at': '2026-10-06T10:00:00Z',
      if (_can('stock.cost.view')) ...{
        'value': _dec(value, 2),
        'average_cost': qty == 0 ? null : _dec((value * 1000 / qty).round(), 2),
      },
    };
  }

  Map<String, dynamic> _present(
    Map<String, dynamic> order, {
    bool summary = false,
  }) {
    final showCost = _can('purchasing.cost.view');
    final lines = (order['lines'] as List).cast<Map<String, dynamic>>();
    int lineTotal(Map<String, dynamic> l) =>
        ((l['quantity'] as int) * (l['cost'] as int) / 1000).round();
    final total = lines.fold<int>(0, (a, l) => a + lineTotal(l));
    final supplier = suppliers.firstWhere((s) => s['id'] == order['supplier']);
    final location = _location(order['location'] as String);
    final base = {
      'id': order['id'],
      'number': order['number'],
      'status': order['status'],
      'supplier': {'id': supplier['id'], 'name': supplier['name']},
      'location': {'id': location['id'], 'name': location['name']},
      'expected_date': order['expected_date'],
      'created_at': order['created_at'],
      if (showCost) 'total': _dec(total, 2),
    };
    if (summary) {
      return {
        ...base,
        'line_count': lines.length,
        'ordered_quantity': _dec(
          lines.fold(0, (a, l) => a + (l['quantity'] as int)),
          3,
        ),
        'received_quantity': _dec(
          lines.fold(0, (a, l) => a + (l['received'] as int)),
          3,
        ),
      };
    }
    return {
      ...base,
      'notes': order['notes'],
      'created_by': {'id': 'u-1', 'name': 'Aman Ataýew'},
      'ordered_at': order['ordered_at'],
      'cancelled_at': order['cancelled_at'],
      'cancel_reason': order['cancel_reason'],
      'lines': [
        for (final l in lines)
          {
            'id': l['id'],
            'product': _productRef(l['product'] as String),
            'quantity': _dec(l['quantity'] as int, 3),
            'received_quantity': _dec(l['received'] as int, 3),
            'outstanding': _dec(
              (l['quantity'] as int) - (l['received'] as int),
              3,
            ),
            if (showCost) ...{
              'unit_cost': _dec(l['cost'] as int, 2),
              'line_total': _dec(lineTotal(l), 2),
            },
          },
      ],
      'deliveries': [
        for (final d
            in (order['deliveries'] as List).cast<Map<String, dynamic>>())
          {
            'id': d['id'],
            'number': d['number'],
            'received_at': d['received_at'],
            'received_by': {'id': 'u-1', 'name': 'Aman Ataýew'},
            'note': d['note'],
            'lines': [
              for (final dl
                  in (d['lines'] as List).cast<Map<String, dynamic>>())
                {
                  'id': dl['id'],
                  'order_line': dl['order_line'],
                  'product': _productRef(dl['product'] as String),
                  'quantity': _dec(dl['quantity'] as int, 3),
                  if (showCost) 'unit_cost': _dec(dl['cost'] as int, 2),
                },
            ],
          },
      ],
    };
  }

  // ---- routing ----------------------------------------------------------------

  http.Response? handle(
    http.Request request,
    String rest,
    Map<String, dynamic> body,
  ) {
    final m = request.method;
    final q = request.url.queryParameters;
    http.Response page(List<Map<String, dynamic>> all) {
      final offset = int.tryParse(q['offset'] ?? '') ?? 0;
      final limit = int.tryParse(q['limit'] ?? '') ?? 50;
      return server.jsonResponse(200, {
        'count': all.length,
        'next': null,
        'previous': null,
        'results': all.skip(offset).take(limit).toList(),
      });
    }

    if (rest == 'stock/' && m == 'GET') {
      var rows = _buckets.values.where((b) {
        if (q['include_zero'] != '1' && b.quantity == 0) return false;
        if (q['location'] != null && b.locationId != q['location']) {
          return false;
        }
        if (q['product'] != null && b.productId != q['product']) return false;
        final p = server.productsData.firstWhere((p) => p['id'] == b.productId);
        final hay = '${p['name']} ${p['sku']}'.toLowerCase();
        for (final t in (q['q'] ?? '').toLowerCase().split(' ')) {
          if (t.isNotEmpty && !hay.contains(t)) return false;
        }
        return true;
      }).toList();
      rows.sort(
        (a, b) => _productRef(a.productId)['name'].toString().compareTo(
          _productRef(b.productId)['name'].toString(),
        ),
      );
      return page([for (final b in rows) _stockRow(b)]);
    }
    if (rest == 'stock/movements/' && m == 'GET') {
      final items = movements
          .where((mv) {
            if (q['product'] != null &&
                (mv['product'] as Map)['id'] != q['product']) {
              return false;
            }
            return true;
          })
          .map((mv) {
            final copy = Map<String, dynamic>.from(mv);
            if (!_can('stock.cost.view')) copy.remove('unit_cost');
            return copy;
          })
          .toList();
      return page(items);
    }
    if (rest == 'stock/opening/' && m == 'POST') {
      return server.runCommand(request, body, () {
        stockWrites++;
        final location = body['location'] as String;
        final documentId = _id('doc');
        final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
        for (final l in lines) {
          final exists = movements.any(
            (mv) =>
                (mv['product'] as Map)['id'] == l['product'] &&
                (mv['location'] as Map)['id'] == location,
          );
          if (exists) {
            return server.errorResponse(409, 'opening_stock_exists');
          }
        }
        final error = _postAll([
          for (final l in lines)
            () => _post(
              productId: l['product'] as String,
              locationId: location,
              condition: 'sellable',
              milli: _milli(l['quantity']),
              costMinor: _minor(l['unit_cost']),
              type: 'opening',
              reason: '${body['note'] ?? ''}',
              documentType: 'opening',
              documentId: documentId,
            ),
        ]);
        if (error != null) return error;
        return (
          status: 201,
          body: {
            'document_id': documentId,
            'location': location,
            'movements': [],
          },
        );
      });
    }
    if (rest == 'stock/adjustments/' && m == 'POST') {
      return server.runCommand(request, body, () {
        stockWrites++;
        final location = body['location'] as String;
        final documentId = _id('doc');
        final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
        final error = _postAll([
          for (final l in lines)
            () => _post(
              productId: l['product'] as String,
              locationId: location,
              condition: '${l['condition'] ?? 'sellable'}',
              milli: l['direction'] == 'in'
                  ? _milli(l['quantity'])
                  : -_milli(l['quantity']),
              costMinor: l['unit_cost'] == null ? null : _minor(l['unit_cost']),
              type: l['direction'] == 'in' ? 'adjustment_in' : 'adjustment_out',
              reason: '${body['reason']}',
              documentType: 'adjustment',
              documentId: documentId,
            ),
        ]);
        if (error != null) return error;
        return (
          status: 201,
          body: {
            'document_id': documentId,
            'location': location,
            'movements': [],
          },
        );
      });
    }

    // ---- suppliers ----
    if (rest == 'suppliers/' && m == 'GET') {
      final active = q['active'] ?? '1';
      return page([
        for (final s in suppliers)
          if (active == 'all' || (active == '1') == (s['is_active'] == true)) s,
      ]);
    }
    if (rest == 'suppliers/' && m == 'POST') {
      final name = '${body['name']}'.trim();
      if (suppliers.any(
        (s) => '${s['name']}'.toLowerCase() == name.toLowerCase(),
      )) {
        return server.errorResponse(
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
        'id': _id('s'),
        'contact_name': '',
        'phone': '',
        'email': '',
        'address': '',
        'notes': '',
        'is_active': true,
        'created_at': '2026-10-06T10:00:00Z',
        ...body,
        'name': name,
      };
      suppliers.add(created);
      return server.jsonResponse(201, created);
    }
    final oneSupplier = RegExp(r'^suppliers/([^/]+)/$').firstMatch(rest);
    if (oneSupplier != null && m == 'PATCH') {
      final s = suppliers.firstWhere((s) => s['id'] == oneSupplier.group(1));
      s.addAll(body);
      return server.jsonResponse(200, s);
    }

    // ---- purchase orders ----
    if (rest == 'purchase-orders/' && m == 'GET') {
      final statuses = (q['status'] ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();
      return page([
        for (final o in orders)
          if (statuses.isEmpty || statuses.contains(o['status']))
            _present(o, summary: true),
      ]);
    }
    if (rest == 'purchase-orders/' && m == 'POST') {
      final order = seedOrder(
        supplierId: body['supplier'] as String,
        locationId: body['location'] as String,
        status: 'draft',
        lines: [
          for (final l
              in (body['lines'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
            (
              productId: l['product'] as String,
              quantity: '${l['quantity']}',
              cost: '${l['unit_cost']}',
            ),
        ],
      );
      order['expected_date'] = body['expected_date'];
      order['notes'] = body['notes'] ?? '';
      return server.jsonResponse(201, _present(order));
    }
    final one = RegExp(r'^purchase-orders/([^/]+)/(.*)$').firstMatch(rest);
    if (one != null) {
      final order = orders.where((o) => o['id'] == one.group(1)).firstOrNull;
      if (order == null) return server.errorResponse(404, 'not_found');
      final action = one.group(2)!;
      if (action.isEmpty && m == 'GET') {
        return server.jsonResponse(200, _present(order));
      }
      if (action.isEmpty && m == 'PATCH') {
        if (order['status'] != 'draft') {
          return server.errorResponse(409, 'order_not_draft');
        }
        order['supplier'] = body['supplier'] ?? order['supplier'];
        order['location'] = body['location'] ?? order['location'];
        order['expected_date'] = body['expected_date'];
        order['notes'] = body['notes'] ?? order['notes'];
        if (body['lines'] != null) {
          order['lines'] = [
            for (final l
                in (body['lines'] as List).cast<Map<String, dynamic>>())
              {
                'id': _id('pol'),
                'product': l['product'],
                'quantity': _milli(l['quantity']),
                'received': 0,
                'cost': _minor(l['unit_cost']),
              },
          ];
        }
        return server.jsonResponse(200, _present(order));
      }
      if (action == 'submit/' && m == 'POST') {
        if (order['status'] != 'draft') {
          return server.errorResponse(409, 'order_not_draft');
        }
        if ((order['lines'] as List).isEmpty) {
          return server.errorResponse(409, 'order_has_no_lines');
        }
        order['status'] = 'ordered';
        return server.jsonResponse(200, _present(order));
      }
      if (action == 'cancel/' && m == 'POST') {
        if (![
          'draft',
          'ordered',
          'partially_received',
        ].contains(order['status'])) {
          return server.errorResponse(409, 'order_not_cancellable');
        }
        order['status'] = 'cancelled';
        order['cancel_reason'] = body['reason'] ?? '';
        return server.jsonResponse(200, _present(order));
      }
      if (action == 'deliveries/' && m == 'POST') {
        return server.runCommand(request, body, () {
          if (!['ordered', 'partially_received'].contains(order['status'])) {
            return server.errorResponse(409, 'order_not_receivable');
          }
          final orderLines = (order['lines'] as List)
              .cast<Map<String, dynamic>>();
          final wanted = (body['lines'] as List).cast<Map<String, dynamic>>();
          for (final w in wanted) {
            final line = orderLines.firstWhere(
              (l) => l['id'] == w['order_line'],
            );
            if (_milli(w['quantity']) >
                (line['quantity'] as int) - (line['received'] as int)) {
              return server.errorResponse(409, 'over_receipt');
            }
          }
          final deliveryId = _id('dl');
          final error = _postAll([
            for (final w in wanted)
              () {
                final line = orderLines.firstWhere(
                  (l) => l['id'] == w['order_line'],
                );
                return _post(
                  productId: line['product'] as String,
                  locationId: order['location'] as String,
                  condition: 'sellable',
                  milli: _milli(w['quantity']),
                  costMinor: line['cost'] as int,
                  type: 'receipt',
                  reason: '${body['note'] ?? ''}',
                  documentType: 'delivery',
                  documentId: deliveryId,
                );
              },
          ]);
          if (error != null) return error;
          deliveriesRecorded++;
          final deliveries = order['deliveries'] as List;
          deliveries.add({
            'id': deliveryId,
            'number': deliveries.length + 1,
            'received_at': '2026-10-06T13:00:00Z',
            'note': body['note'] ?? '',
            'lines': [
              for (final w in wanted)
                () {
                  final line = orderLines.firstWhere(
                    (l) => l['id'] == w['order_line'],
                  );
                  line['received'] =
                      (line['received'] as int) + _milli(w['quantity']);
                  return {
                    'id': _id('dll'),
                    'order_line': line['id'],
                    'product': line['product'],
                    'quantity': _milli(w['quantity']),
                    'cost': line['cost'],
                  };
                }(),
            ],
          });
          order['status'] =
              orderLines.every((l) => l['received'] == l['quantity'])
              ? 'received'
              : 'partially_received';
          return (
            status: 201,
            body: {
              'delivery': deliveryId,
              'delivery_number': deliveries.length,
              'order': _present(order),
            },
          );
        });
      }
    }

    // ---- customers ----
    if (rest == 'customers/' && m == 'GET') {
      final text = (q['q'] ?? '').toLowerCase();
      return page([
        for (final c in customers)
          if (c['is_active'] == true &&
              (text.isEmpty ||
                  '${c['name']} ${c['phone']}'.toLowerCase().contains(text)))
            c,
      ]);
    }
    if (rest == 'customers/' && m == 'POST') {
      final created = {
        'id': _id('cu'),
        'name': '${body['name']}'.trim(),
        'phone': '${body['phone'] ?? ''}',
        'notes': '',
        'is_active': true,
        'created_at': '2026-10-06T10:00:00Z',
      };
      customers.add(created);
      return server.jsonResponse(201, created);
    }

    // ---- sales ----
    if (rest == 'sales/' && m == 'GET') {
      final text = (q['q'] ?? '').trim().toLowerCase();
      return page([
        for (final sale in sales)
          if (text.isEmpty ||
              _saleNumberText(sale).toLowerCase().contains(text) ||
              '${sale['customer_name']}'.toLowerCase().contains(text))
            _presentSale(sale, summary: true),
      ]);
    }
    if (rest == 'sales/' && m == 'POST') {
      return server.runCommand(request, body, () => _completeSale(body));
    }
    final oneSale = RegExp(r'^sales/([^/]+)/(document/)?$').firstMatch(rest);
    if (oneSale != null) {
      final sale = sales.where((s) => s['id'] == oneSale.group(1)).firstOrNull;
      if (sale == null) return server.errorResponse(404, 'not_found');
      if (oneSale.group(2) != null) {
        documentRequests.add({'id': '${sale['id']}', 'lang': q['lang'] ?? ''});
        return http.Response.bytes(
          '%PDF-1.4 fake receipt ${_saleNumberText(sale)}'.codeUnits,
          200,
          headers: {'content-type': 'application/pdf'},
        );
      }
      return server.jsonResponse(200, _presentSale(sale));
    }
    return null;
  }

  String _saleNumberText(Map<String, dynamic> sale) =>
      'S-${(sale['number'] as int).toString().padLeft(6, '0')}';

  Map<String, dynamic> _presentSale(
    Map<String, dynamic> sale, {
    bool summary = false,
  }) {
    final lines = (sale['lines'] as List).cast<Map<String, dynamic>>();
    final location = _location(sale['location'] as String);
    final base = {
      'id': sale['id'],
      'number': sale['number'],
      'created_at': sale['created_at'],
      'location': {'id': location['id'], 'name': location['name']},
      'cashier': {'id': 'u-1', 'name': 'Aman Ataýew'},
      'customer_name': sale['customer_name'],
      'total': _dec(sale['total'] as int, 2),
      'payment_method': sale['payment_method'],
    };
    if (summary) {
      return {...base, 'line_count': lines.length};
    }
    final showCost = _can('sales.cost.view');
    final cost = lines.fold<int>(0, (a, l) => a + (l['cost'] as int));
    return {
      ...base,
      'customer': sale['customer_id'] == null
          ? null
          : {'id': sale['customer_id'], 'name': sale['customer_name']},
      'customer_phone': sale['customer_phone'],
      'note': sale['note'],
      'lines': [
        for (final l in lines)
          {
            'id': l['id'],
            'product': l['product'],
            'sku': l['sku'],
            'name': l['name'],
            'unit_symbol': l['unit_symbol'],
            'unit_decimals': l['unit_decimals'],
            'quantity': _dec(l['quantity'] as int, 3),
            'unit_price': _dec(l['unit_price'] as int, 2),
            'line_total': _dec(l['line_total'] as int, 2),
            'warranty_months': l['warranty_months'],
            'warranty_terms': l['warranty_terms'],
            if (showCost) 'cost_total': _dec(l['cost'] as int, 2),
          },
      ],
      if (showCost) ...{
        'cost_total': _dec(cost, 2),
        'profit': _dec((sale['total'] as int) - cost, 2),
      },
    };
  }

  /// The sale command with the real server's rules: the seller's price on every line (any
  /// amount from zero up), cash or card, stock taken FIFO (nothing changes when any line is
  /// short), numbered last.
  Object _completeSale(Map<String, dynamic> body) {
    final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
    final method = '${body['payment_method'] ?? 'cash'}';
    if (method != 'cash' && method != 'card') {
      return server.errorResponse(400, 'validation_error');
    }
    final priced = <Map<String, dynamic>>[];
    for (final l in lines) {
      final raw = server.productsData.firstWhere(
        (p) => p['id'] == l['product'],
      );
      if (l['unit_price'] == null) {
        return server.errorResponse(400, 'validation_error');
      }
      final unit = _minor(l['unit_price']);
      final quantity = _milli(l['quantity']);
      final lineTotal = (quantity * unit / 1000 + 0.0000001).round();
      final unitRef = server.unitsData.firstWhere(
        (u) => u['id'] == raw['unit'],
      );
      priced.add({
        'id': _id('sl'),
        'product': raw['id'],
        'sku': raw['sku'],
        'name': raw['name'],
        'unit_symbol': unitRef['symbol'],
        'unit_decimals': unitRef['decimal_places'],
        'quantity': quantity,
        'unit_price': unit,
        'line_total': lineTotal,
        'cost': 0,
        'warranty_months': raw['warranty_months'] ?? 0,
        'warranty_terms': raw['warranty_terms'] ?? '',
      });
    }
    final total = priced.fold<int>(0, (a, l) => a + (l['line_total'] as int));
    final saleId = _id('sale');
    final error = _postAll([
      for (final l in priced)
        () => _post(
          productId: l['product'] as String,
          locationId: body['location'] as String,
          condition: 'sellable',
          milli: -(l['quantity'] as int),
          type: 'sale',
          reason: '',
          documentType: 'sale',
          documentId: saleId,
        ),
    ]);
    if (error != null) return error;
    // exact FIFO cost per line, read back from the movements just written
    for (final l in priced) {
      l['cost'] = movements
          .where(
            (mv) =>
                mv['document_id'] == saleId &&
                (mv['product'] as Map)['id'] == l['product'],
          )
          .fold<int>(
            0,
            (a, mv) =>
                a +
                (_milli(mv['quantity']).abs() * _minor(mv['unit_cost']) / 1000)
                    .round(),
          );
    }
    final customerId = body['customer'] as String?;
    final customer = customerId == null
        ? null
        : customers.firstWhere((c) => c['id'] == customerId);
    final sale = {
      'id': saleId,
      'number': ++_saleNumber,
      'created_at': '2026-10-06T14:00:00Z',
      'location': body['location'],
      'customer_id': customerId,
      'customer_name': customer?['name'] ?? '',
      'customer_phone': customer?['phone'] ?? '',
      'total': total,
      'payment_method': method,
      'note': body['note'] ?? '',
      'lines': priced,
    };
    salesRecorded++;
    sales.insert(0, sale);
    return (status: 201, body: _presentSale(sale));
  }
}
