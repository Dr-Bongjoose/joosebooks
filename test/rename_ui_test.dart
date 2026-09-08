import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:joosebooks_flutter/db.dart';
import 'package:joosebooks_flutter/main.dart';

/// Widget tests with sqflite_ffi: the DB completes on the REAL event loop,
/// so every await boundary needs `runAsync` (escape fake-async) + `pump()`
/// (drain microtasks). pumpAndSettle never settles → 10-min timeout. Proven
/// hanging Sep 8 2026; this file uses the runAsync choreography instead.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  group('profile popover + rename (widget)', () {
    late Database db;

    setUp(() async {
      db = await openAppDatabase(inMemoryDatabasePath);
      await db
          .insert('profiles', {'name': 'Bong Media', 'entity': 'LLC', 'created_ts': 0});
    });
    tearDown(() => db.close());

    testWidgets('popover lists piles; rename dialog prefilled; save renames Personal',
        (tester) async {
      await tester.pumpWidget(JooseBooksApp(db: db, home: DashboardPage(db: db)));
      await settle(tester); // let initState _refresh finish

      // Open the pile popover.
      await tester.tap(find.textContaining('▾'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Both piles visible — Personal is the real row now, not a hardcoded one.
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Bong Media'), findsOneWidget);
      // Rename affordance: a pencil per row (2 piles → 2 pencils).
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));

      // Open rename on Personal (first row).
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Rename pile'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Personal'); // prefilled

      // Test keyboard works here (unlike macOS synthetic input) — rename it.
      await tester.enterText(find.byType(TextField), 'Life & Home');
      await tester.tap(find.text('Save'));
      await settle(tester, 500); // db.update runs on the real loop
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // DB row renamed.
      final row = (await tester.runAsync(() async =>
              (await db.query('profiles', where: 'id = 0')).single['name']))!
          as String;
      expect(row, 'Life & Home');
      // Popover re-rendered with the new name; old name gone.
      expect(find.text('Life & Home'), findsOneWidget);
      expect(find.text('Personal'), findsNothing);
    });

    testWidgets('dashboard shows a back arrow when pushed; tapping returns to overview',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(
            body: Center(child: Text('OVERVIEW-SENTINEL'))),
      ));
      await settle(tester);
      // Push the dashboard the same way OverviewPage does. NOT awaited —
      // push's future resolves only when the route is popped, and that
      // happens later in this test (awaiting it deadlocks fake-async).
      nav.currentState!
          .push(MaterialPageRoute(builder: (_) => DashboardPage(db: db)));
      await settle(tester, 500);
      await tester.pump(const Duration(milliseconds: 300));

      // Dashboard is on top: the home route below is offstage (kept alive
      // but excluded from hit testing), and the dashboard header shows a
      // back affordance.
      expect(find.byType(BackButton), findsOneWidget);

      // Tap back → overview sentinel visible again.
      await tester.tap(find.byType(BackButton));
      await settle(tester, 400);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('OVERVIEW-SENTINEL'), findsOneWidget);
    });

    testWidgets('rename updates the dashboard header chip', (tester) async {
      await tester.pumpWidget(JooseBooksApp(db: db, home: DashboardPage(db: db)));
      await settle(tester);
      await tester.tap(find.textContaining('▾'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Me');
      await tester.tap(find.text('Save'));
      await settle(tester, 500);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      // Tap the renamed row to select it and close the popover.
      await tester.tap(find.text('Me').last);
      await settle(tester, 400);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Me ▾'), findsOneWidget);
    });
  });
}