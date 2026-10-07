import 'dart:convert';
import 'dart:typed_data';

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

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Expenses, receipt files, warranty claims and the CSV import for the widget tests: a small
/// stand-in with the same rules as the real server (the file's real type decides, 5 MB at most,
/// an expired warranty needs the override right and a note, an import is all or nothing).
class FakeOffice {
  FakeOffice(this.server);
  final FakeServer server;

  int _ids = 100; // above the seeded ids
  String _id(String prefix) => '$prefix-${++_ids}';
  bool _can(String code) => server.permissions.contains(code);

  // ---- expenses and files -------------------------------------------------------
  final List<Map<String, dynamic>> categories = [
    {'id': 'xc-1', 'name': 'Аренда', 'is_active': true},
    {'id': 'xc-2', 'name': 'Зарплата', 'is_active': true},
    {'id': 'xc-3', 'name': 'Транспорт', 'is_active': true},
  ];
  final List<Map<String, dynamic>> expenses = []; // newest first
  final Map<String, ({String name, String type, Uint8List bytes})> files = {};
  int maxUpload = 5 * 1024 * 1024;
  int expensesCreated = 0;

  // ---- warranty claims ----------------------------------------------------------
  final List<Map<String, dynamic>> claims = []; // newest first
  int _claimNumber = 0;
  int claimsOpened = 0;
  int claimsClosed = 0;

  // ---- CSV ------------------------------------------------------------------------
  int importsApplied = 0;
  int importLimit = 2000;

  Map<String, dynamic> _where(String id) => {
    'id': id,
    'name': server.locationsData.firstWhere((l) => l['id'] == id)['name'],
  };

  Map<String, dynamic> _person() => {'id': 'u-1', 'name': 'Aman Ataýew'};

  /// A stored expense, as the server shows it.
  Map<String, dynamic> presentExpense(Map<String, dynamic> e) {
    final attachment = e['attachment'] as String?;
    final file = attachment == null ? null : files[attachment];
    return {
      'id': e['id'],
      'category': {
        'id': e['category'],
        'name': categories.firstWhere((c) => c['id'] == e['category'])['name'],
      },
      'location': _where(e['location'] as String),
      'amount': _dec(e['amount'] as int, 2),
      'spent_on': e['spent_on'],
      'description': e['description'],
      'attachment': file == null
          ? null
          : {
              'id': attachment,
              'name': file.name,
              'content_type': file.type,
              'size': file.bytes.length,
            },
      'created_by': _person(),
      'created_at': '2026-10-07T09:00:00Z',
      'voided': e['voided'] ?? false,
      'void_reason': e['void_reason'] ?? '',
    };
  }

  /// Puts an expense in directly (test set-up).
  Map<String, dynamic> seedExpense({
    required String category,
    required int amountMinor,
    required String spentOn,
    String description = '',
    String location = 'l-1',
  }) {
    final e = {
      'id': _id('ex'),
      'category': category,
      'location': location,
      'amount': amountMinor,
      'spent_on': spentOn,
      'description': description,
      'attachment': null,
      'voided': false,
      'void_reason': '',
    };
    expenses.insert(0, e);
    return e;
  }

  List<Map<String, dynamic>> _filtered(Map<String, String> q) => [
    for (final e in expenses)
      if ((q['include_void'] == '1' || e['voided'] != true) &&
          (q['date_from'] == null ||
              (e['spent_on'] as String).compareTo(q['date_from']!) >= 0) &&
          (q['date_to'] == null ||
              (e['spent_on'] as String).compareTo(q['date_to']!) <= 0) &&
          (q['category'] == null || e['category'] == q['category']) &&
          (q['location'] == null || e['location'] == q['location']))
        e,
  ];

  /// What the file really is, by its first bytes (the name and the claimed type are ignored).
  String? _detectType(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
      return 'image/png';
    }
    if (b.length >= 5 &&
        utf8.decode(b.sublist(0, 5), allowMalformed: true) == '%PDF-') {
      return 'application/pdf';
    }
    return null;
  }

  /// The file and its name inside a multipart body.
  ({String name, Uint8List bytes})? _filePart(Map<String, dynamic> body) {
    final raw = body['__multipart'] as Uint8List?;
    if (raw == null) {
      return null;
    }
    final text = latin1.decode(raw);
    final nameMatch = RegExp(r'filename="([^"]*)"').firstMatch(text);
    final start = text.indexOf('\r\n\r\n');
    final end = text.lastIndexOf('\r\n--');
    if (nameMatch == null || start < 0 || end <= start) {
      return null;
    }
    return (
      name: utf8.decode(latin1.encode(nameMatch.group(1)!)),
      bytes: Uint8List.fromList(raw.sublist(start + 4, end)),
    );
  }

  Object _present(Map<String, dynamic> claim, {bool full = true}) {
    final base = {
      'id': claim['id'],
      'number': claim['number'],
      'status': claim['status'],
      'outcome': claim['outcome'],
      'out_of_warranty': claim['out_of_warranty'],
      'sale': {'id': claim['sale'], 'number': claim['sale_number']},
      'sale_line': {
        'id': claim['sale_line'],
        'warranty_months': claim['warranty_months'],
        'warranty_until': claim['warranty_until'],
        'quantity': _dec(claim['sold'] as int, 3),
      },
      'product': {
        'sku': claim['sku'],
        'name': claim['name'],
        'unit_symbol': claim['unit_symbol'],
        'unit_decimals': claim['unit_decimals'],
      },
      'quantity': _dec(claim['quantity'] as int, 3),
      'customer_name': claim['customer_name'],
      'customer_phone': claim['customer_phone'],
      'problem': claim['problem'],
      'resolution_note': claim['resolution_note'],
      'return': claim['return_number'] == null
          ? null
          : {'id': claim['return_id'], 'number': claim['return_number']},
      'opened_by': _person(),
      'opened_at': claim['opened_at'],
      'closed_at': claim['closed_at'],
    };
    if (!full) {
      return base;
    }
    return {
      ...base,
      'events': [
        for (final e in (claim['events'] as List).cast<Map<String, dynamic>>())
          {
            'id': e['id'],
            'kind': e['kind'],
            'note': e['note'],
            'outcome': e['outcome'],
            'created_at': e['created_at'],
            'actor': _person(),
          },
      ],
    };
  }

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

    // ---- files ----
    if (rest == 'attachments/' && m == 'POST') {
      final part = _filePart(body);
      if (part == null) {
        return server.errorResponse(400, 'file_required');
      }
      if (part.bytes.length > maxUpload) {
        return server.errorResponse(
          400,
          'file_too_large',
          params: {'max_bytes': maxUpload},
        );
      }
      final type = _detectType(part.bytes);
      if (type == null) {
        return server.errorResponse(400, 'file_type_not_allowed');
      }
      final id = _id('att');
      files[id] = (name: part.name, type: type, bytes: part.bytes);
      return server.jsonResponse(201, {
        'id': id,
        'name': part.name,
        'content_type': type,
        'size': part.bytes.length,
        'created_at': '2026-10-07T09:00:00Z',
      });
    }
    final file = RegExp(r'^attachments/([^/]+)/$').firstMatch(rest);
    if (file != null && m == 'GET') {
      final stored = files[file.group(1)];
      if (stored == null) {
        return server.errorResponse(404, 'not_found');
      }
      return http.Response.bytes(
        stored.bytes,
        200,
        headers: {'content-type': stored.type},
      );
    }

    // ---- expense categories and expenses ----
    if (rest == 'expense-categories/' && m == 'GET') {
      return page(categories);
    }
    if (rest == 'expense-categories/' && m == 'POST') {
      final name = '${body['name']}'.trim();
      if (categories.any(
        (c) => '${c['name']}'.toLowerCase() == name.toLowerCase(),
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
      final created = {'id': _id('xc'), 'name': name, 'is_active': true};
      categories.add(created);
      return server.jsonResponse(201, created);
    }
    if (rest == 'expenses/summary/' && m == 'GET') {
      final rows = _filtered(q);
      final byCategory = <String, ({int total, int count})>{};
      var total = 0;
      for (final e in rows) {
        total += e['amount'] as int;
        final before = byCategory[e['category']] ?? (total: 0, count: 0);
        byCategory['${e['category']}'] = (
          total: before.total + (e['amount'] as int),
          count: before.count + 1,
        );
      }
      return server.jsonResponse(200, {
        'total': _dec(total, 2),
        'count': rows.length,
        'by_category': [
          for (final entry in byCategory.entries)
            {
              'category': {
                'id': entry.key,
                'name': categories.firstWhere(
                  (c) => c['id'] == entry.key,
                )['name'],
              },
              'total': _dec(entry.value.total, 2),
              'count': entry.value.count,
            },
        ],
      });
    }
    if (rest == 'expenses/' && m == 'GET') {
      return page([for (final e in _filtered(q)) presentExpense(e)]);
    }
    if (rest == 'expenses/' && m == 'POST') {
      final error = _checkExpense(body);
      if (error != null) {
        return error;
      }
      final e = {
        'id': _id('ex'),
        'category': body['category'],
        'location': body['location'],
        'amount': _minor(body['amount']),
        'spent_on': body['spent_on'],
        'description': body['description'] ?? '',
        'attachment': body['attachment'],
        'voided': false,
        'void_reason': '',
      };
      expenses.insert(0, e);
      expensesCreated++;
      return server.jsonResponse(201, presentExpense(e));
    }
    final one = RegExp(r'^expenses/([^/]+)/(void/)?$').firstMatch(rest);
    if (one != null) {
      final e = expenses.where((x) => x['id'] == one.group(1)).firstOrNull;
      if (e == null) {
        return server.errorResponse(404, 'not_found');
      }
      if (one.group(2) == null && m == 'GET') {
        return server.jsonResponse(200, presentExpense(e));
      }
      if (one.group(2) == null && m == 'PATCH') {
        if (e['voided'] == true) {
          return server.errorResponse(409, 'expense_void');
        }
        final error = _checkExpense(body);
        if (error != null) {
          return error;
        }
        e['category'] = body['category'];
        e['location'] = body['location'];
        e['amount'] = _minor(body['amount']);
        e['spent_on'] = body['spent_on'];
        e['description'] = body['description'] ?? '';
        e['attachment'] = body['attachment'];
        return server.jsonResponse(200, presentExpense(e));
      }
      if (one.group(2) != null && m == 'POST') {
        if (e['voided'] == true) {
          return server.errorResponse(409, 'already_void');
        }
        if ('${body['reason'] ?? ''}'.trim().isEmpty) {
          return server.errorResponse(400, 'validation_error');
        }
        e['voided'] = true;
        e['void_reason'] = '${body['reason']}'.trim();
        return server.jsonResponse(200, presentExpense(e));
      }
    }

    // ---- warranty claims ----
    if (rest == 'warranty-claims/' && m == 'GET') {
      return page([
        for (final c in claims)
          if (q['status'] == null || q['status'] == c['status'])
            _present(c, full: false) as Map<String, dynamic>,
      ]);
    }
    if (rest == 'warranty-claims/' && m == 'POST') {
      return _openClaim(body);
    }
    final claimRoute = RegExp(
      r'^warranty-claims/([^/]+)/(notes/|close/)?$',
    ).firstMatch(rest);
    if (claimRoute != null) {
      final claim = claims
          .where((c) => c['id'] == claimRoute.group(1))
          .firstOrNull;
      if (claim == null) {
        return server.errorResponse(404, 'not_found');
      }
      final action = claimRoute.group(2);
      if (action == null && m == 'GET') {
        return server.jsonResponse(200, _present(claim));
      }
      if (action == 'notes/' && m == 'POST') {
        if (claim['status'] != 'open') {
          return server.errorResponse(409, 'claim_closed');
        }
        (claim['events'] as List).add({
          'id': _id('we'),
          'kind': 'note',
          'note': '${body['note']}',
          'outcome': null,
          'created_at': '2026-10-07T11:00:00Z',
        });
        return server.jsonResponse(200, _present(claim));
      }
      if (action == 'close/' && m == 'POST') {
        return server.runCommand(request, body, () => _closeClaim(claim, body));
      }
    }

    // ---- CSV ----
    if (rest == 'catalog/export/' && m == 'GET') {
      final rows = [
        'sku;name;unit;category;brand;price;currency;default_cost;warranty_months;warranty_terms;return_days;barcodes',
        for (final p in server.productsData)
          [
            p['sku'],
            p['name'],
            'шт',
            '',
            '',
            p['price_amount'],
            p['price_currency'],
            p['default_purchase_cost'] ?? '',
            p['warranty_months'] ?? 0,
            p['warranty_terms'] ?? '',
            p['return_days'] ?? '',
            (p['barcodes'] as List).join('|'),
          ].join(';'),
      ];
      return http.Response.bytes(
        [0xEF, 0xBB, 0xBF, ...utf8.encode(rows.join('\r\n'))],
        200,
        headers: {'content-type': 'text/csv; charset=utf-8'},
      );
    }
    if ((rest == 'catalog/import/preview/' ||
            rest == 'catalog/import/apply/') &&
        m == 'POST') {
      final part = _filePart(body);
      if (part == null) {
        return server.errorResponse(400, 'file_required');
      }
      final checked = _checkCsv(utf8.decode(part.bytes, allowMalformed: true));
      if (checked.fatal != null) {
        return server.errorResponse(400, checked.fatal!);
      }
      if (rest == 'catalog/import/preview/') {
        return server.jsonResponse(200, {
          'rows': checked.rows.length,
          'valid': checked.rows.length - checked.badRows,
          'errors': checked.errors.take(200).toList(),
          'error_count': checked.errors.length,
          'truncated': checked.errors.length > 200,
        });
      }
      if (checked.errors.isNotEmpty) {
        return server.errorResponse(
          409,
          'import_invalid',
          params: {
            'errors': checked.errors.take(50).toList(),
            'error_count': checked.errors.length,
          },
        );
      }
      for (final r in checked.rows) {
        server.productsData.add({
          'id': 'p-imp-${server.productsData.length + 1}',
          'sku': r['sku'],
          'name': r['name'],
          'category': null,
          'brand': null,
          'unit': 'un-1',
          'price_amount': r['price'],
          'price_currency': r['currency'],
          'default_purchase_cost': null,
          'warranty_months': 0,
          'warranty_terms': '',
          'return_days': null,
          'barcodes': <String>[],
          'is_active': true,
          'created_at': '2026-10-07T10:00:00Z',
          'updated_at': '2026-10-07T10:00:00Z',
        });
      }
      importsApplied++;
      return server.jsonResponse(201, {'created': checked.rows.length});
    }
    return null;
  }

  http.Response? _checkExpense(Map<String, dynamic> body) {
    if (!categories.any((c) => c['id'] == body['category'])) {
      return server.errorResponse(400, 'validation_error');
    }
    if (_minor(body['amount']) <= 0) {
      return server.errorResponse(400, 'validation_error');
    }
    final date = DateTime.tryParse('${body['spent_on']}');
    if (date == null || date.isAfter(DateTime.now())) {
      return server.errorResponse(400, 'future_date');
    }
    final attachment = body['attachment'];
    if (attachment != null && !files.containsKey(attachment)) {
      return server.errorResponse(400, 'validation_error');
    }
    return null;
  }

  ({
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> errors,
    int badRows,
    String? fatal,
  })
  _checkCsv(String text) {
    final clean = text.startsWith('﻿') ? text.substring(1) : text;
    final lines = clean
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return (rows: [], errors: [], badRows: 0, fatal: 'invalid_header');
    }
    final delimiter = lines.first.contains(';') ? ';' : ',';
    final header = lines.first.split(delimiter);
    for (final required in ['sku', 'name', 'unit', 'price']) {
      if (!header.contains(required)) {
        return (rows: [], errors: [], badRows: 0, fatal: 'invalid_header');
      }
    }
    if (lines.length - 1 > importLimit) {
      return (rows: [], errors: [], badRows: 0, fatal: 'import_too_large');
    }
    final rows = <Map<String, dynamic>>[];
    final errors = <Map<String, dynamic>>[];
    final seen = <String>{};
    var bad = 0;
    for (var i = 1; i < lines.length; i++) {
      final cells = lines[i].split(delimiter);
      final row = {
        for (var c = 0; c < header.length; c++)
          header[c]: c < cells.length ? cells[c].trim() : '',
      };
      final before = errors.length;
      void fail(String field, String code) =>
          errors.add({'row': i, 'field': field, 'code': code});
      if ('${row['sku']}'.isEmpty) fail('sku', 'required');
      if ('${row['name']}'.isEmpty) fail('name', 'required');
      if (double.tryParse('${row['price']}'.replaceAll(',', '.')) == null) {
        fail('price', 'invalid_number');
      }
      if (!['шт', 'pc'].contains(row['unit'])) fail('unit', 'unknown_unit');
      final sku = '${row['sku']}'.toLowerCase();
      if (sku.isNotEmpty) {
        if (server.productsData.any(
          (p) => '${p['sku']}'.toLowerCase() == sku,
        )) {
          fail('sku', 'sku_exists');
        } else if (!seen.add(sku)) {
          fail('sku', 'sku_duplicate_in_file');
        }
      }
      if (errors.length > before) bad++;
      rows.add({
        'sku': row['sku'],
        'name': row['name'],
        'price': '${row['price']}'.replaceAll(',', '.'),
        'currency': (row['currency'] ?? '').toString().isEmpty
            ? 'TMT'
            : row['currency'],
      });
    }
    return (rows: rows, errors: errors, badRows: bad, fatal: null);
  }

  http.Response _openClaim(Map<String, dynamic> body) {
    Map<String, dynamic>? sale;
    Map<String, dynamic>? line;
    for (final s in server.ledger.sales) {
      for (final l in (s['lines'] as List).cast<Map<String, dynamic>>()) {
        if (l['id'] == body['sale_line']) {
          sale = s;
          line = l;
        }
      }
    }
    if (sale == null || line == null) {
      return server.errorResponse(404, 'not_found');
    }
    final months = (line['warranty_months'] ?? 0) as int;
    final until = line['warranty_until'] as String?;
    final expired =
        months == 0 ||
        (until != null && until.compareTo(_day(DateTime.now())) < 0);
    var outOfWarranty = false;
    if (expired) {
      if (!_can('warranty.override')) {
        return server.errorResponse(
          409,
          months == 0 ? 'no_warranty' : 'warranty_expired',
          params: {'until': until},
        );
      }
      if (body['override'] != true ||
          '${body['override_note'] ?? ''}'.trim().isEmpty) {
        return server.errorResponse(
          409,
          months == 0 ? 'no_warranty' : 'warranty_expired',
          params: {'until': until},
        );
      }
      outOfWarranty = true;
    }
    final quantity = _milli(body['quantity']);
    final remaining =
        (line['quantity'] as int) - ((line['returned'] ?? 0) as int);
    if (quantity > remaining || '${body['problem'] ?? ''}'.trim().isEmpty) {
      return server.errorResponse(400, 'validation_error');
    }
    final claim = {
      'id': _id('wc'),
      'number': ++_claimNumber,
      'status': 'open',
      'outcome': null,
      'out_of_warranty': outOfWarranty,
      'sale': sale['id'],
      'sale_number': sale['number'],
      'sale_line': line['id'],
      'warranty_months': months,
      'warranty_until': until,
      'sold': line['quantity'],
      'product': line['product'],
      'location': sale['location'],
      'sku': line['sku'],
      'name': line['name'],
      'unit_symbol': line['unit_symbol'],
      'unit_decimals': line['unit_decimals'],
      'quantity': quantity,
      'customer_name': sale['customer_name'],
      'customer_phone': sale['customer_phone'],
      'problem': '${body['problem']}'.trim(),
      'resolution_note': '',
      'return_id': null,
      'return_number': null,
      'opened_at': '2026-10-07T10:00:00Z',
      'closed_at': null,
      'events': [
        {
          'id': _id('we'),
          'kind': 'opened',
          'note': outOfWarranty ? '${body['override_note']}' : '',
          'outcome': null,
          'created_at': '2026-10-07T10:00:00Z',
        },
      ],
    };
    claimsOpened++;
    claims.insert(0, claim);
    return server.jsonResponse(201, _present(claim));
  }

  Object _closeClaim(Map<String, dynamic> claim, Map<String, dynamic> body) {
    if (claim['status'] != 'open') {
      return server.errorResponse(409, 'claim_closed');
    }
    final outcome = '${body['outcome']}';
    final note = '${body['note'] ?? ''}'.trim();
    if (outcome == 'rejected' && note.isEmpty) {
      return server.errorResponse(400, 'validation_error');
    }
    final sale = server.ledger.sales.firstWhere(
      (s) => s['id'] == claim['sale'],
    );
    final line = (sale['lines'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((l) => l['id'] == claim['sale_line']);
    final milli = claim['quantity'] as int;
    if (outcome == 'replacement') {
      final error = server.ledger.warrantyReplacement(
        sale,
        line,
        milli,
        '${claim['id']}',
      );
      if (error != null) {
        return error;
      }
    }
    if (outcome == 'refund') {
      final made = server.ledger.warrantyRefund(
        sale,
        line,
        milli,
        'Warranty W-${(claim['number'] as int).toString().padLeft(4, '0')}',
      );
      if (made is http.Response) {
        return made;
      }
      final record = (made as ({int status, Object body})).body as Map;
      claim['return_id'] = record['id'];
      claim['return_number'] = record['number'];
    }
    claim['status'] = 'closed';
    claim['outcome'] = outcome;
    claim['resolution_note'] = note;
    claim['closed_at'] = '2026-10-07T12:00:00Z';
    (claim['events'] as List).add({
      'id': _id('we'),
      'kind': 'closed',
      'note': note,
      'outcome': outcome,
      'created_at': '2026-10-07T12:00:00Z',
    });
    claimsClosed++;
    return (status: 200, body: _present(claim));
  }
}
