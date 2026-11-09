import 'dart:async';
import 'dart:typed_data';

import 'package:erp_system/core/files/file_services.dart';
import 'package:erp_system/features/scanning/photo_scan_screen.dart';
import 'package:erp_system/l10n/app_localizations.dart';
import 'package:erp_system/l10n/turkmen_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_files.dart';
import '../support/real_rig.dart' show key, tapKey;

Future<void> openPhoto(
  WidgetTester tester,
  FakeFilePicking picker,
  Future<List<String>> Function(Uint8List) decode, {
  String locale = 'ru',
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    FilesScope(
      picking: picker,
      sharing: FakeFileSharing(),
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          TurkmenMaterialDelegate(),
          TurkmenCupertinoDelegate(),
          TurkmenWidgetsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-photo'),
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => PhotoScanScreen(decode: decode),
                  ),
                );
                if (context.mounted && code != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('result:$code')));
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tapKey(tester, 'open-photo');
  await tester.pumpAndSettle();
}

FakeFilePicking photoPicker() => FakeFilePicking(hasCamera: false)
  ..nextPhoto = PickedFile(name: 'barcode.jpg', bytes: Uint8List.fromList([1]));

void main() {
  for (final locale in ['ru', 'tk']) {
    testWidgets(
      'phone photo returns a code, even without live camera ($locale)',
      (tester) async {
        final picker = photoPicker();
        await openPhoto(
          tester,
          picker,
          (_) async => ['4006381333931'],
          locale: locale,
        );
        await tapKey(tester, 'photo-scan-camera');
        await tester.pumpAndSettle();
        expect(picker.photoRequests, ['camera']);
        expect(find.text('result:4006381333931'), findsOneWidget);
      },
    );
  }

  testWidgets('cancelled capture leaves the scanner and never decodes', (
    tester,
  ) async {
    var calls = 0;
    final picker = photoPicker()..nextPhoto = null;
    await openPhoto(tester, picker, (_) async {
      calls++;
      return [];
    });
    await tapKey(tester, 'photo-scan-camera');
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(key('photo-scan-error'), findsNothing);
    expect(key('photo-scan-camera'), findsOneWidget);
  });

  testWidgets('no result and decoder failure can be retried from the gallery', (
    tester,
  ) async {
    var calls = 0;
    await openPhoto(tester, photoPicker(), (_) async {
      calls++;
      if (calls == 1) return [];
      if (calls == 2) throw StateError('unreadable');
      return ['4006381333931'];
    });
    for (var i = 0; i < 2; i++) {
      await tapKey(tester, 'photo-scan-gallery');
      await tester.pumpAndSettle();
      expect(key('photo-scan-error'), findsOneWidget);
    }
    await tapKey(tester, 'photo-scan-gallery');
    await tester.pumpAndSettle();
    expect(find.text('result:4006381333931'), findsOneWidget);
  });

  testWidgets('several distinct codes need an explicit choice', (tester) async {
    await openPhoto(
      tester,
      photoPicker(),
      (_) async => ['4006381333931', 'OTHER-2', 'OTHER-2'],
    );
    await tapKey(tester, 'photo-scan-camera');
    await tester.pumpAndSettle();
    expect(find.text('OTHER-2'), findsOneWidget);
    expect(find.textContaining('result:'), findsNothing);
    await tester.tap(find.text('OTHER-2'));
    await tester.pumpAndSettle();
    expect(find.text('result:OTHER-2'), findsOneWidget);
  });

  testWidgets(
    'pending recognition prevents duplicates and ignores a closed route',
    (tester) async {
      final pending = Completer<List<String>>();
      var calls = 0;
      await openPhoto(tester, photoPicker(), (_) {
        calls++;
        return pending.future;
      });
      await tapKey(tester, 'photo-scan-camera');
      await tester.pump();
      await tapKey(tester, 'photo-scan-camera');
      expect(calls, 1);
      await tapKey(tester, 'photo-scan-manual');
      await tester.pumpAndSettle();
      pending.complete(['4006381333931']);
      await tester.pumpAndSettle();
      expect(find.textContaining('result:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('oversized images are rejected before decoder allocation', (
    tester,
  ) async {
    var calls = 0;
    final picker = photoPicker()
      ..nextPhoto = PickedFile(
        name: 'huge.jpg',
        bytes: Uint8List(12 * 1024 * 1024 + 1),
      );
    await openPhoto(tester, picker, (_) async {
      calls++;
      return [];
    });
    await tapKey(tester, 'photo-scan-gallery');
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(key('photo-scan-error'), findsOneWidget);
  });
}
