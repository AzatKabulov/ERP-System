import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'returns_models.dart';

/// Customer returns over the API. Making a return and deciding on goods awaiting inspection
/// change stock and money, so they are sent by the OperationRunner (see the paths and bodies).
class ReturnsRepository {
  ReturnsRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';
  String returnPath(String saleId) => '$_base/sales/$saleId/returns/';
  String inspectPath(String returnId) =>
      '$_base/returns/$returnId/inspections/';

  Map<String, dynamic> returnBody({
    required String reason,
    required String note,
    required List<({String saleLineId, int quantityMilli, String condition})>
    lines,
  }) => {
    'reason': reason,
    'note': note,
    'lines': [
      for (final l in lines)
        {
          'sale_line': l.saleLineId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'condition': l.condition,
        },
    ],
  };

  Map<String, dynamic> inspectBody(
    List<({String returnLineId, String outcome, int quantityMilli})> lines,
  ) => {
    'lines': [
      for (final l in lines)
        {
          'return_line': l.returnLineId,
          'outcome': l.outcome,
          'quantity': toServerDecimal(l.quantityMilli, 3),
        },
    ],
  };

  Future<ReturnPage> returns({
    String query = '',
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/returns/',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return ReturnPage([
      for (final r in map['results'] as List)
        ReturnSummary.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<SaleReturnDoc> returnDoc(String id) async =>
      SaleReturnDoc.fromJson((await api.get('$_base/returns/$id/')).map);
}
