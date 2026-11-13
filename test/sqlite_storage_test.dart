import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studysync/services/storage_service.dart';

void main() {
  sqfliteFfiInit();
  final store = StorageService.instance;
  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_sql');
    dbPath = p.join(dir.path, 'studysync.db');
    await store.initSqliteAt(dbPath, databaseFactoryFfi);
  });

  tearDown(() async {
    store.onUserChange = null;
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<void> restart() async {
    await store.close();
    await store.initSqliteAt(dbPath, databaseFactoryFfi);
  }

  test('collections are real SQLite tables and survive a restart', () async {
    await store.openUser('u1');
    await store.writeList('subjects', [
      {'id': 's1', 'name': 'Networks'},
      {'id': 's2', 'name': 'Databases'},
    ]);
    await store.writeList('tasks', [
      {'id': 't2', 'start': '2026-10-14T09:00:00.000', 'title': 'B'},
      {'id': 't1', 'start': '2026-10-13T09:00:00.000', 'title': 'A'},
    ]);
    await restart();
    await store.openUser('u1');
    expect(store.readList('subjects').map((m) => m['name']), ['Networks', 'Databases']);
    expect(store.readList('tasks').map((m) => m['id']), ['t1', 't2'], reason: 'ordered by start time in SQL');

    final db = await databaseFactoryFfi.openDatabase(dbPath);
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']);
    expect(tables, containsAll(['subjects', 'study_tasks', 'study_sessions', 'daily_tasks', 'surveys', 'app_kv', 'user_kv']));
    final count = await db.rawQuery('SELECT COUNT(*) AS n FROM study_tasks WHERE uid = ?', ['u1']);
    expect(count.first['n'], 2);
    await db.close();
  });

  test('settings and preferences persist with their types', () async {
    await store.app.put('language', 'SI');
    await store.openUser('u1');
    await store.write('setupDone', true);
    await store.writeMap('prefs', {'session': 45, 'mode': 'examFocus'});
    await restart();
    expect(store.app.get('language'), 'SI');
    expect(store.app.get('missing', defaultValue: 'EN'), 'EN');
    await store.openUser('u1');
    expect(store.read<bool>('setupDone'), isTrue);
    expect(store.readMap('prefs'), {'session': 45, 'mode': 'examFocus'});
  });

  test('each student only sees their own data', () async {
    await store.openUser('u1');
    await store.writeList('subjects', [{'id': 's1', 'name': 'Mine'}]);
    await store.openUser('u2');
    expect(store.readList('subjects'), isEmpty);
    await store.writeList('subjects', [{'id': 's9', 'name': 'Theirs'}]);
    await store.openUser('u1');
    expect(store.readList('subjects').single['name'], 'Mine');
  });

  test('reset clears only the current student', () async {
    await store.openUser('u2');
    await store.writeList('subjects', [{'id': 'x', 'name': 'Keep'}]);
    await store.openUser('u1');
    await store.writeList('subjects', [{'id': 's1', 'name': 'Gone'}]);
    await store.clearUser();
    await restart();
    await store.openUser('u1');
    expect(store.readList('subjects'), isEmpty);
    await store.openUser('u2');
    expect(store.readList('subjects'), hasLength(1));
  });

  test('writes notify cloud sync; imports from the cloud do not echo back', () async {
    final seen = <String>[];
    store.onUserChange = (uid, key, value) => seen.add('$uid:$key');
    await store.openUser('u1');
    await store.writeList('dailyTasks', [{'id': 'd1', 'title': 'Read', 'date': '2026-10-13T00:00:00.000'}]);
    await store.write('flags', 'planner');
    expect(seen, ['u1:dailyTasks', 'u1:flags']);

    await store.importUser({'subjects': [{'id': 'r1', 'name': 'From cloud'}], 'consent': true});
    expect(seen, hasLength(2));
    expect(store.readList('subjects').single['name'], 'From cloud');
    expect(store.read<bool>('consent'), isTrue);
  });

  test('inspector stats and rows come straight from SQLite', () async {
    await store.openUser('u1');
    await store.writeList('dailyTasks', [
      {'id': 'd1', 'title': 'Read', 'date': '2026-10-13T00:00:00.000'},
      {'id': 'd2', 'title': 'Gym', 'date': '2026-10-12T00:00:00.000'},
    ]);
    await store.write('setupDone', true);
    final stats = {for (final (table, _, n) in await store.tableStats()) table: n};
    expect(stats['daily_tasks'], 2);
    expect(stats['subjects'], 0);
    expect(stats['user_kv'], 1);
    final rows = await store.tableRows('daily_tasks');
    expect(rows.map((r) => r['id']), ['d2', 'd1'], reason: 'ORDER BY sort_at');
    expect(rows.first.keys, containsAll(['id', 'sort_at', 'data', 'updated_at']));
    expect(store.databasePath, dbPath);
  });
}
