import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'sales_models.dart';

/// Sales, customers and the receipt PDF over the API. A sale itself is a stock-changing
/// command and is sent by the OperationRunner (see [salePath] and [saleBody]).
class SalesRepository {
  SalesRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';
  String get salePath => '$_base/sales/';

  /// Quantities and prices go as exact decimal text. The seller sets every price, so each
  /// line carries the price shown on screen; the server only checks it is not negative.
  Map<String, dynamic> saleBody({
    required String locationId,
    required String? customerId,
    required String paymentMethod,
    required List<({String productId, int quantityMilli, int unitPriceMinor})>
    lines,
    String note = '',
  }) => {
    'location': locationId,
    'customer': customerId,
    'note': note,
    'payment_method': paymentMethod,
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'unit_price': toServerDecimal(l.unitPriceMinor, 2),
        },
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

  /// The PDF bytes of the receipt. [lang] null = the business's document language.
  Future<Uint8List> receipt(String id, {String? lang}) async {
    final response = await api.download(
      '$salePath$id/document/',
      query: {'lang': ?lang},
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
