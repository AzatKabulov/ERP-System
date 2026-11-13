import 'dart:ui' as ui;
import 'package:erp_system/theme/app_palette.dart';
import 'package:erp_system/theme/app_theme.dart';
import 'package:erp_system/widgets/app_route.dart';
import 'package:erp_system/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppColors.use(AppPalette.light));
  for (final dark in [false, true]) {
    testWidgets('ambient canvas survives push and pop frames, dark=$dark', (
      tester,
    ) async {
      AppColors.use(dark ? AppPalette.dark : AppPalette.light);
      final capture = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            navigatorKey: nav,
            theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
              platform: TargetPlatform.android,
            ),
            builder: (_, child) => Stack(
              fit: StackFit.expand,
              children: [const AmbientField(), child!],
            ),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixel() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (100 * image.width + 40) * 4;
        final rgb = List.generate(3, (i) => bytes.getUint8(offset + i));
        image.dispose();
        return rgb;
      }

      final baseline = (await tester.runAsync(pixel))!;
      nav.currentState!.push(appRoute<void>(builder: (_) => const Scaffold()));
      await tester.pump();
      for (final ms in [40, 60, 80, 100, 120]) {
        await tester.pump(Duration(milliseconds: ms));
        final frame = (await tester.runAsync(pixel))!;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (frame[channel] - baseline[channel]).abs(),
            lessThanOrEqualTo(8),
            reason: 'push: $frame vs $baseline',
          );
        }
      }
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pump();
      for (final ms in [40, 80, 120, 160]) {
        await tester.pump(Duration(milliseconds: ms));
        final frame = (await tester.runAsync(pixel))!;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (frame[channel] - baseline[channel]).abs(),
            lessThanOrEqualTo(8),
            reason: 'pop: $frame vs $baseline',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
