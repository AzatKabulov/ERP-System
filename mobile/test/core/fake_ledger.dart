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

  // ---- transfers and counts ---------------------------------------------------
  final List<Map<String, dynamic>> transfers = []; // newest first
  final List<Map<String, dynamic>> counts = []; // newest first
  int _transferNumber = 0;
  int _countNumber = 0;

  /// Commands the server actually carried out (to prove nothing happens twice).
  int transfersDispatched = 0;

  // ---- receiving by scanning ----------------------------------------------------
  final List<Map<String, dynamic>> intakes = []; // newest first
  int _intakeNumber = 0;
  int intakesPosted = 0;
  int transfersReceived = 0;
  int countsApproved = 0;

  // ---- returns, supplier returns, reorder ---------------------------------------
  final List<Map<String, dynamic>> saleReturns = []; // newest first
  final List<Map<String, dynamic>> supplierReturns = []; // newest first
  final Map<String, List<Map<String, dynamic>>> reorderLevels = {};
  int _returnNumber = 0;
  int _supplierReturnNumber = 0;

  /// What the server actually carried out (to prove nothing happens twice).
  int returnsRecorded = 0;
  int returnInspections = 0;
  int supplierReturnsRecorded = 0;

  /// Tests flip this to make every dated return window look expired.
  bool returnWindowOver = false;

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

  /// Receives everything still outstanding on [order] as one delivery (test set-up).
  void seedDelivery(Map<String, dynamic> order) {
    final lines = (order['lines'] as List).cast<Map<String, dynamic>>();
    final deliveryId = _id('dl');
    final deliveryLines = <Map<String, dynamic>>[];
    for (final line in lines) {
      final quantity = (line['quantity'] as int) - (line['received'] as int);
      if (quantity == 0) continue;
      _post(
        productId: line['product'] as String,
        locationId: order['location'] as String,
        condition: 'sellable',
        milli: quantity,
        costMinor: line['cost'] as int,
        type: 'receipt',
        reason: '',
        documentType: 'delivery',
        documentId: deliveryId,
      );
      line['received'] = line['quantity'];
      deliveryLines.add({
        'id': _id('dll'),
        'order_line': line['id'],
        'product': line['product'],
        'quantity': quantity,
        'cost': line['cost'],
      });
    }
    final deliveries = order['deliveries'] as List;
    deliveries.add({
      'id': deliveryId,
      'number': deliveries.length + 1,
      'received_at': '2026-10-06T13:00:00Z',
      'note': '',
      'lines': deliveryLines,
    });
    order['status'] = 'received';
  }

  /// A completed sale of one product (test set-up). Returns the stored sale.
  Map<String, dynamic> seedSale({
    required String productId,
    required String locationId,
    required String quantity,
    required String price,
    String method = 'cash',
  }) {
    final result = _completeSale({
      'location': locationId,
      'payment_method': method,
      'lines': [
        {'product': productId, 'quantity': quantity, 'unit_price': price},
      ],
    });
    assert(result is! http.Response, 'the sale was refused');
    return sales.first;
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
                  'returned_quantity': _dec((dl['returned'] ?? 0) as int, 3),
                  'returnable_quantity': _dec(
                    (dl['quantity'] as int) - ((dl['returned'] ?? 0) as int),
                    3,
                  ),
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

    final ops = _stockOps(request, rest, body, page);
    if (ops != null) return ops;
    final more = _returnsOps(request, rest, body, page);
    if (more != null) return more;

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
            'return_days': l['return_days'],
            'return_until': _returnUntil(l),
            'warranty_until': l['warranty_until'],
            'returned_quantity': _dec(l['returned'] as int, 3),
            'returnable_quantity': _dec(
              (l['quantity'] as int) - (l['returned'] as int),
              3,
            ),
            'refunded_total': _dec(l['refunded'] as int, 2),
            if (showCost) 'cost_total': _dec(l['cost'] as int, 2),
          },
      ],
      'returns': [
        for (final r in saleReturns.reversed)
          if (r['sale'] == sale['id'])
            {
              'id': r['id'],
              'number': r['number'],
              'created_at': r['created_at'],
              'refund_total': _dec(r['refund'] as int, 2),
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
        'return_days': raw['return_days'],
        'returned': 0,
        'refunded': 0,
        'warranty_until': ((raw['warranty_months'] ?? 0) as int) > 0
            ? _day(
                DateTime.now().add(
                  Duration(days: 30 * (raw['warranty_months'] as int)),
                ),
              )
            : null,
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

  // ---- returns, supplier returns, reorder -------------------------------------------

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _returnUntil(Map<String, dynamic> line) {
    final days = line['return_days'] as int?;
    if (days == null) return null;
    final until = DateTime.utc(2026, 10, 6).add(Duration(days: days));
    return '${until.year}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _presentReturn(
    Map<String, dynamic> r, {
    bool summary = false,
  }) {
    final sale = sales.firstWhere((s) => s['id'] == r['sale']);
    final lines = (r['lines'] as List).cast<Map<String, dynamic>>();
    int waiting(Map<String, dynamic> l) => l['condition'] == 'inspection'
        ? (l['quantity'] as int) - (l['decided'] as int)
        : 0;
    final base = {
      'id': r['id'],
      'number': r['number'],
      'created_at': r['created_at'],
      'sale': {'id': sale['id'], 'number': sale['number']},
      'location': _where(sale['location'] as String),
      'reason': r['reason'],
      'refund_total': _dec(r['refund'] as int, 2),
    };
    if (summary) {
      return {...base, 'awaiting_inspection': lines.any((l) => waiting(l) > 0)};
    }
    return {
      ...base,
      'created_by': _person(),
      'note': '',
      'payment_method': sale['payment_method'],
      'lines': [
        for (final l in lines)
          {
            'id': l['id'],
            'sale_line': l['sale_line'],
            'product': l['product'],
            'sku': l['sku'],
            'name': l['name'],
            'unit_symbol': l['unit_symbol'],
            'unit_decimals': l['unit_decimals'],
            'quantity': _dec(l['quantity'] as int, 3),
            'condition': l['condition'],
            'refund_amount': _dec(l['refund'] as int, 2),
            'awaiting_inspection': _dec(waiting(l), 3),
          },
      ],
    };
  }

  /// The return command with the real server's rules: only what is still returnable, a window
  /// per product, the refund at the price charged (the last piece takes the remainder).
  Object _makeReturn(
    Map<String, dynamic> sale,
    Map<String, dynamic> body, {
    bool ignoreWindow = false,
  }) {
    if ('${body['reason'] ?? ''}'.trim().isEmpty) {
      return server.errorResponse(
        400,
        'validation_error',
        fields: {
          'reason': [
            {'code': 'required', 'message': 'Required'},
          ],
        },
      );
    }
    final saleLines = (sale['lines'] as List).cast<Map<String, dynamic>>();
    final built = <Map<String, dynamic>>[];
    for (final row in (body['lines'] as List).cast<Map<String, dynamic>>()) {
      final line = saleLines.firstWhere((l) => l['id'] == row['sale_line']);
      final quantity = _milli(row['quantity']);
      final remaining = (line['quantity'] as int) - (line['returned'] as int);
      if (quantity > remaining) {
        return server.errorResponse(
          409,
          'over_return',
          params: {
            'product': line['product'],
            'returnable': _dec(remaining, 3),
          },
        );
      }
      final days = line['return_days'] as int?;
      if (!ignoreWindow && days == 0) {
        return server.errorResponse(
          409,
          'returns_not_accepted',
          params: {'product': line['product']},
        );
      }
      if (!ignoreWindow && days != null && returnWindowOver) {
        return server.errorResponse(
          409,
          'return_window_expired',
          params: {'product': line['product'], 'until': _returnUntil(line)},
        );
      }
      final left = (line['line_total'] as int) - (line['refunded'] as int);
      var refund = quantity == remaining
          ? left
          : (quantity * (line['unit_price'] as int) / 1000 + 0.0000001).round();
      if (refund > left) refund = left;
      built.add({
        'line': line,
        'quantity': quantity,
        'row': row,
        'refund': refund,
      });
    }
    final returnId = _id('ret');
    final error = _postAll([
      for (final b in built)
        () {
          final line = b['line'] as Map<String, dynamic>;
          final unitCost = (line['quantity'] as int) == 0
              ? 0
              : ((line['cost'] as int) * 1000 / (line['quantity'] as int))
                    .round();
          return _post(
            productId: line['product'] as String,
            locationId: sale['location'] as String,
            condition: '${(b['row'] as Map)['condition']}',
            milli: b['quantity'] as int,
            costMinor: unitCost,
            type: 'return_in',
            reason: '${body['reason']}',
            documentType: 'return',
            documentId: returnId,
          );
        },
    ]);
    if (error != null) return error;
    final lines = <Map<String, dynamic>>[];
    for (final b in built) {
      final line = b['line'] as Map<String, dynamic>;
      line['returned'] = (line['returned'] as int) + (b['quantity'] as int);
      line['refunded'] = (line['refunded'] as int) + (b['refund'] as int);
      lines.add({
        'id': _id('rl'),
        'sale_line': line['id'],
        'product': line['product'],
        'sku': line['sku'],
        'name': line['name'],
        'unit_symbol': line['unit_symbol'],
        'unit_decimals': line['unit_decimals'],
        'quantity': b['quantity'],
        'condition': '${(b['row'] as Map)['condition']}',
        'refund': b['refund'],
        'decided': 0,
      });
    }
    final record = {
      'id': returnId,
      'number': ++_returnNumber,
      'created_at': '2026-10-06T15:00:00Z',
      'sale': sale['id'],
      'reason': '${body['reason']}'.trim(),
      'refund': lines.fold<int>(0, (a, l) => a + (l['refund'] as int)),
      'lines': lines,
    };
    returnsRecorded++;
    saleReturns.insert(0, record);
    return (status: 201, body: _presentReturn(record));
  }

  /// A warranty replacement: one sellable piece out, the defective one in as damaged.
  http.Response? warrantyReplacement(
    Map<String, dynamic> sale,
    Map<String, dynamic> line,
    int milli,
    String documentId,
  ) {
    final unitCost = (line['quantity'] as int) == 0
        ? 0
        : ((line['cost'] as int) * 1000 / (line['quantity'] as int)).round();
    return _postAll([
      () => _post(
        productId: line['product'] as String,
        locationId: sale['location'] as String,
        condition: 'sellable',
        milli: -milli,
        type: 'warranty_out',
        reason: 'warranty',
        documentType: 'warranty',
        documentId: documentId,
      ),
      () => _post(
        productId: line['product'] as String,
        locationId: sale['location'] as String,
        condition: 'damaged',
        milli: milli,
        costMinor: unitCost,
        type: 'warranty_in',
        reason: 'warranty',
        documentType: 'warranty',
        documentId: documentId,
      ),
    ]);
  }

  /// A warranty refund is an ordinary customer return of the defective goods (damaged).
  Object warrantyRefund(
    Map<String, dynamic> sale,
    Map<String, dynamic> line,
    int milli,
    String reason,
  ) => _makeReturn(sale, {
    'reason': reason,
    'lines': [
      {
        'sale_line': line['id'],
        'quantity': _dec(milli, 3),
        'condition': 'damaged',
      },
    ],
  }, ignoreWindow: true);

  Map<String, dynamic> _presentSupplierReturn(Map<String, dynamic> r) => {
    'id': r['id'],
    'number': r['number'],
    'created_at': r['created_at'],
    'supplier': {'id': r['supplier'], 'name': r['supplier_name']},
    'location': _where(r['location'] as String),
    'delivery': {
      'id': r['delivery'],
      'number': r['delivery_number'],
      'order': r['order'],
      'order_number': r['order_number'],
    },
    'created_by': _person(),
    'reason': r['reason'],
    'note': '',
    if (_can('purchasing.cost.view'))
      'credit_total': _dec(r['credit'] as int, 2),
    'lines': [
      for (final l in (r['lines'] as List).cast<Map<String, dynamic>>())
        {
          'id': l['id'],
          'delivery_line': l['delivery_line'],
          'product': _productRef(l['product'] as String),
          'quantity': _dec(l['quantity'] as int, 3),
          'condition': l['condition'],
        },
    ],
  };

  http.Response? _returnsOps(
    http.Request request,
    String rest,
    Map<String, dynamic> body,
    http.Response Function(List<Map<String, dynamic>>) page,
  ) {
    final m = request.method;
    final q = request.url.queryParameters;

    final make = RegExp(r'^sales/([^/]+)/returns/$').firstMatch(rest);
    if (make != null && m == 'POST') {
      final sale = sales.where((s) => s['id'] == make.group(1)).firstOrNull;
      if (sale == null) return server.errorResponse(404, 'not_found');
      return server.runCommand(request, body, () => _makeReturn(sale, body));
    }
    if (rest == 'returns/' && m == 'GET') {
      final text = (q['q'] ?? '').trim().toUpperCase();
      return page([
        for (final r in saleReturns)
          if (text.isEmpty ||
              'R-${(r['number'] as int).toString().padLeft(4, '0')}' == text)
            _presentReturn(r, summary: true),
      ]);
    }
    final one = RegExp(r'^returns/([^/]+)/(inspections/)?$').firstMatch(rest);
    if (one != null) {
      final record = saleReturns
          .where((r) => r['id'] == one.group(1))
          .firstOrNull;
      if (record == null) return server.errorResponse(404, 'not_found');
      if (one.group(2) == null && m == 'GET') {
        return server.jsonResponse(200, _presentReturn(record));
      }
      if (one.group(2) != null && m == 'POST') {
        return server.runCommand(request, body, () {
          final sale = sales.firstWhere((s) => s['id'] == record['sale']);
          final lines = (record['lines'] as List).cast<Map<String, dynamic>>();
          final rows = (body['lines'] as List).cast<Map<String, dynamic>>();
          for (final row in rows) {
            final line = lines.firstWhere((l) => l['id'] == row['return_line']);
            if (line['condition'] != 'inspection') {
              return server.errorResponse(409, 'not_awaiting_inspection');
            }
            final waiting =
                (line['quantity'] as int) - (line['decided'] as int);
            if (_milli(row['quantity']) > waiting) {
              return server.errorResponse(409, 'over_inspection');
            }
          }
          final error = _postAll([
            for (final row in rows) ...[
              () {
                final line = lines.firstWhere(
                  (l) => l['id'] == row['return_line'],
                );
                return _post(
                  productId: line['product'] as String,
                  locationId: sale['location'] as String,
                  condition: 'inspection',
                  milli: -_milli(row['quantity']),
                  type: 'inspection_out',
                  reason: 'inspection decided',
                  documentType: 'return',
                  documentId: record['id'] as String,
                );
              },
              () {
                final line = lines.firstWhere(
                  (l) => l['id'] == row['return_line'],
                );
                return _post(
                  productId: line['product'] as String,
                  locationId: sale['location'] as String,
                  condition: '${row['outcome']}',
                  milli: _milli(row['quantity']),
                  costMinor: 0,
                  type: 'inspection_in',
                  reason: 'inspection decided',
                  documentType: 'return',
                  documentId: record['id'] as String,
                );
              },
            ],
          ]);
          if (error != null) return error;
          for (final row in rows) {
            final line = lines.firstWhere((l) => l['id'] == row['return_line']);
            line['decided'] =
                (line['decided'] as int) + _milli(row['quantity']);
          }
          returnInspections++;
          return (status: 200, body: _presentReturn(record));
        });
      }
    }

    if (rest == 'supplier-returns/' && m == 'GET') {
      return page([for (final r in supplierReturns) _presentSupplierReturn(r)]);
    }
    if (rest == 'supplier-returns/' && m == 'POST') {
      return server.runCommand(request, body, () {
        Map<String, dynamic>? order;
        Map<String, dynamic>? delivery;
        for (final o in orders) {
          for (final d
              in (o['deliveries'] as List).cast<Map<String, dynamic>>()) {
            if (d['id'] == body['delivery']) {
              order = o;
              delivery = d;
            }
          }
        }
        if (order == null || delivery == null) {
          return server.errorResponse(404, 'not_found');
        }
        if ('${body['reason'] ?? ''}'.trim().isEmpty) {
          return server.errorResponse(400, 'validation_error');
        }
        final dLines = (delivery['lines'] as List).cast<Map<String, dynamic>>();
        final rows = (body['lines'] as List).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final line = dLines.firstWhere(
            (l) => l['id'] == row['delivery_line'],
          );
          final remaining =
              (line['quantity'] as int) - ((line['returned'] ?? 0) as int);
          if (_milli(row['quantity']) > remaining) {
            return server.errorResponse(
              409,
              'over_return',
              params: {
                'product': line['product'],
                'returnable': _dec(remaining, 3),
              },
            );
          }
        }
        final returnId = _id('sret');
        final error = _postAll([
          for (final row in rows)
            () {
              final line = dLines.firstWhere(
                (l) => l['id'] == row['delivery_line'],
              );
              return _post(
                productId: line['product'] as String,
                locationId: order!['location'] as String,
                condition: '${row['condition'] ?? 'sellable'}',
                milli: -_milli(row['quantity']),
                type: 'supplier_return',
                reason: '${body['reason']}',
                documentType: 'supplier_return',
                documentId: returnId,
              );
            },
        ]);
        if (error != null) return error;
        var credit = 0;
        final lines = <Map<String, dynamic>>[];
        for (final row in rows) {
          final line = dLines.firstWhere(
            (l) => l['id'] == row['delivery_line'],
          );
          line['returned'] =
              ((line['returned'] ?? 0) as int) + _milli(row['quantity']);
          credit += (_milli(row['quantity']) * (line['cost'] as int) / 1000)
              .round();
          lines.add({
            'id': _id('srl'),
            'delivery_line': line['id'],
            'product': line['product'],
            'quantity': _milli(row['quantity']),
            'condition': '${row['condition'] ?? 'sellable'}',
          });
        }
        final supplier = suppliers.firstWhere(
          (s) => s['id'] == order!['supplier'],
        );
        final record = {
          'id': returnId,
          'number': ++_supplierReturnNumber,
          'created_at': '2026-10-06T16:00:00Z',
          'supplier': supplier['id'],
          'supplier_name': supplier['name'],
          'location': order['location'],
          'delivery': delivery['id'],
          'delivery_number': delivery['number'],
          'order': order['id'],
          'order_number': order['number'],
          'reason': '${body['reason']}'.trim(),
          'credit': credit,
          'lines': lines,
        };
        supplierReturnsRecorded++;
        supplierReturns.insert(0, record);
        return (status: 201, body: _presentSupplierReturn(record));
      });
    }

    final levels = RegExp(
      r'^products/([^/]+)/reorder-settings/$',
    ).firstMatch(rest);
    if (levels != null) {
      final id = levels.group(1)!;
      List<Map<String, dynamic>> view() => [
        for (final r in reorderLevels[id] ?? const <Map<String, dynamic>>[])
          {
            'location': r['location'],
            'location_name': _where(r['location'] as String)['name'],
            'minimum': _dec(r['minimum'] as int, 3),
            'target': _dec(r['target'] as int, 3),
          },
      ];
      if (m == 'GET') return server.jsonResponse(200, {'settings': view()});
      if (m == 'PUT') {
        reorderLevels[id] = [
          for (final r
              in (body['settings'] as List).cast<Map<String, dynamic>>())
            {
              'location': r['location'],
              'minimum': _milli(r['minimum']),
              'target': _milli(r['target']),
            },
        ];
        return server.jsonResponse(200, {'settings': view()});
      }
    }
    if (rest == 'reorder-suggestions/' && m == 'GET') {
      final rows = <Map<String, dynamic>>[];
      reorderLevels.forEach((productId, list) {
        for (final r in list) {
          final place = r['location'] as String;
          final onHand = _sellable(productId, place);
          var onOrder = 0;
          for (final o in orders) {
            if (o['location'] != place) continue;
            if (!['ordered', 'partially_received'].contains(o['status'])) {
              continue;
            }
            for (final l in (o['lines'] as List).cast<Map<String, dynamic>>()) {
              if (l['product'] == productId) {
                onOrder += (l['quantity'] as int) - (l['received'] as int);
              }
            }
          }
          if (onHand + onOrder >= (r['minimum'] as int)) continue;
          final product = server.productsData.firstWhere(
            (p) => p['id'] == productId,
          );
          rows.add({
            'product': {
              ..._productRef(productId),
              if (_can('purchasing.cost.view'))
                'default_purchase_cost': product['default_purchase_cost'],
            },
            'location': _where(place),
            'on_hand': _dec(onHand, 3),
            'on_order': _dec(onOrder, 3),
            'minimum': _dec(r['minimum'] as int, 3),
            'target': _dec(r['target'] as int, 3),
            'suggested': _dec((r['target'] as int) - onHand - onOrder, 3),
          });
        }
      });
      return server.jsonResponse(200, {'count': rows.length, 'results': rows});
    }
    return null;
  }

  // ---- transfers and counts ---------------------------------------------------

  Map<String, dynamic> _person() => {'id': 'u-1', 'name': 'Aman Ataýew'};

  Map<String, dynamic> _where(String id) => {
    'id': id,
    'name': (server.locationsData.firstWhere((l) => l['id'] == id))['name'],
  };

  Map<String, dynamic> _presentTransfer(
    Map<String, dynamic> t, {
    bool summary = false,
  }) {
    final lines = (t['lines'] as List).cast<Map<String, dynamic>>();
    final base = {
      'id': t['id'],
      'number': t['number'],
      'status': t['status'],
      'from_location': _where(t['from'] as String),
      'to_location': _where(t['to'] as String),
      'created_at': '2026-10-07T09:00:00Z',
    };
    if (summary) return {...base, 'line_count': lines.length};
    return {
      ...base,
      'note': t['note'],
      'created_by': _person(),
      'received_by':
          t['status'] == 'received' || t['status'] == 'partially_received'
          ? _person()
          : null,
      'discrepancy_reason': t['discrepancy_reason'],
      'cancel_reason': t['cancel_reason'],
      'lines': [
        for (final l in lines)
          {
            'id': l['id'],
            'product': _productRef(l['product'] as String),
            'quantity': _dec(l['quantity'] as int, 3),
            'received_quantity': l['received'] == null
                ? null
                : _dec(l['received'] as int, 3),
          },
      ],
    };
  }

  int _sellable(String productId, String locationId) =>
      _buckets['$productId|$locationId|sellable']?.quantity ?? 0;

  Map<String, dynamic> _presentCount(
    Map<String, dynamic> c, {
    bool summary = false,
  }) {
    final lines = (c['lines'] as List).cast<Map<String, dynamic>>();
    final counted = lines.where((l) => l['counted'] != null).toList();
    final differences = counted.where((l) => l['counted'] != l['baseline']);
    final base = {
      'id': c['id'],
      'number': c['number'],
      'status': c['status'],
      'scope': c['scope'],
      'location': _where(c['location'] as String),
      'created_at': '2026-10-07T09:00:00Z',
    };
    if (summary) {
      return {
        ...base,
        'line_count': lines.length,
        'counted_count': counted.length,
        'difference_count': differences.length,
      };
    }
    final open = c['status'] == 'open' || c['status'] == 'submitted';
    return {
      ...base,
      'note': '',
      'created_by': _person(),
      'decision_reason': c['decision_reason'],
      'lines': [
        for (final l in lines)
          {
            'id': l['id'],
            'product': _productRef(l['product'] as String),
            'baseline_quantity': _dec(l['baseline'] as int, 3),
            'counted_quantity': l['counted'] == null
                ? null
                : _dec(l['counted'] as int, 3),
            'note': '',
            'variance': l['counted'] == null
                ? null
                : _dec((l['counted'] as int) - (l['baseline'] as int), 3),
            // sellable stock moved since the start (only checked while it is still open)
            'moved_since_start':
                open &&
                _sellable(l['product'] as String, c['location'] as String) !=
                    (l['baseline'] as int),
          },
      ],
    };
  }

  http.Response? _stockOps(
    http.Request request,
    String rest,
    Map<String, dynamic> body,
    http.Response Function(List<Map<String, dynamic>>) page,
  ) {
    final m = request.method;
    final q = request.url.queryParameters;

    // ---- receiving by scanning ----
    if (rest == 'intakes/' && m == 'POST') {
      return server.runCommand(request, body, () {
        final location = body['location'] as String;
        final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
        if (!server.permissions.contains('stock.cost.view') &&
            lines.any((l) => l['unit_cost'] != null)) {
          return server.errorResponse(403, 'permission_denied');
        }
        final id = _id('in');
        final error = _postAll([
          for (final l in lines)
            () => _post(
              productId: l['product'] as String,
              locationId: location,
              condition: 'sellable',
              milli: _milli(l['quantity']),
              costMinor: l['unit_cost'] == null ? 0 : _minor(l['unit_cost']),
              type: 'intake',
              reason: '',
              documentType: 'intake',
              documentId: id,
            ),
        ]);
        if (error != null) return error;
        intakesPosted++;
        final intake = {
          'id': id,
          'number': ++_intakeNumber,
          'location': _where(location),
          'note': body['note'] ?? '',
          'created_by': _person(),
          'created_at': '2026-10-07T09:00:00Z',
          'line_count': lines.length,
          'lines': lines,
        };
        intakes.insert(0, intake);
        return (status: 201, body: intake);
      });
    }

    // ---- transfers ----
    if (rest == 'transfers/' && m == 'GET') {
      return page([
        for (final t in transfers)
          if (q['status'] == null || q['status'] == t['status'])
            _presentTransfer(t, summary: true),
      ]);
    }
    if (rest == 'transfers/' && m == 'POST') {
      return server.runCommand(request, body, () {
        final from = body['from_location'] as String;
        final to = body['to_location'] as String;
        final lines = (body['lines'] as List).cast<Map<String, dynamic>>();
        final id = _id('tr');
        final error = _postAll([
          for (final l in lines)
            () => _post(
              productId: l['product'] as String,
              locationId: from,
              condition: 'sellable',
              milli: -_milli(l['quantity']),
              type: 'transfer_out',
              reason: '',
              documentType: 'transfer',
              documentId: id,
            ),
          for (final l in lines)
            () => _post(
              productId: l['product'] as String,
              locationId: to,
              condition: 'in_transit',
              milli: _milli(l['quantity']),
              costMinor: 0,
              type: 'transfer_in',
              reason: '',
              documentType: 'transfer',
              documentId: id,
            ),
        ]);
        if (error != null) return error;
        transfersDispatched++;
        final transfer = {
          'id': id,
          'number': ++_transferNumber,
          'status': 'dispatched',
          'from': from,
          'to': to,
          'note': body['note'] ?? '',
          'discrepancy_reason': '',
          'cancel_reason': '',
          'lines': [
            for (final l in lines)
              {
                'id': _id('tl'),
                'product': l['product'],
                'quantity': _milli(l['quantity']),
                'received': null,
              },
          ],
        };
        transfers.insert(0, transfer);
        return (status: 201, body: _presentTransfer(transfer));
      });
    }
    final oneTransfer = RegExp(
      r'^transfers/([^/]+)/(receive/|cancel/)?$',
    ).firstMatch(rest);
    if (oneTransfer != null) {
      final transfer = transfers
          .where((t) => t['id'] == oneTransfer.group(1))
          .firstOrNull;
      if (transfer == null) return server.errorResponse(404, 'not_found');
      final action = oneTransfer.group(2);
      if (action == null && m == 'GET') {
        return server.jsonResponse(200, _presentTransfer(transfer));
      }
      if (action == 'receive/' && m == 'POST') {
        return server.runCommand(request, body, () {
          if (transfer['status'] != 'dispatched') {
            return server.errorResponse(409, 'transfer_not_receivable');
          }
          final tLines = (transfer['lines'] as List)
              .cast<Map<String, dynamic>>();
          final arrived = <Object?, int>{
            for (final l in tLines) l['id']: l['quantity'] as int,
          };
          for (final r in (body['lines'] as List? ?? const [])) {
            arrived[r['line']] = _milli(r['quantity']);
          }
          final short = tLines.any((l) => arrived[l['id']]! < l['quantity']);
          final reason = '${body['reason'] ?? ''}'.trim();
          if (short && reason.isEmpty) {
            return server.errorResponse(
              400,
              'validation_error',
              fields: {
                'reason': [
                  {'code': 'required', 'message': 'Required'},
                ],
              },
            );
          }
          final id = transfer['id'] as String;
          final to = transfer['to'] as String;
          final error = _postAll([
            for (final l in tLines) ...[
              if (arrived[l['id']]! > 0)
                () => _post(
                  productId: l['product'] as String,
                  locationId: to,
                  condition: 'in_transit',
                  milli: -arrived[l['id']]!,
                  type: 'transfer_out',
                  reason: '',
                  documentType: 'transfer',
                  documentId: id,
                ),
              if (arrived[l['id']]! < (l['quantity'] as int))
                () => _post(
                  productId: l['product'] as String,
                  locationId: to,
                  condition: 'in_transit',
                  milli: -((l['quantity'] as int) - arrived[l['id']]!),
                  type: 'transfer_loss',
                  reason: reason,
                  documentType: 'transfer',
                  documentId: id,
                ),
              if (arrived[l['id']]! > 0)
                () => _post(
                  productId: l['product'] as String,
                  locationId: to,
                  condition: 'sellable',
                  milli: arrived[l['id']]!,
                  costMinor: 0,
                  type: 'transfer_in',
                  reason: '',
                  documentType: 'transfer',
                  documentId: id,
                ),
            ],
          ]);
          if (error != null) return error;
          for (final l in tLines) {
            l['received'] = arrived[l['id']];
          }
          transfer['status'] = short ? 'partially_received' : 'received';
          transfer['discrepancy_reason'] = short ? reason : '';
          transfersReceived++;
          return (status: 200, body: _presentTransfer(transfer));
        });
      }
      if (action == 'cancel/' && m == 'POST') {
        return server.runCommand(request, body, () {
          final reason = '${body['reason'] ?? ''}'.trim();
          if (reason.isEmpty) {
            return server.errorResponse(
              400,
              'validation_error',
              fields: {
                'reason': [
                  {'code': 'required', 'message': 'Required'},
                ],
              },
            );
          }
          if (transfer['status'] != 'dispatched') {
            return server.errorResponse(409, 'transfer_not_cancellable');
          }
          final id = transfer['id'] as String;
          final tLines = (transfer['lines'] as List)
              .cast<Map<String, dynamic>>();
          final error = _postAll([
            for (final l in tLines) ...[
              () => _post(
                productId: l['product'] as String,
                locationId: transfer['to'] as String,
                condition: 'in_transit',
                milli: -(l['quantity'] as int),
                type: 'transfer_out',
                reason: reason,
                documentType: 'transfer',
                documentId: id,
              ),
              () => _post(
                productId: l['product'] as String,
                locationId: transfer['from'] as String,
                condition: 'sellable',
                milli: l['quantity'] as int,
                costMinor: 0,
                type: 'transfer_in',
                reason: reason,
                documentType: 'transfer',
                documentId: id,
              ),
            ],
          ]);
          if (error != null) return error;
          transfer['status'] = 'cancelled';
          transfer['cancel_reason'] = reason;
          return (status: 200, body: _presentTransfer(transfer));
        });
      }
    }

    // ---- counts ----
    if (rest == 'counts/' && m == 'GET') {
      return page([
        for (final c in counts)
          if (q['status'] == null || q['status'] == c['status'])
            _presentCount(c, summary: true),
      ]);
    }
    if (rest == 'counts/' && m == 'POST') {
      final location = body['location'] as String;
      final scope = '${body['scope'] ?? 'full'}';
      final ids = scope == 'partial'
          ? (body['products'] as List).cast<String>()
          : [
              for (final b in _buckets.values)
                if (b.locationId == location &&
                    b.condition == 'sellable' &&
                    b.quantity > 0)
                  b.productId,
            ];
      final count = {
        'id': _id('ct'),
        'number': ++_countNumber,
        'status': 'open',
        'scope': scope,
        'location': location,
        'decision_reason': '',
        'lines': [
          for (final id in ids)
            {
              'id': _id('cl'),
              'product': id,
              'baseline': _sellable(id, location),
              'counted': null,
            },
        ],
      };
      counts.insert(0, count);
      return server.jsonResponse(201, _presentCount(count));
    }
    final oneCount = RegExp(
      r'^counts/([^/]+)/(lines/|submit/|approve/|cancel/)?$',
    ).firstMatch(rest);
    if (oneCount != null) {
      final count = counts
          .where((c) => c['id'] == oneCount.group(1))
          .firstOrNull;
      if (count == null) return server.errorResponse(404, 'not_found');
      final action = oneCount.group(2);
      final cLines = (count['lines'] as List).cast<Map<String, dynamic>>();
      if (action == null && m == 'GET') {
        return server.jsonResponse(200, _presentCount(count));
      }
      if (action == 'lines/' && m == 'PUT') {
        if (count['status'] != 'open') {
          return server.errorResponse(409, 'count_not_open');
        }
        for (final row
            in (body['lines'] as List).cast<Map<String, dynamic>>()) {
          final line = cLines
              .where((l) => l['product'] == row['product'])
              .firstOrNull;
          if (line == null) {
            cLines.add({
              'id': _id('cl'),
              'product': row['product'],
              'baseline': _sellable(
                row['product'] as String,
                count['location'] as String,
              ),
              'counted': _milli(row['counted_quantity']),
            });
          } else {
            line['counted'] = _milli(row['counted_quantity']);
          }
        }
        return server.jsonResponse(200, _presentCount(count));
      }
      if (action == 'submit/' && m == 'POST') {
        if (count['status'] != 'open') {
          return server.errorResponse(409, 'count_not_open');
        }
        if (!cLines.any((l) => l['counted'] != null)) {
          return server.errorResponse(409, 'count_empty');
        }
        count['status'] = 'submitted';
        return server.jsonResponse(200, _presentCount(count));
      }
      if (action == 'cancel/' && m == 'POST') {
        if (count['status'] != 'open' && count['status'] != 'submitted') {
          return server.errorResponse(409, 'count_not_cancellable');
        }
        count['status'] = 'cancelled';
        count['decision_reason'] = '${body['reason'] ?? ''}';
        return server.jsonResponse(200, _presentCount(count));
      }
      if (action == 'approve/' && m == 'POST') {
        if (!_can('count.approve')) {
          return server.errorResponse(403, 'permission_denied');
        }
        return server.runCommand(request, body, () {
          if (count['status'] != 'submitted') {
            return server.errorResponse(409, 'count_not_submitted');
          }
          final deltas = [
            for (final l in cLines)
              if (l['counted'] != null && l['counted'] != l['baseline']) l,
          ];
          final reason = '${body['reason'] ?? ''}'.trim();
          if (deltas.isNotEmpty && reason.isEmpty) {
            return server.errorResponse(
              400,
              'validation_error',
              fields: {
                'reason': [
                  {'code': 'required', 'message': 'Required'},
                ],
              },
            );
          }
          final id = count['id'] as String;
          final error = _postAll([
            for (final l in deltas)
              () {
                final delta = (l['counted'] as int) - (l['baseline'] as int);
                return _post(
                  productId: l['product'] as String,
                  locationId: count['location'] as String,
                  condition: 'sellable',
                  milli: delta,
                  costMinor: delta > 0 ? 0 : null,
                  type: delta > 0 ? 'adjustment_in' : 'adjustment_out',
                  reason: 'Stock count: $reason',
                  documentType: 'count',
                  documentId: id,
                );
              },
          ]);
          if (error != null) return error;
          count['status'] = 'approved';
          count['decision_reason'] = reason;
          countsApproved++;
          return (status: 200, body: _presentCount(count));
        });
      }
    }
    return null;
  }
}
