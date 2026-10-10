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
  'sale' => l.movementSale,
  'transfer_out' => l.movementTransferOut,
  'transfer_in' => l.movementTransferIn,
  'transfer_loss' => l.movementTransferLoss,
  'return_in' => l.movementReturnIn,
  'inspection_out' => l.movementInspectionOut,
  'inspection_in' => l.movementInspectionIn,
  'supplier_return' => l.movementSupplierReturn,
  'warranty_out' => l.movementWarrantyOut,
  'warranty_in' => l.movementWarrantyIn,
  'intake' => l.movementIntake,
  _ => l.movementOther,
};
