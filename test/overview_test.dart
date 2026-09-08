import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joosebooks_flutter/charts.dart';
import 'package:joosebooks_flutter/overview_content.dart';

/// OverviewContent is PURE presentation — no db, no async — so plain
/// pumpWidget works (no runAsync choreography needed). The db-backed page
/// (OverviewPage) is verified visually + covered by db_test.dart queries.
void main() {
  List<Map<String, double>> buckets({double inFeb = 0, double outFeb = 0}) {
    final b = List.generate(
        12, (_) => {'income': 0.0, 'expenses': 0.0});
    b[1]['income'] = inFeb;
    b[1]['expenses'] = outFeb;
    return b;
  }

  group('OverviewContent', () {
    testWidgets('renders one card per pile with totals + charts', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OverviewContent(
          year: 2026,
          profiles: [
            {'id': 0, 'name': 'Personal'},
            {'id': 1, 'name': 'Bong Media'},
          ],
          monthly: {0: buckets(inFeb: 200), 1: buckets(outFeb: 50)},
          totals: {
            0: {'income': 200.0, 'expenses': 0.0, 'profit': 200.0},
            1: {'income': 0.0, 'expenses': 50.0, 'profit': -50.0},
          },
          onOpenPile: (_) {},
          onQuickAdd: () {},
          onPrevYear: () {},
          onNextYear: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Bong Media'), findsOneWidget);
      expect(find.byType(MiniBarChart), findsNWidgets(2));
      // Totals land on the cards.
      expect(find.text('in \$200.00'), findsOneWidget);
      expect(find.text('out \$50.00'), findsOneWidget);
      // Profit color-coding text (negative shows minus).
      expect(find.text('profit -\$50.00'), findsOneWidget);
      expect(find.text('profit \$200.00'), findsOneWidget);
    });

    testWidgets('empty state when no piles', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OverviewContent(
          year: 2026,
          profiles: const [],
          monthly: const {},
          totals: const {},
          onOpenPile: (_) {},
          onQuickAdd: () {},
          onPrevYear: () {},
          onNextYear: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No piles yet.'), findsOneWidget);
    });

    testWidgets('tapping a card fires onOpenPile with that pile id', (tester) async {
      int? opened;
      await tester.pumpWidget(MaterialApp(
        home: OverviewContent(
          year: 2026,
          profiles: [
            {'id': 0, 'name': 'Personal'},
            {'id': 3, 'name': 'Bong Media'},
          ],
          monthly: {0: buckets(), 3: buckets()},
          totals: {
            0: {'income': 0.0, 'expenses': 0.0, 'profit': 0.0},
            3: {'income': 0.0, 'expenses': 0.0, 'profit': 0.0},
          },
          onOpenPile: (pid) => opened = pid,
          onQuickAdd: () {},
          onPrevYear: () {},
          onNextYear: () {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bong Media'));
      expect(opened, 3);
    });
  });
}