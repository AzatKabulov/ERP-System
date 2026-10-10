import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'warranties_models.dart';

/// Warranty claims over the API. Closing a claim can move stock or money (a replacement, a
/// refund), so it is sent by the OperationRunner (see [closePath] and [closeBody]); opening a
/// claim and adding notes are plain requests.
class WarrantiesRepository {
  WarrantiesRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId/warranty-claims';
  String closePath(String id) => '$_base/$id/close/';

  Map<String, dynamic> closeBody({
    required String outcome,
    required String note,
  }) => {'outcome': outcome, 'note': note};

  Future<WarrantyPage> claims({
    String? status,
    String query = '',
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/',
      query: {
        'status': ?status,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return WarrantyPage([
      for (final r in map['results'] as List)
        WarrantyClaim.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<WarrantyClaim> claim(String id) async =>
      WarrantyClaim.fromJson((await api.get('$_base/$id/')).map);

  /// An expired or missing warranty is accepted only with [overrideNote] (owner or manager).
  Future<WarrantyClaim> open({
    required String saleLineId,
    required int quantityMilli,
    required String problem,
    String? overrideNote,
  }) async => WarrantyClaim.fromJson(
    (await api.post(
      '$_base/',
      body: {
        'sale_line': saleLineId,
        'quantity': toServerDecimal(quantityMilli, 3),
        'problem': problem,
        if (overrideNote != null) ...{
          'override': true,
          'override_note': overrideNote,
        },
      },
    )).map,
  );

  Future<WarrantyClaim> addNote(String id, String note) async =>
      WarrantyClaim.fromJson(
        (await api.post('$_base/$id/notes/', body: {'note': note})).map,
      );
}
