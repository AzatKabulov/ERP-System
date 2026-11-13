import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../core/money/decimal_math.dart';
import 'document_buttons.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

/// Receipt actions belong to the confirmed sale, never to a request still in flight.
class SaleSuccessSheet extends StatelessWidget {
  const SaleSuccessSheet({
    super.key,
    required this.sale,
    required this.repository,
  });
  final SaleDetail sale;
  final SalesRepository repository;
  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return SafeArea(
      key: const ValueKey('sale-done'),
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('sale-success-sheet'),
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: l.close,
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(AppIcons.close),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: AppMotion.reduced(context) ? 1 : 0, end: 1),
                duration: AppMotion.of(
                  context,
                  const Duration(milliseconds: 480),
                ),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: _ConfirmationPainter(
                      value,
                      AppColors.success,
                      AppColors.successTint,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                l.saleDoneTitle(saleNumber(sale.number)),
                key: const ValueKey('sale-done-number'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.saleTotal(formatMoney(sale.totalMinor, 'TMT')),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Center(
              child: DocumentButtons(
                repository: repository,
                saleId: sale.id,
                saleNumber: sale.number,
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              key: const ValueKey('sale-new'),
              label: l.newSaleAction,
              icon: AppIcons.plus,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmationPainter extends CustomPainter {
  const _ConfirmationPainter(this.progress, this.color, this.fill);
  final double progress;
  final Color color;
  final Color fill;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      Paint()..color = fill,
    );
    final path = Path()
      ..moveTo(size.width * .27, size.height * .51)
      ..lineTo(size.width * .44, size.height * .67)
      ..lineTo(size.width * .74, size.height * .34);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ConfirmationPainter old) =>
      old.progress != progress || old.color != color || old.fill != fill;
}
