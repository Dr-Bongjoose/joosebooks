import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// JooseBooks database layer — schema (v3) + the aggregation queries the UI
/// reads. Kept separate from main.dart so tests and screens share ONE factory.

/// Opens (and migrates) the app database.
///
/// Version history:
///   v1 — entries only.
///   v2 — business profiles (guarded ALTER; old entries stay Personal, id 0).
///   v3 — Personal becomes a REAL row (id 0) so it can be renamed like any
///        other pile. Entry semantics unchanged: profile_id 0 = Personal.
Future<Database> openAppDatabase(String path) => openDatabase(path, version: 3,
    onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          amount_cents INTEGER NOT NULL,
          kind TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Other',
          note TEXT DEFAULT '',
          profile_id INTEGER DEFAULT 0
        )''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          entity TEXT DEFAULT '',
          created_ts INTEGER NOT NULL
        )''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_entries_profile ON entries(profile_id, ts)');
      await _seedPersonal(db);
    },
    onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) {
        // Guarded ALTER: pre-profile installs add the column; old entries stay
        // Personal (0). Never moves or deletes anyone's data.
        try {
          await db.execute(
              'ALTER TABLE entries ADD COLUMN profile_id INTEGER DEFAULT 0');
        } catch (_) {}
        await db.execute('''
          CREATE TABLE IF NOT EXISTS profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            entity TEXT DEFAULT '',
            created_ts INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_entries_profile ON entries(profile_id, ts)');
      }
      if (oldV < 3) {
        // INSERT OR IGNORE: id 0 is fixed (autoincrement started at 1), so the
        // only way this inserts is when the row is genuinely missing. Renames
        // a v2 install's virtual Personal into a real row — no data moves.
        await _seedPersonal(db);
      }
    });

Future<void> _seedPersonal(Database db) => db.execute('''
  INSERT OR IGNORE INTO profiles (id, name, entity, created_ts)
  VALUES (0, 'Personal', '', 0)''');

/// Renames any profile including Personal. Entries keep pointing at the same
/// id — a rename never touches money records.
Future<void> renameProfile(Database db, int profileId, String name) =>
    db.update('profiles', {'name': name},
        where: 'id = ?', whereArgs: [profileId]);

/// Year window [start, end) in unix seconds for a given year.
(int, int) yearWindow(int year) {
  final start = DateTime(year).millisecondsSinceEpoch ~/ 1000;
  final end = DateTime(year + 1).millisecondsSinceEpoch ~/ 1000;
  return (start, end);
}

/// 12 month buckets (Jan..Dec) for [year], each
/// {income: double, expenses: double, start: int, end: int}.
/// Buckets are computed in Dart from one year-scoped query so the same query
/// feeds both the summary and the chart.
List<Map<String, double>> monthBucket({required int year, required int secs}) {
  final buckets = List.generate(12, (m) {
    final start = DateTime(year, m + 1).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(year, m + 2).millisecondsSinceEpoch ~/ 1000;
    return {'income': 0.0, 'expenses': 0.0, 'start': start.toDouble(), 'end': end.toDouble()};
  });
  for (var m = 0; m < 12; m++) {
    final b = buckets[m];
    if (secs >= b['start']! && secs < b['end']!) break;
  }
  return buckets;
}

Future<List<Map<String, double>>> monthlyByProfile(
    Database db, int year, int profileId) async {
  final (startY, endY) = yearWindow(year);
  final rows = await db.query('entries',
      where: 'ts >= ? AND ts < ? AND profile_id = ?',
      whereArgs: [startY, endY, profileId],
      orderBy: 'ts DESC');
  final buckets = List.generate(12, (m) {
    final start = DateTime(year, m + 1).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(year, m + 2).millisecondsSinceEpoch ~/ 1000;
    return {'income': 0.0, 'expenses': 0.0, 'start': start.toDouble(), 'end': end.toDouble()};
  });
  for (final r in rows) {
    final ts = r['ts'] as int;
    for (var m = 0; m < 12; m++) {
      final b = buckets[m];
      if (ts >= b['start']! && ts < b['end']!) {
        final v = (r['amount_cents'] as int) / 100;
        if (r['kind'] == 'in') {
          b['income'] = b['income']! + v;
        } else {
          b['expenses'] = b['expenses']! + v;
        }
        break;
      }
    }
  }
  return buckets;
}