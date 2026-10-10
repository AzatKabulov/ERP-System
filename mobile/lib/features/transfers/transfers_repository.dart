import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'transfers_models.dart';

/// Transfers over the API. Dispatching, receiving and cancelling change stock, so they are
/// sent by the OperationRunner (see the paths and bodies below).
class TransfersRepository {
  TransfersRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId/transfers';
  String get dispatchPath => '$_base/';
  String receivePath(String id) => '$_base/$id/receive/';
  String cancelPath(String id) => '$_base/$id/cancel/';

  Map<String, dynamic> dispatchBody({
    required String fromId,
    required String toId,
    required String note,
    required List<({String productId, int quantityMilli})> lines,
  }) => {
    'from_location': fromId,
    'to_location': toId,
    'note': note,
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
        },
    ],
  };

  /// Every line says how much arrived; what is missing needs a [reason].
  Map<String, dynamic> receiveBody({
    required List<({String lineId, int quantityMilli})> lines,
    required String reason,
  }) => {
    'lines': [
      for (final l in lines)
        {'line': l.lineId, 'quantity': toServerDecimal(l.quantityMilli, 3)},
    ],
    'reason': reason,
  };

  Map<String, dynamic> cancelBody(String reason) => {'reason': reason};

  Future<TransferPage> transfers({
    String? status,
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/',
      query: {'status': ?status, 'limit': '$limit', 'offset': '$offset'},
    )).map;
    return TransferPage([
      for (final r in map['results'] as List)
        TransferSummary.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<Transfer> transfer(String id) async =>
      Transfer.fromJson((await api.get('$_base/$id/')).map);
}
