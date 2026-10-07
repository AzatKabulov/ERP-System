import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'counts_models.dart';

/// Stock counts over the API. Only approving a count changes stock, so only that is sent by
/// the OperationRunner; entering, submitting and cancelling are plain requests.
class CountsRepository {
  CountsRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId/counts';
  String approvePath(String id) => '$_base/$id/approve/';

  Map<String, dynamic> approveBody(String reason) => {'reason': reason};

  Future<CountPage> counts({
    String? status,
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/',
      query: {'status': ?status, 'limit': '$limit', 'offset': '$offset'},
    )).map;
    return CountPage([
      for (final r in map['results'] as List)
        CountSummary.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<StockCountDoc> count(String id) async =>
      StockCountDoc.fromJson((await api.get('$_base/$id/')).map);

  Future<StockCountDoc> start({
    required String locationId,
    required String scope,
    List<String> productIds = const [],
  }) async => StockCountDoc.fromJson(
    (await api.post(
      '$_base/',
      body: {
        'location': locationId,
        'scope': scope,
        if (scope == 'partial') 'products': productIds,
      },
    )).map,
  );

  /// Saves counted quantities: product id -> quantity in thousandths.
  Future<StockCountDoc> enter(String id, Map<String, int> counted) async =>
      StockCountDoc.fromJson(
        (await api.send(
          'PUT',
          '$_base/$id/lines/',
          body: {
            'lines': [
              for (final e in counted.entries)
                {
                  'product': e.key,
                  'counted_quantity': toServerDecimal(e.value, 3),
                },
            ],
          },
        )).map,
      );

  Future<StockCountDoc> submit(String id) async => StockCountDoc.fromJson(
    (await api.post('$_base/$id/submit/', body: {})).map,
  );

  Future<StockCountDoc> cancel(String id, String reason) async =>
      StockCountDoc.fromJson(
        (await api.post('$_base/$id/cancel/', body: {'reason': reason})).map,
      );
}
