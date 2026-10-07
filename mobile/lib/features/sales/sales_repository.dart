import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'sales_models.dart';

/// Sales, customers and the PDF documents over the API. A sale itself is a stock-changing
/// command and is sent by the OperationRunner (see [salePath] and [saleBody]).
class SalesRepository {
  SalesRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';
  String get salePath => '$_base/sales/';

  /// Quantities, discounts and the expected total go as exact decimal text. Prices are
  /// never sent: the server prices every line itself, and refuses the sale (`price_changed`)
  /// if the total the cashier saw is no longer right.
  Map<String, dynamic> saleBody({
    required String locationId,
    required String? customerId,
    required int expectedTotalMinor,
    required List<({String productId, int quantityMilli, int discountMinor})>
    lines,
    required List<({String method, int amountMinor})> payments,
    String note = '',
  }) => {
    'location': locationId,
    'customer': customerId,
    'note': note,
    'expected_total': toServerDecimal(expectedTotalMinor, 2),
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'discount': toServerDecimal(l.discountMinor, 2),
        },
    ],
    'payments': [
      for (final p in payments)
        {'method': p.method, 'amount': toServerDecimal(p.amountMinor, 2)},
    ],
  };

  Future<SalePage> sales({
    String query = '',
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      salePath,
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return SalePage([
      for (final r in map['results'] as List)
        SaleSummary.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<SaleDetail> sale(String id) async =>
      SaleDetail.fromJson((await api.get('$salePath$id/')).map);

  /// The PDF bytes of a receipt or invoice. [lang] null = the business's document language.
  Future<Uint8List> document(
    String id, {
    String kind = 'receipt',
    String? lang,
  }) async {
    final response = await api.download(
      '$salePath$id/document/',
      query: {'kind': kind, 'lang': ?lang},
    );
    return response.bytes ?? Uint8List(0);
  }

  Future<List<Customer>> customers({String query = ''}) async {
    final map = (await api.get(
      '$_base/customers/',
      query: {if (query.trim().isNotEmpty) 'q': query.trim(), 'limit': '30'},
    )).map;
    return [
      for (final r in map['results'] as List)
        Customer.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<Customer> createCustomer(String name, String phone) async =>
      Customer.fromJson(
        (await api.post(
          '$_base/customers/',
          body: {'name': name, 'phone': phone},
        )).map,
      );
}
