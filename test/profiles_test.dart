import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // The exact schema factory used by main.dart (v2, profiles included).
  Future<Database> openV2(String path) => openDatabase(path, version: 2,
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
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          // Guarded ALTER: existing installs add the column; old entries stay Personal.
          try {
            await db.execute('ALTER TABLE entries ADD COLUMN profile_id INTEGER DEFAULT 0');
          } catch (_) {} // fresh-but-flagged DBs may already have it
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
      });

  group('profiles schema', () {
    test('fresh v2 DB: profiles table exists, entries.profile_id defaults to 0', () async {
      final db = await openV2(inMemoryDatabasePath);
      final cols = await db.rawQuery('PRAGMA table_info(entries)');
      expect(cols.any((c) => c['name'] == 'profile_id'), isTrue);
      await db.insert('entries', {'ts': 0, 'amount_cents': 1000, 'kind': 'in'});
      final row = await db.query('entries', limit: 1);
      expect(row.single['profile_id'], 0);
      expect((await db.query('profiles')).length, 0);
      await db.close();
    });

    test('v1 DB (no profile_id column) upgrades: column added, old entries = Personal', () async {
      final db1 = await openDatabase(inMemoryDatabasePath, version: 1,
          onCreate: (db, v) => db.execute('''
            CREATE TABLE entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ts INTEGER NOT NULL,
              amount_cents INTEGER NOT NULL,
              kind TEXT NOT NULL,
              category TEXT NOT NULL DEFAULT 'Other',
              note TEXT DEFAULT ''
            )'''));
      await db1.insert('entries', {'ts': 0, 'amount_cents': 5000, 'kind': 'in'});
      await db1.close();
      // Reopen at v2 — simulates the app updating over an existing install.
      // (in-memory DBs die with the handle, so prove the upgrade path on a temp file)
      final tmp = '${Directory.systemTemp.path}/jb_upgrade_test.db';
      final f = File(tmp);
      if (await f.exists()) await f.delete();
      final dbA = await openDatabase(tmp, version: 1,
          onCreate: (db, v) => db.execute('''
            CREATE TABLE entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ts INTEGER NOT NULL,
              amount_cents INTEGER NOT NULL,
              kind TEXT NOT NULL,
              category TEXT NOT NULL DEFAULT 'Other',
              note TEXT DEFAULT ''
            )'''));
      await dbA.insert('entries', {'ts': 0, 'amount_cents': 5000, 'kind': 'in'});
      await dbA.close();
      final dbB = await openDatabase(tmp, version: 2,
          onUpgrade: (db, o, n) async {
            await db.execute('ALTER TABLE entries ADD COLUMN profile_id INTEGER DEFAULT 0');
            await db.execute('CREATE TABLE IF NOT EXISTS profiles (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, entity TEXT DEFAULT \'\', created_ts INTEGER NOT NULL)');
          });
      final row = await dbB.query('entries', limit: 1);
      expect(row.single['profile_id'], 0); // old money belongs to Personal
      final sum = await dbB.rawQuery(
          'SELECT SUM(amount_cents) s FROM entries WHERE profile_id = 0');
      expect(sum.single['s'], 5000);
      await dbB.close();
      await f.delete();
    });
  });

  group('profile split accounting', () {
    late Database db;
    setUp(() async {
      db = await openV2(inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    test('create business → entries split per profile; Personal unaffected', () async {
      final pid = await db.insert('profiles',
          {'name': 'Bong Media', 'entity': 'LLC', 'created_ts': 0});
      await db.insert('entries',
          {'ts': 100, 'amount_cents': 10000, 'kind': 'in', 'profile_id': 0});
      await db.insert('entries',
          {'ts': 200, 'amount_cents': 2500, 'kind': 'out', 'profile_id': pid});
      final personal = await db.rawQuery(
          'SELECT SUM(amount_cents) s FROM entries WHERE profile_id = 0 AND kind = ?',
          ['in']);
      expect(personal.single['s'], 10000);
      final biz = await db.rawQuery(
          'SELECT SUM(amount_cents) s FROM entries WHERE profile_id = ? AND kind = ?',
          [pid, 'out']);
      expect(biz.single['s'], 2500);
    });

    test('delete profile: entries fall back to Personal, profile gone', () async {
      final pid = await db.insert('profiles',
          {'name': 'Etsy', 'entity': 'Sole Prop', 'created_ts': 0});
      await db.insert('entries',
          {'ts': 300, 'amount_cents': 700, 'kind': 'in', 'profile_id': pid});
      await db.execute('UPDATE entries SET profile_id = 0 WHERE profile_id = ?', [pid]);
      await db.delete('profiles', where: 'id = ?', whereArgs: [pid]);
      final row = await db.query('entries', limit: 1);
      expect(row.single['profile_id'], 0);
      expect((await db.query('profiles')).length, 0);
    });
  });
}

// Silence unused-import lint for File/Directory used in upgrade test.