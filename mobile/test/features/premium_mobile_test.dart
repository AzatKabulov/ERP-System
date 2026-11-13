import 'package:erp_system/theme/app_theme.dart';
import 'package:erp_system/theme/app_palette.dart';
import 'package:erp_system/widgets/app_icons.dart';
import 'package:erp_system/widgets/bottom_navigation.dart';
import 'package:erp_system/widgets/common.dart';
import 'package:erp_system/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/real_rig.dart';
import 'sales_test.dart' show deskRig, openSales, addToCart, checkout, confirm;
import 'product_photo_test.dart' show hasPicture, openProduct;
import 'catalog_test.dart' show seedProduct;

void main() {
  testWidgets('strong overlays paint an opaque surface without backdrop blur', (
    tester,
  ) async {
    final previous = AppColors.palette;
    addTearDown(() => AppColors.use(previous));
    for (final palette in [AppPalette.light, AppPalette.dark]) {
      AppColors.use(palette);
      final theme = palette == AppPalette.dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: GlassSurface(strong: true, child: Text('Overlay')),
          ),
        ),
      );
      final decorations = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        decorations.any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color?.a == 1,
        ),
        isTrue,
      );
      expect(find.byType(BackdropFilter), findsNothing);
    }
  });

  testWidgets(
    'bottom navigation selects on drag release, has an opaque surface and no splash',
    (tester) async {
      var selected = 0;
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 350,
                child: StatefulBuilder(
                  builder: (context, setState) => SlidingBottomNavigation(
                    selected: selected,
                    tabs: [
                      for (var i = 0; i < 5; i++)
                        BottomTab(
                          key: ValueKey('test-tab-$i'),
                          label: '$i',
                          icon: AppIcons.box,
                        ),
                    ],
                    onSelected: (i) => setState(() {
                      selected = i;
                      selections++;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('test-tab-0')));
      expect(selections, 0);
      final start = tester.getCenter(find.byKey(const ValueKey('test-tab-0')));
      final end = tester.getCenter(find.byKey(const ValueKey('test-tab-3')));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await tester.pump();
      expect(selections, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(selections, 1);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('test-tab-3')))
            .splashFactory,
        NoSplash.splashFactory,
      );
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(SlidingBottomNavigation),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        boxes.any(
          (b) => (b.decoration as BoxDecoration).color == AppColors.surface,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'monthly metric heights also match with very different amount lengths',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: AdaptiveGrid(
                minimumWidth: 150,
                maxColumns: 2,
                children: const [
                  MetricCard(
                    key: ValueKey('long-metric'),
                    alignWithPeers: true,
                    label: 'Продажи за месяц (390)',
                    value: '12 345 678,90 TMT',
                    icon: AppIcons.sale,
                  ),
                  MetricCard(
                    key: ValueKey('short-metric'),
                    alignWithPeers: true,
                    label: 'Валовая прибыль за месяц',
                    value: '50,00 TMT',
                    meta: '30,7%',
                    icon: AppIcons.trendUp,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(key('long-metric')).height,
        tester.getSize(key('short-metric')).height,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone overview metric boxes align and shop header is moved into More',
    (tester) async {
      final rig = RealRig();
      await rig.launch(tester, size: const Size(393, 850));
      await rig.signIn(tester);
      expect(
        tester.getSize(key('dash-sales-month')).height,
        tester.getSize(key('dash-profit-month')).height,
      );
      expect(find.textContaining('Здравствуйте'), findsNothing);
      expect(key('help-button'), findsNothing);
      await tapKey(tester, 'tab-more');
      await settle(tester);
      expect(key('more-help'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cart quantity is vertically centred and total cannot wrap', (
    tester,
  ) async {
    final t = deskRig();
    await t.rig.launch(tester, size: const Size(360, 800));
    await t.rig.signIn(tester);
    await tapKey(tester, 'tab-sales');
    await settle(tester);
    await addToCart(tester);
    await tester.enterText(key('cart-qty-0'), '2');
    await tester.pump();
    final field = tester.widget<TextField>(key('cart-qty-0'));
    expect(field.textAlignVertical, TextAlignVertical.center);
    final editable = find.descendant(
      of: key('cart-qty-0'),
      matching: find.byType(EditableText),
    );
    RenderEditable? textBox;
    void visit(RenderObject object) {
      if (object is RenderEditable) {
        textBox = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(tester.renderObject(editable));
    expect(textBox, isNotNull);
    final box = textBox!;
    expect(
      (box.localToGlobal(box.size.center(Offset.zero)).dy -
              tester.getCenter(key('cart-qty-0')).dy)
          .abs(),
      lessThan(2),
    );
    expect(tester.widget<Text>(key('cart-total')).maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed sale opens receipt sheet and emits confirmation once',
    (tester) async {
      var sounds = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('erp/confirmation'),
        (call) async {
          if (call.method == 'success') sounds++;
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('erp/confirmation'),
          null,
        ),
      );
      final t = deskRig();
      await openSales(tester, t.rig);
      await addToCart(tester);
      expect(sounds, 0);
      await checkout(tester);
      expect(sounds, 0);
      await confirm(tester);
      expect(key('sale-success-sheet'), findsOneWidget);
      expect(key('doc-receipt-print'), findsOneWidget);
      expect(key('doc-receipt-share'), findsOneWidget);
      expect(sounds, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(sounds, 1);
      await tapKey(tester, 'sale-new');
      await settle(tester);
      expect(key('sale-success-sheet'), findsNothing);
      expect(key('sale-done'), findsNothing);
    },
  );

  testWidgets('unknown sale never emits a success sound or success sheet', (
    tester,
  ) async {
    var sounds = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('erp/confirmation'),
      (call) async {
        sounds++;
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('erp/confirmation'),
        null,
      ),
    );
    final t = deskRig();
    await openSales(tester, t.rig);
    await addToCart(tester);
    await checkout(tester);
    t.rig.server.dropResponseAfterCommit = 1;
    await confirm(tester);
    expect(sounds, 0);
    expect(key('sale-success-sheet'), findsNothing);
    expect(key('pending-banner'), findsOneWidget);
  });

  for (final locale in ['ru', 'tk']) {
    testWidgets(
      'phone photo actions share a row and delete sits below in $locale',
      (tester) async {
        final rig = RealRig();
        (rig.server.me['user'] as Map)['preferred_language'] = locale;
        final product = seedProduct(
          rig.server,
          sku: 'PHOTO-ROW',
          name: 'Filter',
        );
        hasPicture(rig, product);
        await rig.launch(
          tester,
          size: const Size(390, 844),
          prefsValues: {'language': locale},
        );
        await rig.signIn(tester);
        await tapKey(tester, 'tab-products');
        await settle(tester);
        await tapKey(tester, 'product-PHOTO-ROW');
        await settle(tester);
        expect(
          tester.getTopLeft(key('pd-photo-take')).dy,
          tester.getTopLeft(key('pd-photo-choose')).dy,
        );
        expect(
          tester.getTopLeft(key('pd-photo-remove')).dy,
          greaterThan(tester.getBottomLeft(key('pd-photo-take')).dy),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'customer form fits a short phone viewport and keeps optional surname in $locale',
      (tester) async {
        final t = deskRig();
        (t.rig.server.me['user'] as Map)['preferred_language'] = locale;
        await t.rig.launch(
          tester,
          size: const Size(390, 620),
          prefsValues: {'language': locale},
        );
        await t.rig.signIn(tester);
        await tapKey(tester, 'tab-sales');
        await settle(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'cash desk before picker',
        );
        await tapKey(tester, 'cart-customer');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'picker list');
        await tapKey(tester, 'customer-new');
        await tester.enterText(key('customer-name'), 'Aýgül');
        await tester.enterText(key('customer-phone'), '+993 65 123456');
        await tapKey(tester, 'customer-save');
        await settle(tester);
        expect(t.rig.server.ledger.customers.single['name'], 'Aýgül');
        expect(t.rig.server.ledger.customers.single['phone'], '+993 65 123456');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('product photo opens a zoomable authenticated viewer', (
    tester,
  ) async {
    final rig = RealRig();
    final product = seedProduct(rig.server, sku: 'ZOOM-1', name: 'Filter');
    hasPicture(rig, product);
    await openProduct(tester, rig, 'ZOOM-1');
    await tapKey(tester, 'pd-photo-open');
    await settle(tester);
    expect(key('photo-viewer'), findsOneWidget);
    expect(tester.widget<InteractiveViewer>(key('photo-viewer')).maxScale, 4);
    await tapKey(tester, 'photo-viewer-close');
    await settle(tester);
    expect(key('photo-viewer'), findsNothing);
  });
}
