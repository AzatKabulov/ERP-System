import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fake_server.dart';

/// Reports, the dashboard and the activity history for the widget tests: canned figures with
/// the same permission rules as the real server (a figure a role may not see is left out of the
/// answer, not hidden by the app) and the same filters on the activity list.
class FakeReports {
  FakeReports(this.server);
  final FakeServer server;

  bool _can(String code) => server.permissions.contains(code);

  /// Every reports request the app made, newest last: its path and query.
  final List<({String path, Map<String, String> query})> requests = [];

  /// The activity history, newest first (tests may add to it).
  final List<Map<String, dynamic>> audit = [
    for (var i = 0; i < 45; i++)
      {
        'id': 'a-${100 - i}',
        'action': i == 0
            ? 'sale.completed'
            : i == 1
            ? 'sale.returned'
            : i == 2
            ? 'something.new' // an action this app has no label for
            : i.isEven
            ? 'product.created'
            : 'expense.created',
        'object_type': 'Thing',
        'object_id': 'id-$i',
        'actor': i == 5 ? null : {'id': 'u-1', 'name': 'Aman Ataýew'},
        'created_at':
            '2026-10-07T${(12 - i ~/ 10).toString().padLeft(2, '0')}:${(59 - i).toString().padLeft(2, '0')}:00Z',
        'metadata': <String, dynamic>{},
      },
  ];

  /// When set, every report answers with this status (to see the error state).
  int? failWith;
  String failCode = 'server_error';

  String? lastExportName;

  Map<String, dynamic> summary() => {
    'revenue': '540.00',
    'refunds': '120.00',
    'net_sales': '420.00',
    'sales_count': 3,
    'returns_count': 1,
    if (_can('sales.cost.view')) ...{
      'cost_of_goods': '250.00',
      'gross_profit': '170.00',
    },
    if (_can('expense.view')) 'expenses': '150.00',
    if (_can('sales.cost.view') && _can('expense.view')) 'result': '20.00',
    if (_can('stock.cost.view')) 'inventory_value': '1330.00',
    'low_stock_count': 2,
    'open_orders_count': 1,
  };

  Map<String, dynamic> sales() => {
    'sales_count': 3,
    'revenue': '540.00',
    'refunds': '120.00',
    'returns_count': 1,
    'net_sales': '420.00',
    if (_can('sales.cost.view')) ...{
      'cost_of_goods': '250.00',
      'gross_profit': '170.00',
    },
    'by_payment': [
      {'method': 'cash', 'count': 2, 'total': '300.00'},
      {'method': 'card', 'count': 1, 'total': '240.00'},
    ],
    'by_day': [
      {
        'date': '2026-10-06',
        'count': 1,
        'revenue': '240.00',
        'refunds': '0.00',
      },
      {
        'date': '2026-10-07',
        'count': 2,
        'revenue': '300.00',
        'refunds': '120.00',
      },
    ],
    'top_products': [
      {
        'product': 'p-seed-1',
        'sku': 'BP-100',
        'name': 'Тормозные колодки',
        'unit_symbol': 'шт',
        'unit_decimals': 0,
        'quantity': '5.000',
        'revenue': '540.00',
      },
    ],
  };

  Map<String, dynamic> stock() => {
    'low_stock_count': 2,
    'low_stock': [
      {
        'product': {
          'id': 'p-seed-1',
          'sku': 'BP-100',
          'name': 'Тормозные колодки',
          'unit_symbol': 'шт',
          'unit_decimals': 0,
        },
        'location': {'id': 'l-1', 'name': 'Esasy dükan'},
        'on_hand': '1.000',
        'minimum': '5.000',
        'target': '20.000',
      },
    ],
    if (_can('stock.cost.view'))
      'value': {
        'total': '1330.00',
        'by_location': [
          {
            'location': {'id': 'l-2', 'name': 'Ammar'},
            'total': '1330.00',
            'by_condition': {
              'sellable': '1200.00',
              'damaged': '130.00',
              'inspection': '0.00',
              'in_transit': '0.00',
            },
          },
        ],
      },
    'movements': [
      {
        'type': 'sale',
        'count': 3,
        'quantity_in': '0.000',
        'quantity_out': '5.000',
      },
      {
        'type': 'return_in',
        'count': 1,
        'quantity_in': '1.000',
        'quantity_out': '0.000',
      },
    ],
  };

  Map<String, dynamic> purchasing() => {
    'orders_count': 2,
    'deliveries_count': 1,
    'by_status': [
      {'status': 'received', 'count': 1},
      {'status': 'draft', 'count': 1},
    ],
    if (_can('purchasing.cost.view')) ...{
      'ordered_total': '1830.00',
      'received_value': '500.00',
    },
    'by_supplier': [
      {
        'supplier': {'id': 's-1', 'name': 'Ашхабад Запчасти'},
        'orders': 2,
        if (_can('purchasing.cost.view')) 'received_value': '500.00',
      },
    ],
    'supplier_returns_count': 1,
    if (_can('purchasing.cost.view')) 'supplier_returns_credit': '50.00',
  };

  Map<String, dynamic> returns() => {
    'returns_count': 1,
    'refund_total': '120.00',
    'by_condition': [
      {'condition': 'sellable', 'quantity': '1.000', 'refund': '120.00'},
    ],
    'by_reason': [
      {'reason': 'Не подошли по размеру', 'count': 1, 'refund': '120.00'},
    ],
    'supplier_returns': {
      'count': 1,
      if (_can('purchasing.cost.view')) 'credit': '50.00',
    },
  };

  Map<String, dynamic> expenses() => {
    'total': '150.00',
    'count': 1,
    'by_category': [
      {
        'category': {'id': 'xc-1', 'name': 'Аренда'},
        'total': '150.00',
        'count': 1,
      },
    ],
    'by_location': [
      {
        'location': {'id': 'l-1', 'name': 'Esasy dükan'},
        'total': '150.00',
        'count': 1,
      },
    ],
  };

  Map<String, dynamic> dashboard() => {
    'generated_at': '2026-10-07T12:00:00Z',
    if (_can('sales.view')) ...{
      'sales_today': {'count': 2, 'total': '300.00'},
      'sales_month': {'count': 3, 'total': '540.00'},
    },
    if (_can('sales.cost.view')) 'gross_profit_month': '170.00',
    if (_can('expense.view')) 'expenses_month': '150.00',
    if (_can('stock.cost.view')) 'inventory_value': '1330.00',
    if (_can('stock.view')) 'low_stock_count': 2,
    if (_can('reorder.view')) 'reorder_count': 1,
    if (_can('purchasing.view')) 'open_orders_count': 1,
    if (_can('warranty.view')) 'open_claims_count': 4,
    if (_can('audit.view')) 'recent_activity': audit.take(3).toList(),
  };

  http.Response? handle(http.Request request, String rest) {
    final q = request.url.queryParameters;
    if (request.method != 'GET') return null;

    if (rest == 'dashboard/') {
      requests.add((path: rest, query: q));
      if (!_can('dashboard.view')) {
        return server.errorResponse(403, 'permission_denied');
      }
      return server.jsonResponse(200, dashboard());
    }

    final report = RegExp(r'^reports/([a-z]+)/(export/)?$').firstMatch(rest);
    if (report != null) {
      requests.add((path: rest, query: q));
      final name = report.group(1)!;
      final needed = name == 'expenses' ? 'expense.view' : 'report.view';
      if (!_can(needed)) return server.errorResponse(403, 'permission_denied');
      if (failWith != null) return server.errorResponse(failWith!, failCode);
      if ((q['date_from'] ?? '').compareTo(q['date_to'] ?? '') > 0) {
        return server.errorResponse(400, 'validation_error');
      }
      final body = switch (name) {
        'summary' => summary(),
        'sales' => sales(),
        'stock' => stock(),
        'purchasing' => purchasing(),
        'returns' => returns(),
        'expenses' => expenses(),
        _ => null,
      };
      if (body == null) return null;
      if (report.group(2) != null) {
        lastExportName = '$name-${q['date_from']}-${q['date_to']}.csv';
        return http.Response.bytes(
          [
            0xEF,
            0xBB,
            0xBF,
            ...utf8.encode('date;count;revenue\r\n2026-10-07;2;300.00'),
          ],
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      }
      return server.jsonResponse(200, body);
    }

    if (rest == 'audit/actions/') {
      requests.add((path: rest, query: q));
      if (!_can('audit.view')) {
        return server.errorResponse(403, 'permission_denied');
      }
      final actions = {for (final e in audit) e['action'] as String}.toList()
        ..sort();
      return server.jsonResponse(200, {'actions': actions});
    }
    if (rest == 'audit/') {
      requests.add((path: rest, query: q));
      if (!_can('audit.view')) {
        return server.errorResponse(403, 'permission_denied');
      }
      final text = (q['q'] ?? '').toLowerCase();
      final all = [
        for (final e in audit)
          if ((q['action'] == null ||
                  e['action'] == q['action'] ||
                  (e['action'] as String).startsWith('${q['action']}.')) &&
              (text.isEmpty ||
                  '${e['action']} ${e['object_type']} ${e['object_id']}'
                      .toLowerCase()
                      .contains(text)))
            e,
      ];
      final offset = int.tryParse(q['offset'] ?? '') ?? 0;
      final limit = int.tryParse(q['limit'] ?? '') ?? 30;
      return server.jsonResponse(200, {
        'count': all.length,
        'next': null,
        'previous': null,
        'results': all.skip(offset).take(limit).toList(),
      });
    }
    return null;
  }
}
