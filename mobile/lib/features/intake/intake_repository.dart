import '../../core/money/decimal_math.dart';
import 'intake_models.dart';

/// Receiving goods by scanning, over the API. Posting the counted list changes stock, so it is
/// sent by the OperationRunner (see the path and body below).
class IntakeRepository {
  const IntakeRepository(this.businessId);

  final String businessId;

  String get path => '/api/v1/businesses/$businessId/intakes/';

  /// Costs are only sent when [withCost] (the role may enter them) and a cost was typed.
  Map<String, dynamic> body({
    required String locationId,
    required String note,
    required List<IntakeEntry> entries,
    required bool withCost,
  }) => {
    'location': locationId,
    'note': note,
    'lines': [
      for (final e in entries)
        {
          'product': e.product!.id,
          'quantity': toServerDecimal(e.quantityMilli, 3),
          if (withCost && e.costMinor != null)
            'unit_cost': toServerDecimal(e.costMinor!, 2),
        },
    ],
  };
}
