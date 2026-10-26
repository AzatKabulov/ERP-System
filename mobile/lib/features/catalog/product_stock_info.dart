import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../inventory/quantity_input.dart';
import 'catalog_models.dart';

/// Stock belongs to the caller's permitted locations. A batch date applies only
/// to the displayed batch quantity, never to all units of the product.
class ProductStockInfo extends StatelessWidget {
  const ProductStockInfo({
    super.key,
    required this.product,
    this.showQuantity = true,
  });
  final Product product;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final p = product;
    final day = p.expiryDate?.split('-').reversed.join('.');
    final qty = quantityWithUnit(p.expiryQuantityMilli ?? 0, p.unit);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showQuantity && p.onHandMilli != null)
          Text(
            l.productStockQuantity(quantityWithUnit(p.onHandMilli!, p.unit)),
            key: ValueKey('product-stock-${p.id}'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        if (day != null)
          Text(
            p.expiryStatus == 'expired'
                ? l.expiredBatch(day, qty)
                : l.expiryBatch(day, qty),
            key: ValueKey('product-expiry-${p.id}'),
            style: TextStyle(
              fontSize: 12,
              color: switch (p.expiryStatus) {
                'expired' => AppColors.danger,
                'soon' => AppColors.warning,
                _ => AppColors.muted,
              },
            ),
          ),
      ],
    );
  }
}
