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
  });
}