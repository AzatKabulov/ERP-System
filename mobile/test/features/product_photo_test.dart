import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_system/core/files/file_services.dart';
import 'package:erp_system/core/files/photo_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_files.dart';
import '../support/fake_scanner.dart';
import '../support/real_rig.dart';
import 'catalog_test.dart' show seedProduct;
import 'intake_test.dart' show openIntake, scanByKeyboard;

/// A real 1x1 picture, so the image decoder is satisfied.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

PickedFile photoFile([String name = 'cream.jpg']) =>
    PickedFile(name: name, bytes: tinyPng);

Finder get shownPicture => find.byKey(const ValueKey('product-photo-image'));

/// Gives the product a picture on the server, as if somebody had added it earlier.
void hasPicture(RealRig rig, Map<String, dynamic> product) {
  rig.server.photosData['${product['id']}'] = (
    version: 'v-seed',
    bytes: tinyPng,
  );
}

Future<void> openProduct(WidgetTester tester, RealRig rig, String sku) async {
  await rig.launchSignedIn(tester);
  await tapKey(tester, 'nav-products');
  await settle(tester);
  await tapKey(tester, 'product-$sku');
  await settle(tester);
}

void main() {
  setUp(() => PhotoCache.instance.clear());

  group('pictures in the catalog', () {
    testWidgets(
      'the gallery shows a product\'s picture, and a plain tile when it has none',
      (tester) async {
        final rig = RealRig();
        final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
        seedProduct(rig.server, sku: 'SP-1', name: 'Мыло');
        hasPicture(rig, cream);
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'nav-products');
        await settle(tester);
        expect(shownPicture, findsOneWidget);
        expect(
          find.descendant(of: key('product-CR-1'), matching: shownPicture),
          findsOneWidget,
        );
        expect(
          find.descendant(of: key('product-SP-1'), matching: shownPicture),
          findsNothing,
        );
        expect(rig.server.photoDownloads, ['${cream['id']}:thumb']);
      },
    );

    testWidgets(
      'the list shows the picture too, without asking the server again',
      (tester) async {
        final rig = RealRig();
        final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
        hasPicture(rig, cream);
        await rig.launchSignedIn(tester);
        await tapKey(tester, 'nav-products');
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: key('catalog-view-toggle'),
            matching: find.text('Список'),
          ),
        );
        await settle(tester);
        expect(
          find.descendant(of: key('product-CR-1'), matching: shownPicture),
          findsOneWidget,
        );
        expect(rig.server.photoDownloads.length, 1, reason: 'kept in memory');
      },
    );

    testWidgets('a picture that cannot be downloaded leaves the plain tile', (
      tester,
    ) async {
      final rig = RealRig();
      final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      hasPicture(rig, cream);
      rig.server.photosData.remove(
        '${cream['id']}',
      ); // gone between list and download
      // the product still says it has one
      rig.server.productsData.first['photo'] = {'version': 'v-ghost'};
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-products');
      await settle(tester);
      expect(shownPicture, findsNothing);
      expect(tester.takeException(), isNull);
      expect(key('product-CR-1'), findsOneWidget);
    });

    testWidgets('the sales search shows the picture next to the name', (
      tester,
    ) async {
      final rig = RealRig();
      final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      hasPicture(rig, cream);
      await rig.launchSignedIn(tester);
      await tapKey(tester, 'nav-sales');
      await settle(tester);
      await tester.enterText(key('sales-search'), 'Крем');
      await settle(tester, ms: 700);
      expect(
        find.descendant(of: key('sell-CR-1'), matching: shownPicture),
        findsOneWidget,
      );
    });
  });

  group('the product page', () {
    testWidgets('a worker takes a picture with the camera and it appears', (
      tester,
    ) async {
      final rig = RealRig();
      final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      rig.picking.nextPhoto = photoFile();
      await openProduct(tester, rig, 'CR-1');
      expect(key('pd-photo-none'), findsOneWidget);
      expect(shownPicture, findsNothing);
      await tapKey(tester, 'pd-photo-take');
      await settle(tester);
      expect(rig.picking.photoRequests, ['camera']);
      expect(rig.server.photoUploads, 1);
      expect(rig.server.photosData['${cream['id']}']!.bytes, tinyPng);
      expect(shownPicture, findsOneWidget);
      expect(key('pd-photo-none'), findsNothing);
      expect(find.text('Фото сохранено.'), findsOneWidget);
    });

    testWidgets('choosing from the gallery, and replacing it later', (
      tester,
    ) async {
      final rig = RealRig();
      final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      rig.picking.nextPhoto = photoFile();
      await openProduct(tester, rig, 'CR-1');
      await tapKey(tester, 'pd-photo-choose');
      await settle(tester);
      expect(rig.picking.photoRequests, ['gallery']);
      expect(find.text('Заменить фото'), findsOneWidget);
      final first = rig.server.photosData['${cream['id']}']!.version;
      await tapKey(tester, 'pd-photo-choose');
      await settle(tester);
      expect(rig.server.photoUploads, 2);
      expect(rig.server.photosData['${cream['id']}']!.version, isNot(first));
      expect(shownPicture, findsOneWidget);
    });

    testWidgets('the picture is removed after a confirmation', (tester) async {
      final rig = RealRig();
      final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      hasPicture(rig, cream);
      await openProduct(tester, rig, 'CR-1');
      expect(shownPicture, findsOneWidget);
      await tapKey(tester, 'pd-photo-remove');
      await settle(tester, ms: 400);
      expect(find.text('Удалить фото этого товара?'), findsOneWidget);
      await tester.tap(find.text('Подтвердить'));
      await settle(tester);
      expect(rig.server.photosData, isEmpty);
      expect(shownPicture, findsNothing);
      expect(key('pd-photo-none'), findsOneWidget);
    });

    testWidgets('cancelling the camera changes nothing', (tester) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      await openProduct(tester, rig, 'CR-1');
      await tapKey(
        tester,
        'pd-photo-take',
      ); // nextPhoto is null: the person cancelled
      await settle(tester);
      expect(rig.server.photoUploads, 0);
      expect(key('pd-photo-error'), findsNothing);
    });

    testWidgets('a browser has no camera: only choosing a file is offered', (
      tester,
    ) async {
      final rig = RealRig(picking: FakeFilePicking(hasCamera: false));
      seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      rig.picking.nextPhoto = photoFile();
      await openProduct(tester, rig, 'CR-1');
      expect(key('pd-photo-take'), findsNothing);
      await tapKey(tester, 'pd-photo-choose');
      await settle(tester);
      expect(rig.picking.photoRequests, ['gallery']);
      expect(rig.server.photoUploads, 1);
    });

    testWidgets(
      'a file the server cannot use is explained and nothing changes',
      (tester) async {
        final rig = RealRig();
        seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
        rig.picking.nextPhoto = photoFile('notes.jpg');
        rig.server.photoFails = 'invalid_image';
        await openProduct(tester, rig, 'CR-1');
        await tapKey(tester, 'pd-photo-choose');
        await settle(tester);
        expect(key('pd-photo-error'), findsOneWidget);
        expect(find.textContaining('Это не картинка'), findsOneWidget);
        expect(shownPicture, findsNothing);
      },
    );

    testWidgets(
      'a person who may not add pictures sees the picture but no buttons',
      (tester) async {
        final rig = RealRig();
        final cream = seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
        hasPicture(rig, cream);
        rig.server.role = 'sales';
        rig.server.permissions = ['catalog.view', 'dashboard.view'];
        await openProduct(tester, rig, 'CR-1');
        expect(shownPicture, findsOneWidget);
        for (final name in [
          'pd-photo-take',
          'pd-photo-choose',
          'pd-photo-remove',
          'pd-photo-none',
        ]) {
          expect(key(name), findsNothing, reason: name);
        }
      },
    );

    testWidgets('the catalog shows the new picture after coming back', (
      tester,
    ) async {
      final rig = RealRig();
      seedProduct(rig.server, sku: 'CR-1', name: 'Крем');
      rig.picking.nextPhoto = photoFile();
      await openProduct(tester, rig, 'CR-1');
      await tapKey(tester, 'pd-photo-choose');
      await settle(tester);
      await goBack(tester);
      expect(
        find.descendant(of: key('product-CR-1'), matching: shownPicture),
        findsOneWidget,
      );
    });

    for (final size in [const Size(360, 800), const Size(800, 1100)]) {
      testWidgets(
        'the page fits $size with a picture, a long name and doubled text',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final rig = RealRig();
          final cream = seedProduct(
            rig.server,
            sku: 'LONG-ARTICLE-1',
            name: 'Очень длинное название товара для проверки переноса строк',
          );
          hasPicture(rig, cream);
          await rig.launch(tester, size: size);
          await rig.signIn(tester);
          if (size.width < 600) {
            await tester.tap(find.byTooltip('Меню'));
            await settle(tester, ms: 400);
            await tester.scrollUntilVisible(
              key('nav-products'),
              200,
              scrollable: find.descendant(
                of: find.byType(Drawer),
                matching: find.byType(Scrollable),
              ),
            );
          }
          await tapKey(tester, 'nav-products');
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'gallery');
          await tester.scrollUntilVisible(
            key('product-LONG-ARTICLE-1'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tapKey(tester, 'product-LONG-ARTICLE-1');
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'page');
          expect(shownPicture, findsOneWidget);
        },
      );
    }
  });

  group('adding a product while receiving goods', () {
    testWidgets('a worker can take its picture in the same form', (
      tester,
    ) async {
      final scanner = FakeScanner();
      final rig = RealRig(scanner: scanner);
      rig.picking.nextPhoto = photoFile();
      await openIntake(tester, rig);
      await scanByKeyboard(tester, 'MH044089');
      await tapKey(tester, 'intake-add-MH044089');
      await settle(tester, ms: 600);
      await tester.enterText(key('intake-new-name'), 'Подшипник КПП');
      await tapKey(tester, 'intake-new-photo');
      await settle(tester, ms: 400);
      expect(key('intake-new-photo-preview'), findsOneWidget);
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      final created = rig.server.productsData.last;
      expect(created['name'], 'Подшипник КПП');
      expect(rig.server.photosData['${created['id']}']!.bytes, tinyPng);
    });

    testWidgets('without a picture the form works as before', (tester) async {
      final rig = RealRig(scanner: FakeScanner());
      await openIntake(tester, rig);
      await scanByKeyboard(tester, 'MH044089');
      await tapKey(tester, 'intake-add-MH044089');
      await settle(tester, ms: 600);
      await tester.enterText(key('intake-new-name'), 'Подшипник КПП');
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(rig.server.productsData.last['name'], 'Подшипник КПП');
      expect(rig.server.photoUploads, 0);
    });

    testWidgets('a picture the server refuses does not undo the product', (
      tester,
    ) async {
      final rig = RealRig(scanner: FakeScanner());
      rig.picking.nextPhoto = photoFile();
      rig.server.photoFails = 'invalid_image';
      await openIntake(tester, rig);
      await scanByKeyboard(tester, 'MH044089');
      await tapKey(tester, 'intake-add-MH044089');
      await settle(tester, ms: 600);
      await tester.enterText(key('intake-new-name'), 'Подшипник КПП');
      await tapKey(tester, 'intake-new-photo');
      await settle(tester, ms: 400);
      await tapKey(tester, 'intake-new-save');
      await settle(tester);
      expect(rig.server.productsData.last['name'], 'Подшипник КПП');
      expect(
        find.text('Подшипник КПП'),
        findsOneWidget,
      ); // the line is tied to it
    });
  });

  group('the picture cache', () {
    test(
      'several askers share one download, and a failure is forgotten',
      () async {
        final cache = PhotoCache.instance..clear();
        var calls = 0;
        Future<Uint8List?> fetch() async {
          calls++;
          return Uint8List.fromList([1, 2, 3]);
        }

        final a = cache.load('k', fetch);
        final b = cache.load('k', fetch);
        expect(await a, [1, 2, 3]);
        expect(await b, [1, 2, 3]);
        expect(calls, 1);

        var failures = 0;
        Future<Uint8List?> broken() async {
          failures++;
          throw Exception('offline');
        }

        expect(await cache.load('bad', broken), isNull);
        expect(await cache.load('bad', broken), isNull);
        expect(failures, 2, reason: 'a failed download is tried again');
      },
    );

    test('the oldest pictures are dropped past a limit', () async {
      final cache = PhotoCache.instance..clear();
      var calls = 0;
      Future<Uint8List?> fetch() async {
        calls++;
        return Uint8List(1);
      }

      for (var i = 0; i < 450; i++) {
        await cache.load('k$i', fetch);
      }
      expect(calls, 450);
      await cache.load('k449', fetch); // recent: kept
      expect(calls, 450);
      await cache.load('k0', fetch); // oldest: dropped, fetched again
      expect(calls, 451);
    });

    test('clearing forgets everything', () async {
      final cache = PhotoCache.instance..clear();
      var calls = 0;
      Future<Uint8List?> fetch() async {
        calls++;
        return Uint8List(1);
      }

      await cache.load('x', fetch);
      cache.clear();
      await cache.load('x', fetch);
      expect(calls, 2);
    });
  });
}
