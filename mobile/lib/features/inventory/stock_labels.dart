import '../../l10n/app_localizations.dart';

String conditionLabel(AppLocalizations l, String condition) =>
    switch (condition) {
      'sellable' => l.conditionSellable,
      'damaged' => l.conditionDamaged,
      'inspection' => l.conditionInspection,
      'in_transit' => l.conditionInTransit,
      _ => condition,
    };

String movementTypeLabel(AppLocalizations l, String type) => switch (type) {
  'opening' => l.movementOpening,
  'receipt' => l.movementReceipt,
  'adjustment_in' => l.movementAdjustmentIn,
  'adjustment_out' => l.movementAdjustmentOut,
  _ => l.movementOther,
};
