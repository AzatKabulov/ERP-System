import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'purchasing_models.dart';

/// Suppliers and purchase orders over the API. Receiving goods is a stock-changing
/// command and is sent by the [OperationRunner], not from here.
class PurchasingRepository {
  PurchasingRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';

  String receivePath(String orderId) =>
      '$_base/purchase-orders/$orderId/deliveries/';

  Map<String, dynamic> receiveBody({
    required List<({String lineId, int quantityMilli})> lines,
    String note = '',
  }) => {
    'note': note,
    'lines': [
      for (final l in lines)
        {
          'order_line': l.lineId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
        },
    ],
  };

  // ---- returns to a supplier and what to reorder ----------------------------

  String get supplierReturnPath => '$_base/supplier-returns/';

  /// Goods go back against one delivery; [condition] says where they are taken from.
  Map<String, dynamic> supplierReturnBody({
    required String deliveryId,
    required String reason,
    required List<
      ({String deliveryLineId, int quantityMilli, String condition})
    >
    lines,
  }) => {
    'delivery': deliveryId,
    'reason': reason,
    'lines': [
      for (final l in lines)
        {
          'delivery_line': l.deliveryLineId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'condition': l.condition,
        },
    ],
  };

  Future<SupplierReturnPage> supplierReturns({
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/supplier-returns/',
      query: {'limit': '$limit', 'offset': '$offset'},
    )).map;
    return SupplierReturnPage([
      for (final r in map['results'] as List)
        SupplierReturnRecord.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<List<ReorderRow>> reorderSuggestions() async {
    final map = (await api.get('$_base/reorder-suggestions/')).map;
    return [
      for (final r in map['results'] as List)
        ReorderRow.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  // ---- suppliers -----------------------------------------------------------

  Future<SupplierPage> suppliers({
    String query = '',
    bool archived = false,
    int offset = 0,
    int limit = 50,
  }) async {
    final map = (await api.get(
      '$_base/suppliers/',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'active': archived ? '0' : '1',
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return SupplierPage([
      for (final r in map['results'] as List)
        Supplier.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<Supplier> createSupplier(Map<String, dynamic> fields) async =>
      Supplier.fromJson(
        (await api.post('$_base/suppliers/', body: fields)).map,
      );

  Future<Supplier> updateSupplier(
    String id,
    Map<String, dynamic> fields,
  ) async => Supplier.fromJson(
    (await api.patch('$_base/suppliers/$id/', body: fields)).map,
  );

  // ---- purchase orders -----------------------------------------------------

  Future<OrderPage> orders({
    List<String> statuses = const [],
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/purchase-orders/',
      query: {
        if (statuses.isNotEmpty) 'status': statuses.join(','),
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return OrderPage([
      for (final r in map['results'] as List)
        OrderSummary.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<PurchaseOrder> order(String id) async => PurchaseOrder.fromJson(
    (await api.get('$_base/purchase-orders/$id/')).map,
  );

  Map<String, dynamic> orderBody({
    required String supplierId,
    required String locationId,
    required String? expectedDate,
    required String notes,
    required List<({String productId, int quantityMilli, int costMinor})> lines,
  }) => {
    'supplier': supplierId,
    'location': locationId,
    'expected_date': expectedDate,
    'notes': notes,
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'unit_cost': toServerDecimal(l.costMinor, 2),
        },
    ],
  };

  Future<PurchaseOrder> createOrder(Map<String, dynamic> body) async =>
      PurchaseOrder.fromJson(
        (await api.post('$_base/purchase-orders/', body: body)).map,
      );

  Future<PurchaseOrder> updateOrder(
    String id,
    Map<String, dynamic> body,
  ) async => PurchaseOrder.fromJson(
    (await api.patch('$_base/purchase-orders/$id/', body: body)).map,
  );

  Future<PurchaseOrder> submit(String id) async => PurchaseOrder.fromJson(
    (await api.post('$_base/purchase-orders/$id/submit/', body: {})).map,
  );

  Future<PurchaseOrder> cancel(String id, String reason) async =>
      PurchaseOrder.fromJson(
        (await api.post(
          '$_base/purchase-orders/$id/cancel/',
          body: {'reason': reason},
        )).map,
      );
}
