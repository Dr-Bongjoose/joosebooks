import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:joosebooks_flutter/db.dart';
import 'package:joosebooks_flutter/main.dart';

/// Entry lifecycle tests: edit, undo delete, swipe-to-delete. Same runAsync
/// choreography as rename_ui_test.dart — sqflite_ffi completes on the REAL
/// event loop, so every await boundary needs runAsync + pump (pumpAndSettle
/// deadlocks; proven Sep 8 2026).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  /// Seed one "out" entry ($25.50, Equipment, today) and open the dashboard.
  /// The insert MUST go through runAsync — raw awaits on ffi futures inside
  /// the fake-async zone never resume (real event loop vs fake zone).
  Future<int> seedEntry(WidgetTester tester, Database db) async {
    final ts = DateTime(2026, 9, 9, 12).millisecondsSinceEpoch ~/ 1000;
    final id = await tester.runAsync(() => db.insert('entries', {
          'ts': ts,
          'amount_cents': 2550,
          'kind': 'out',
          'category': 'Equipment',
          'note': 'Test note',
          'profile_id': 0,
        }));
    return id!;
  }

  /// The add/edit sheet is ~900px tall — taller than the default 800×600
  /// test viewport — so keypad rows and the Save button sit below the fold
  /// and taps silently miss (hit-test warning + zero effect). Give the test
  /// a tall surface so the whole sheet AND the undo snackbar (docked at the
  /// very bottom, its rect can sit at y≈1414 on a 1400 surface) stay
  /// on-screen and tappable.
  void useTallView(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.reset);
  }

  group('entry lifecycle (widget)', () {
    late Database db;
    setUp(() async {
      db = await openAppDatabase(inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    testWidgets('tapping an entry row opens the edit sheet prefilled; '
        'changing amount and saving updates the row', (tester) async {
      useTallView(tester);
      final id = await seedEntry(tester, db);
      await tester.pumpWidget(JooseBooksApp(db: db, home: DashboardPage(db: db)));
      await settle(tester, 400);

      // Row shows the note; tap it to open the edit sheet.
      expect(find.textContaining('Test note'), findsOneWidget);
      await tester.tap(find.textContaining('Test note'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Sheet is open, prefilled: $25.50, Money OUT, Equipment, note.
      expect(find.text('Edit entry'), findsOneWidget);
      // Amount shows twice on screen: the row's trailing price + the sheet's
      // big display — scope the finder to the sheet's 40pt display.
      final sheetAmount = find.widgetWithText(Container, '\$25.50').last;
      expect(sheetAmount, findsOneWidget);
      expect(find.text('Test note'), findsWidgets); // row + field controller
      final equipChip = find.widgetWithText(ChoiceChip, 'Equipment');
      expect(equipChip, findsOneWidget);
      expect(tester.widget<ChoiceChip>(equipChip).selected, isTrue);

      // Change amount to 40.00: keypad 4, 0, then save.
      await tester.tap(find.widgetWithText(OutlinedButton, '4'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      await tester.pump();
      expect(find.text('\$40'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await settle(tester, 500);
      // Drain the modal-route pop animation fully before asserting (two
      // 400ms fake pumps; a single short pump left the sheet half-visible).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // DB row updated in place (same id, new amount).
      final row = (await tester.runAsync(() async =>
              (await db.query('entries', where: 'id = ?', whereArgs: [id]))
                  .single))!;
      expect(row['amount_cents'], 4000);
      expect(row['kind'], 'out');
      // Sheet closed, list reflects it — one more runAsync cycle to drain
      // the _refresh query that fired when the route popped.
      expect(find.text('Edit entry'), findsNothing);
      await settle(tester, 400);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('\$40.00'), findsOneWidget);
    });

    testWidgets('edit sheet opens via the same add sheet; kind toggle works '
        'in edit mode', (tester) async {
      useTallView(tester);
      final id = await seedEntry(tester, db);
      await tester.pumpWidget(JooseBooksApp(db: db, home: DashboardPage(db: db)));
      await settle(tester, 400);

      await tester.tap(find.textContaining('Test note'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Flip to Money IN and save.
      await tester.tap(find.text('⬆ Money IN'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await settle(tester, 500);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final row = (await tester.runAsync(() async =>
              (await db.query('entries', where: 'id = ?', whereArgs: [id]))
                  .single))!;
      expect(row['kind'], 'in');
    });

    testWidgets('swipe an entry row left → row deleted with UNDO snackbar; '
        'the always-on × button is gone', (tester) async {
      final id = await seedEntry(tester, db);
      await tester.pumpWidget(JooseBooksApp(db: db, home: DashboardPage(db: db)));
      await settle(tester, 400);

      // The old always-on delete × is gone — rows delete by swipe only.
      expect(find.byIcon(Icons.close), findsNothing);

      final rowFinder = find.textContaining('Test note');
      expect(rowFinder, findsOneWidget);

      // A slow full drag (not a fling): Dismissible needs the gesture to
      // cross the dismiss threshold, then its dismiss+resize animations
      // must run to completion (~500ms fake time) before onDismissed fires.
      await tester.drag(rowFinder, const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester, 300);
      // Snackbar entrance: keep pumping until its rect is fully docked
      // (entrance anim ~250ms; tapping mid-entrance silently misses).
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(SnackBar), findsOneWidget);
      final gone = await tester.runAsync(() async =>
          (await db.query('entries', where: 'id = ?', whereArgs: [id])));
      expect(gone, isEmpty);

      // UNDO brings it back.
      await tester.tap(find.text('UNDO'));
      await settle(tester, 400);
      final back = await tester.runAsync(() async =>
          (await db.query('entries', where: 'id = ?', whereArgs: [id])));
      expect(back, isNotEmpty);
    });
  });
}