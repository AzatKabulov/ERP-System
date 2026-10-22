import 'package:erp_system/widgets/charts.dart';
import 'package:erp_system/widgets/common.dart';
import 'package:erp_system/widgets/motion.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:erp_system/features/shared/async_section.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/real_rig.dart';

String tm(int minor) {
  final whole = (minor ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '$whole,${(minor % 100).toString().padLeft(2, '0')} TMT';
}

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// The motion of the app. Most tests run with the system's "remove animations" setting on; these
/// run with it off and check that things arrive, settle on the right values, and never overlap.
void main() {
  group('motion', () {
    testWidgets('revealing loaded content never reloads it at the end', (
      tester,
    ) async {
      var loads = 0;
      await tester.pumpWidget(
        host(
          Reveal(
            child: AsyncSection<int>(
              load: () async => ++loads,
              builder: (_, value) => Text('loaded $value'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(loads, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(loads, 1);
      expect(find.text('loaded 1'), findsOneWidget);
    });

    testWidgets('a figure counts up and ends on its exact value', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(CountUp(value: 30000, format: (n) => '${n.round()}')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      final early = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(early, greaterThan(0));
      expect(early, lessThan(30000)); // on its way
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('30000'), findsOneWidget);
    });

    testWidgets('reduced motion shows the final value at once', (tester) async {
      await tester.pumpWidget(
        host(
          CountUp(value: 30000, format: (n) => '${n.round()}'),
          reduced: true,
        ),
      );
      expect(find.text('30000'), findsOneWidget);
    });

    testWidgets('content revealed in a group arrives one after another', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              for (var i = 0; i < 3; i++)
                Reveal(
                  index: i,
                  child: Text('row $i', key: ValueKey('r$i')),
                ),
            ],
          ),
        ),
      );
      double opacityOf(int i) => tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byKey(ValueKey('r$i')),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(0), greaterThan(0)); // the first has started
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 3; i++) {
        expect(find.text('row $i'), findsOneWidget);
      }
      // Fully opaque without remounting the revealed content. At opacity 1
      // Flutter does not need an opacity compositing layer.
      expect(opacityOf(0), 1);
    });

    testWidgets('the switch thumb glides to the chosen segment', (
      tester,
    ) async {
      var value = 'a';
      late StateSetter set;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return AppSegmented<String>(
                keyPrefix: 'seg',
                value: value,
                onChanged: (v) => setState(() => value = v),
                options: const [('a', 'Alpha'), ('b', 'Beta')],
              );
            },
          ),
        ),
      );
      Alignment thumb() =>
          tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment
              as Alignment;
      expect(thumb(), const Alignment(-1, 0));
      await tester.tap(find.byKey(const ValueKey('seg-b')));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = thumb().x;
      expect(mid, greaterThan(-1)); // on its way, not jumped
      await tester.pump(const Duration(seconds: 1));
      expect(thumb(), const Alignment(1, 0));
      set(() => value = 'a');
      await tester.pump(const Duration(seconds: 1));
      expect(thumb(), const Alignment(-1, 0));
    });

    testWidgets('the area chart names the day under the pointer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 400,
            child: AreaChart(
              values: const [0, 100, 300, 200],
              labelFor: (i) => 'day $i',
              valueText: (i) => 'sum $i',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('day 2'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final box = tester.getRect(find.byType(AreaChart));
      await mouse.moveTo(Offset(box.left + box.width * 0.66, box.center.dy));
      await tester.pump();
      expect(find.text('day 2'), findsOneWidget);
      expect(find.text('sum 2'), findsOneWidget);
      await mouse.moveTo(const Offset(-50, -50));
      await tester.pump();
      expect(find.text('day 2'), findsNothing);
    });

    testWidgets('a page change shows only the new page, and it arrives', (
      tester,
    ) async {
      final rig = RealRig();
      await rig.launch(tester, reduceMotion: false);
      await rig.signIn(tester);
      await settle(tester, ms: 2500);
      expect(find.text(tm(30000)), findsOneWidget); // the dashboard, counted up
      expect(key('welcome'), findsOneWidget);
      await tapKey(tester, 'nav-products');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // the old page is gone at once: nothing overlaps while the new one fades in
      expect(key('welcome'), findsNothing);
      await settle(tester, ms: 1200);
      expect(key('catalog-view-toggle'), findsOneWidget);
    });
  });
}
