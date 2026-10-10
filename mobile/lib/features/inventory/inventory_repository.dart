import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import 'inventory_models.dart';

/// Stock reads, and the request bodies for the two stock-changing commands. The
/// commands themselves are sent by the [OperationRunner], which keeps their
/// operation key across timeouts and restarts.
class InventoryRepository {
  InventoryRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId/stock';

  String get openingPath => '$_base/opening/';
  String get adjustmentPath => '$_base/adjustments/';

  Future<StockPage> stock({
    String query = '',
    String? locationId,
    String? productId,
    bool includeZero = false,
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'location': ?locationId,
        'product': ?productId,
        if (includeZero) 'include_zero': '1',
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return StockPage([
      for (final r in map['results'] as List)
        StockRow.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  Future<MovementPage> movements({
    String? productId,
    String? locationId,
    int offset = 0,
    int limit = 30,
  }) async {
    final map = (await api.get(
      '$_base/movements/',
      query: {
        'product': ?productId,
        'location': ?locationId,
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return MovementPage([
      for (final r in map['results'] as List)
        MovementRow.fromJson((r as Map).cast<String, dynamic>()),
    ], map['count'] as int);
  }

  /// Quantities and costs are sent as exact decimal text, never as numbers.
  Map<String, dynamic> openingBody({
    required String locationId,
    required List<({String productId, int quantityMilli, int costMinor})> lines,
    String note = '',
  }) => {
    'location': locationId,
    'note': note,
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'quantity': toServerDecimal(l.quantityMilli, 3),
          'unit_cost': toServerDecimal(l.costMinor, 2),
        },
    ],
  };

  Map<String, dynamic> adjustmentBody({
    required String locationId,
    required String reason,
    required List<
      ({
        String productId,
        bool incoming,
        int quantityMilli,
        int? costMinor,
        String condition,
      })
    >
    lines,
  }) => {
    'location': locationId,
    'reason': reason,
    'lines': [
      for (final l in lines)
        {
          'product': l.productId,
          'direction': l.incoming ? 'in' : 'out',
          'quantity': toServerDecimal(l.quantityMilli, 3),
          if (l.incoming && l.costMinor != null)
            'unit_cost': toServerDecimal(l.costMinor!, 2),
          'condition': l.condition,
        },
    ],
  };
}
