import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show SemanticsRole;

import 'package:erp_system/core/files/photo_cache.dart';
import 'package:erp_system/features/shared/async_section.dart';
import 'package:erp_system/features/shared/loading_skeletons.dart';
import 'package:erp_system/l10n/app_localizations.dart';
import 'package:erp_system/l10n/turkmen_localizations.dart';
import 'package:erp_system/theme/app_palette.dart';
import 'package:erp_system/theme/app_theme.dart';
import 'package:erp_system/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  bool reduced = true,
  bool dark = false,
  String language = 'ru',
}) {
  AppColors.use(dark ? AppPalette.dark : AppPalette.light);
  return MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    locale: Locale(language),
    localizationsDelegates: const [
      TurkmenMaterialDelegate(),
      TurkmenCupertinoDelegate(),
      TurkmenWidgetsDelegate(),
      ...AppLocalizations.localizationsDelegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  tearDown(() => AppColors.use(AppPalette.light));

  for (final language in ['ru', 'tk']) {
    testWidgets(
      'one localized status hides nested decorative bones ($language)',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          host(
            const SkeletonRegion(
              child: Column(
                children: [
                  SkeletonCard(avatar: true),
                  SkeletonRegion(child: Text('decorative, never announced')),
                ],
              ),
            ),
            language: language,
          ),
        );
        await tester.pump();
        final context = tester.element(find.byType(SkeletonRegion).first);
        final label = AppLocalizations.of(context).loading;
        expect(find.bySemanticsLabel(label), findsOneWidget);
        expect(
          find.bySemanticsLabel('decorative, never announced'),
          findsNothing,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .role,
          SemanticsRole.status,
        );
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'pulse repaints without rebuilding content and stops for reduced motion',
    (tester) async {
      var builds = 0;
      Widget content(bool reduced) => host(
        SkeletonRegion(
          child: Builder(
            builder: (_) {
              builds++;
              return const SkeletonCard(avatar: true);
            },
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(content(false));
      await tester.pump();
      final before = builds;
      expect(tester.hasRunningAnimations, isTrue);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, before);
      await tester.pumpWidget(content(true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 800.0, 1280.0, 1920.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'all page profiles fit ${width.toInt()}px, dark=$dark, scaled text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final compact = width < 600;
          await tester.pumpWidget(
            host(
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 1000),
                      textScaler: const TextScaler.linear(1.6),
                      disableAnimations: true,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DashboardLoadingSkeleton(
                          compact: compact,
                          metrics: 6,
                          activity: true,
                        ),
                        CatalogLoadingSkeleton(gallery: true, compact: compact),
                        CatalogLoadingSkeleton(
                          gallery: false,
                          compact: compact,
                        ),
                        StockLoadingSkeleton(compact: compact, withValue: true),
                        const FormLoadingSkeleton(columns: 2),
                        const ProductFormLoadingSkeleton(canSeeCost: true),
                        const DetailLoadingSkeleton(),
                        const ReportLoadingSkeleton(metrics: 9, chart: true),
                        const PlatformOverviewLoadingSkeleton(),
                        const PageLoadingSkeleton(),
                      ],
                    ),
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final viewport = Rect.fromLTWH(0, 0, width, 1000);
          for (final element in find.byType(SkeletonBase).evaluate()) {
            final rect = tester.getRect(
              find.byElementPredicate((e) => identical(e, element)),
            );
            expect(rect.left, greaterThanOrEqualTo(viewport.left));
            expect(rect.right, lessThanOrEqualTo(viewport.right));
          }
        },
      );
    }
  }

  testWidgets('gallery uses the actual 186px column rule', (tester) async {
    for (final width in [350.0, 740.0, 1240.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(
        host(CatalogLoadingSkeleton(gallery: true, compact: width < 600)),
      );
      await tester.pump();
      final columns = ((width + 16) / 186).floor().clamp(2, 5);
      expect(find.byType(SkeletonCard), findsNWidgets(columns * 2));
      final first = tester.getRect(find.byType(SkeletonCard).first);
      expect(first.width, closeTo((width - (columns - 1) * 16) / columns, .01));
      expect(tester.takeException(), isNull);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('reference placeholders support intrinsic dialog layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const AlertDialog(
          content: SizedBox(
            width: 420,
            child: SkeletonForm(fields: 1, actions: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded picker skeleton scrolls instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Center(
          child: SizedBox(
            width: 300,
            height: 100,
            child: SkeletonList(rows: 6, avatar: true, inCard: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('read, empty, failure, retry and refresh retain draft state', (
    tester,
  ) async {
    final key = GlobalKey<AsyncSectionState<List<int>>>();
    var pending = Completer<List<int>>();
    var loads = 0;
    Widget section() => host(
      SingleChildScrollView(
        child: AsyncSection<List<int>>(
          key: key,
          load: () {
            loads++;
            return pending.future;
          },
          loadingBuilder: (_) => const RecordListSkeleton(),
          builder: (_, data) => Column(
            children: [
              Text('rows: ${data.length}'),
              const TextField(key: ValueKey('draft')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(section());
    await tester.pump();
    expect(find.byType(RecordListSkeleton), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(RecordListSkeleton), findsOneWidget);
    expect(loads, 1);
    pending.complete([]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(RecordListSkeleton), findsNothing);
    expect(find.text('rows: 0'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('draft')), 'unsaved work');
    final state = tester.state(find.byKey(const ValueKey('draft')));
    pending = Completer<List<int>>();
    key.currentState!.reload();
    await tester.pump();
    expect(find.text('unsaved work'), findsOneWidget);
    expect(tester.state(find.byKey(const ValueKey('draft'))), same(state));
    expect(find.byType(RecordListSkeleton), findsNothing);
    pending.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.text('unsaved work'), findsOneWidget);
    expect(tester.state(find.byKey(const ValueKey('draft'))), same(state));
    pending = Completer<List<int>>();
    await tester.tap(find.byKey(const ValueKey('retry-load')));
    await tester.pump();
    pending.complete([1, 2]);
    await tester.pump();
    await tester.pump();
    expect(find.text('rows: 2'), findsOneWidget);
    expect(find.text('unsaved work'), findsOneWidget);
    expect(find.byType(ErrorPanel), findsNothing);
    expect(loads, 3);
    await tester.pumpWidget(section());
    await tester.pump();
    expect(loads, 3, reason: 'ordinary parent builds must not refetch');
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial failure ends skeleton, retry starts a real new read', (
    tester,
  ) async {
    var pending = Completer<String?>();
    await tester.pumpWidget(
      host(
        AsyncSection<String?>(
          load: () => pending.future,
          loadingBuilder: (_) => const RecordListSkeleton(),
          builder: (_, data) => Text(data ?? 'empty'),
        ),
      ),
    );
    await tester.pump();
    pending.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(RecordListSkeleton), findsNothing);
    expect(find.byType(ErrorPanel), findsOneWidget);
    pending = Completer<String?>();
    await tester.tap(find.byKey(const ValueKey('retry-load')));
    await tester.pump();
    expect(find.byType(RecordListSkeleton), findsOneWidget);
    pending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('empty'), findsOneWidget);
    expect(find.byType(SkeletonRegion), findsNothing);
  });

  testWidgets(
    'late/out-of-order requests never overwrite the latest read or disposed state',
    (tester) async {
      final key = GlobalKey<AsyncSectionState<int>>();
      final reads = [Completer<int>(), Completer<int>()];
      var next = 0;
      await tester.pumpWidget(
        host(
          AsyncSection<int>(
            key: key,
            load: () => reads[next++].future,
            loadingBuilder: (_) => const RecordListSkeleton(),
            builder: (_, value) => Text('value $value'),
          ),
        ),
      );
      key.currentState!.reload();
      await tester.pump();
      reads[1].complete(2);
      await tester.pump();
      await tester.pump();
      expect(find.text('value 2'), findsOneWidget);
      reads[0].complete(1);
      await tester.pump();
      await tester.pump();
      expect(find.text('value 2'), findsOneWidget);
      await tester.pumpWidget(host(const SizedBox()));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'cleared cache rejects stale in-flight completion and preserves a newer request',
    () async {
      final cache = PhotoCache.instance..clear();
      final stale = Completer<Uint8List?>();
      final first = cache.load('same-version', () => stale.future);
      cache.clear();
      final fresh = Uint8List.fromList([2]);
      await cache.load('same-version', () async => fresh);
      expect(cache.peek('same-version'), same(fresh));
      stale.completeError(Exception('late failure'));
      await first;
      var fetched = false;
      expect(
        await cache.load('same-version', () async {
          fetched = true;
          return null;
        }),
        same(fresh),
      );
      expect(fetched, isFalse);
      cache.clear();
      expect(cache.peek('same-version'), isNull);
    },
  );
}
