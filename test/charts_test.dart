import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joosebooks_flutter/charts.dart';

void main() {
  group('MiniBarChart', () {
    testWidgets('renders 12 month slots from bucket data', (tester) async {
      final buckets = List.generate(12, (m) {
        return {'income': m == 2 ? 100.0 : 0.0, 'expenses': m == 4 ? 40.0 : 0.0};
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MiniBarChart(buckets: buckets))));
      // The painter is attached to a CustomPaint.
      expect(find.byType(CustomPaint), findsWidgets);
      final painters = tester.widgetList<CustomPaint>(
          find.byType(CustomPaint)).map((cp) => cp.painter);
      expect(painters.whereType<MiniBarChartPainter>().length, 1);
      final p = painters.whereType<MiniBarChartPainter>().first;
      expect(p.buckets.length, 12);
      expect(p.maxVal, 100.0); // scaled to the biggest value
    });

    testWidgets('all-zero data renders without division-by-zero', (tester) async {
      final buckets = List.generate(
          12, (_) => {'income': 0.0, 'expenses': 0.0});
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MiniBarChart(buckets: buckets))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('month letters: 12 separate labels, each centered on its '
        'bar slot', (tester) async {
      final buckets = List.generate(
          12, (_) => {'income': 0.0, 'expenses': 0.0});
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MiniBarChart(key: key, buckets: buckets))));

      const letters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
      // 12 separate letter widgets — not one letterSpacing string. Find by
      // ValueKey (J/M/A repeat across months, so find.text would be ambiguous).
      for (var m = 0; m < 12; m++) {
        expect(find.byKey(ValueKey('month-label-$m')), findsOneWidget);
      }

      // Each letter's horizontal center must sit on its slot's center
      // (slot = chartWidth / 12, slot m centered at (m + 0.5) * slot).
      final box = key.currentContext!.findRenderObject()! as RenderBox;
      final chartW = box.size.width;
      final slot = chartW / 12;
      for (var m = 0; m < 12; m++) {
        final rect = tester.getRect(find.byKey(ValueKey('month-label-$m')));
        final center = rect.center.dx;
        final expected = slot * (m + 0.5);
        expect((center - expected).abs(), lessThan(1.5),
            reason: 'letter ${letters[m]} (month $m) center $center '
                'vs slot center $expected (chart $chartW)');
      }
    });
  });
}