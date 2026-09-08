import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:joosebooks_flutter/db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('db v3 schema — Personal as real row', () {
    test('fresh v3 DB: Personal row exists at id 0, entries default to it', () async {
      final db = await openAppDatabase(inMemoryDatabasePath);
      final profs = await db.query('profiles', orderBy: 'id');
      expect(profs.first['id'], 0);
      expect(profs.first['name'], 'Personal');
      await db.insert('entries', {'ts': 0, 'amount_cents': 1000, 'kind': 'in'});
      final row = await db.query('entries', limit: 1);
      expect(row.single['profile_id'], 0);
      expect((await db.query('profiles')).length, 1);
      await db.close();
    });

    test('v2 DB with a business upgrades to v3: Personal row added, business untouched', () async {
      final tmp = '${Directory.systemTemp.path}/jb_v3_upgrade_test.db';
      final f = File(tmp);
      if (await f.exists()) await f.delete();
      // Build a real v2 file (in-memory dies with its handle).
      final dbV2 = await openDatabase(tmp, version: 2, onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            amount_cents INTEGER NOT NULL,
            kind TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'Other',
            note TEXT DEFAULT '',
            profile_id INTEGER DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            entity TEXT DEFAULT '',
            created_ts INTEGER NOT NULL
          )''');
      });
      final bizId = await dbV2
          .insert('profiles', {'name': 'Bong Media', 'entity': 'LLC', 'created_ts': 100});
      await dbV2.insert('entries',
          {'ts': 200, 'amount_cents': 2500, 'kind': 'out', 'profile_id': bizId});
      await dbV2.close();

      final db = await openAppDatabase(tmp);
      final profs = await db.query('profiles', orderBy: 'id');
      // Personal row added, existing business preserved with its id.
      expect(profs.length, 2);
      expect(profs.first['id'], 0);
      expect(profs.first['name'], 'Personal');
      expect(profs.last['id'], bizId);
      expect(profs.last['name'], 'Bong Media');
      // Entry still points at the business.
      final entry = await db.query('entries', limit: 1);
      expect(entry.single['profile_id'], bizId);
      await db.close();
      await f.delete();
    });

    test('v1 → v3 chain: profile_id column added, old entries = Personal, Personal row exists', () async {
      final tmp = '${Directory.systemTemp.path}/jb_v1_v3_upgrade_test.db';
      final f = File(tmp);
      if (await f.exists()) await f.delete();
      final dbV1 = await openDatabase(tmp, version: 1, onCreate: (db, v) => db.execute('''
        CREATE TABLE entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          amount_cents INTEGER NOT NULL,
          kind TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Other',
          note TEXT DEFAULT ''
        )'''));
      await dbV1.insert('entries', {'ts': 0, 'amount_cents': 5000, 'kind': 'in'});
      await dbV1.close();

      final db = await openAppDatabase(tmp);
      final row = await db.query('entries', limit: 1);
      expect(row.single['profile_id'], 0);
      final profs = await db.query('profiles');
      expect(profs.any((p) => p['id'] == 0 && p['name'] == 'Personal'), isTrue);
      await db.close();
      await f.delete();
    });
  });

  group('rename profile', () {
    late Database db;
    setUp(() async => db = await openAppDatabase(inMemoryDatabasePath));
    tearDown(() => db.close());

    test('rename Personal (id 0): name updated, entries untouched', () async {
      await db.insert('entries',
          {'ts': 100, 'amount_cents': 10000, 'kind': 'in', 'profile_id': 0});
      await renameProfile(db, 0, 'Me Myself');
      final p0 = (await db.query('profiles', where: 'id = 0')).single;
      expect(p0['name'], 'Me Myself');
      final entry = await db.query('entries', limit: 1);
      expect(entry.single['profile_id'], 0); // pointer unchanged
    });

    test('rename business: name updated, entity + entries untouched', () async {
      final pid = await db.insert(
          'profiles', {'name': 'Old', 'entity': 'LLC', 'created_ts': 0});
      await db.insert('entries',
          {'ts': 5, 'amount_cents': 100, 'kind': 'in', 'profile_id': pid});
      await renameProfile(db, pid, 'New Name');
      final p = (await db.query('profiles', where: 'id = ?', whereArgs: [pid])).single;
      expect(p['name'], 'New Name');
      expect(p['entity'], 'LLC');
      final entry = await db.query('entries', limit: 1);
      expect(entry.single['profile_id'], pid);
    });
  });

  group('entry dates', () {
    late Database db;
    setUp(() async => db = await openAppDatabase(inMemoryDatabasePath));
    tearDown(() => db.close());

    test('save path: entry with explicit noon ts lands in right year+profile query', () async {
      // What AddEntrySheet._save does with a user-chosen date (Sep 1 2026).
      final chosen = DateTime(2026, 9, 1, 12);
      final ts = chosen.millisecondsSinceEpoch ~/ 1000;
      final pid = await db.insert(
          'profiles', {'name': 'Bong Media', 'entity': 'LLC', 'created_ts': 0});
      await db.insert('entries', {
        'ts': ts, 'amount_cents': 1200, 'kind': 'out',
        'category': 'Server costs', 'note': 'hosting', 'profile_id': pid});
      // Year query (dashboard) finds it.
      final (startY, endY) = yearWindow(2026);
      final rows = await db.query('entries',
          where: 'ts >= ? AND ts < ? AND profile_id = ?',
          whereArgs: [startY, endY, pid]);
      expect(rows.length, 1);
      // Round-trip preserves the chosen calendar day.
      final back = DateTime.fromMillisecondsSinceEpoch((rows.single['ts'] as int) * 1000);
      expect(back.year, 2026);
      expect(back.month, 9);
      expect(back.day, 1);
    });

    test('noon rule: entry at local noon of chosen day buckets into that day', () {
      // Sep 1 2026, local noon — 12h on each side of midnight boundaries.
      final noon = DateTime(2026, 9, 1, 12);
      final secs = noon.millisecondsSinceEpoch ~/ 1000;
      final back = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
      expect(back.day, 1);
      expect(back.month, 9);
      expect(back.year, 2026);
      // One year window covering Sep 2026 contains it.
      final startY = DateTime(2026).millisecondsSinceEpoch ~/ 1000;
      final endY = DateTime(2027).millisecondsSinceEpoch ~/ 1000;
      expect(secs >= startY && secs < endY, isTrue);
    });

    test('bucketing: entry in Sep vs Aug lands in correct month bucket', () {
      final sep = DateTime(2026, 9, 15, 12).millisecondsSinceEpoch ~/ 1000;
      final aug = DateTime(2026, 8, 31, 12).millisecondsSinceEpoch ~/ 1000;
      final bSep = monthBucket(secs: sep, year: 2026);
      final bAug = monthBucket(secs: aug, year: 2026);
      expect(bSep[8]['income'], 0.0); // no income yet in Sep bucket (values set later)
      expect(bSep[8]['expenses'], 0.0);
      // Round-trip: the secs belong to that bucket's month.
      expect(sep >= bSep[8]['start']!, isTrue);
      expect(sep < bSep[8]['end']!, isTrue);
      expect(aug >= bAug[7]['start']!, isTrue);
      expect(aug < bAug[7]['end']!, isTrue);
    });
  });

  group('monthlyByProfile', () {
    late Database db;
    setUp(() async => db = await openAppDatabase(inMemoryDatabasePath));
    tearDown(() => db.close());

    test('splits income/expenses per month per profile for a year', () async {
      final pid = await db.insert(
          'profiles', {'name': 'Bong Media', 'entity': 'LLC', 'created_ts': 0});
      int secs(int mo, int day) =>
          DateTime(2026, mo, day, 12).millisecondsSinceEpoch ~/ 1000;
      await db.insert('entries', {
        'ts': secs(2, 10), 'amount_cents': 10000, 'kind': 'in', 'profile_id': 0});
      await db.insert('entries', {
        'ts': secs(2, 20), 'amount_cents': 4000, 'kind': 'out', 'profile_id': 0});
      await db.insert('entries', {
        'ts': secs(9, 3), 'amount_cents': 5000, 'kind': 'in', 'profile_id': 0});
      // Business: -25 out in Feb, +300 in Sep.
      await db.insert('entries', {
        'ts': secs(2, 15), 'amount_cents': 2500, 'kind': 'out', 'profile_id': pid});
      await db.insert('entries', {
        'ts': secs(9, 5), 'amount_cents': 30000, 'kind': 'in', 'profile_id': pid});

      final personal = await monthlyByProfile(db, 2026, 0);
      expect(personal[1]['income'], 100.0);
      expect(personal[1]['expenses'], 40.0);
      expect(personal[8]['income'], 50.0);
      expect(personal[0]['income'], 0.0); // empty months are zeroed, not missing
      expect(personal.length, 12);

      final biz = await monthlyByProfile(db, 2026, pid);
      expect(biz[1]['expenses'], 25.0);
      expect(biz[8]['income'], 300.0);
      expect(biz[1]['income'], 0.0);
    });
  });
}