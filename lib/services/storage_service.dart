import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Offline-first local storage.
///
/// * Android / iOS: **SQLite** (sqflite) — one table per collection
///   (`subjects`, `study_tasks`, `study_sessions`, `daily_tasks`, `surveys`)
///   plus key-value tables for settings.
/// * Web (browser demo) and tests: Hive, because SQLite isn't available there.
///
/// Everything is cached in memory, so reads are synchronous and instant; writes
/// update the cache, persist to disk, and notify [onUserChange] (cloud sync).
class StorageService {
  StorageService._();
  static final instance = StorageService._();

  late _Backend _backend;
  final app = AppKv._();

  String? _uid;
  final Map<String, Object?> _userKv = {};
  final Map<String, List<Map<String, dynamic>>> _lists = {};

  /// Called after every user-data write: (uid, key, value). Used by cloud sync.
  void Function(String uid, String key, Object? value)? onUserChange;

  String? get currentUid => _uid;
  bool get usesSqlite => _backend is _SqliteBackend;

  /// Where the SQLite database file lives on the phone (null on web).
  String? get databasePath => _backend is _SqliteBackend ? (_backend as _SqliteBackend).path : null;

  /// Row counts per table for the open student (for the Database & Cloud screen).
  Future<List<(String table, String key, int rows)>> tableStats() async {
    final uid = _uid;
    final out = <(String, String, int)>[];
    for (final e in collections.entries) {
      final n = _backend is _SqliteBackend && uid != null
          ? await (_backend as _SqliteBackend).count(e.value, uid)
          : (_lists[e.key]?.length ?? 0);
      out.add((e.value, e.key, n));
    }
    final kv = _backend is _SqliteBackend && uid != null
        ? await (_backend as _SqliteBackend).count('user_kv', uid)
        : _userKv.length;
    out.add(('user_kv', '', kv));
    return out;
  }

  /// Raw rows of one table for the open student, straight from SQLite.
  Future<List<Map<String, Object?>>> tableRows(String table, {int limit = 100}) async {
    final uid = _uid;
    if (uid == null) return [];
    if (_backend is _SqliteBackend) return (_backend as _SqliteBackend).rows(table, uid, limit);
    final key = collections.entries.where((e) => e.value == table).map((e) => e.key).firstOrNull;
    if (key == null) {
      return [for (final e in _userKv.entries) {'key': e.key, 'value': jsonEncode(e.value)}];
    }
    return [for (final m in (_lists[key] ?? const []).take(limit)) {'id': m['id'], 'data': jsonEncode(m)}];
  }

  /// The SQL the inspector runs for a table (shown on screen for the demo).
  static String querySql(String table) => table == 'user_kv'
      ? 'SELECT key, value FROM user_kv WHERE uid = ?'
      : 'SELECT id, sort_at, data, updated_at FROM $table WHERE uid = ? ORDER BY sort_at LIMIT 100';

  /// Collections stored as SQLite tables (key used by the app → table name).
  static const collections = {
    'subjects': 'subjects',
    'tasks': 'study_tasks',
    'sessions': 'study_sessions',
    'dailyTasks': 'daily_tasks',
    'surveys': 'surveys',
  };

  Future<void> init() async {
    if (kIsWeb) {
      await Hive.initFlutter();
      _backend = _HiveBackend();
    } else {
      _backend = _SqliteBackend(p.join(await getDatabasesPath(), 'studysync.db'), databaseFactory);
    }
    await _open();
  }

  /// Tests: Hive in a plain directory (no path_provider plugin).
  Future<void> initAt(String path) async {
    Hive.init(path);
    _backend = _HiveBackend();
    await _open();
  }

  /// Tests: SQLite with a given factory (e.g. sqflite_common_ffi).
  Future<void> initSqliteAt(String dbPath, DatabaseFactory factory) async {
    _backend = _SqliteBackend(dbPath, factory);
    await _open();
  }

  Future<void> _open() async {
    await _backend.open();
    app._backend = _backend;
    app._cache
      ..clear()
      ..addAll(await _backend.loadAppKv());
    _uid = null;
    _userKv.clear();
    _lists.clear();
  }

  Future<void> close() => _backend.close();

  // ── Per-user data ────────────────────────────────────────────────────────
  Future<void> openUser(String uid) async {
    if (_uid == uid) return;
    _uid = uid;
    _userKv
      ..clear()
      ..addAll(await _backend.loadUserKv(uid));
    _lists.clear();
    for (final key in collections.keys) {
      _lists[key] = await _backend.loadList(uid, key);
    }
  }

  Future<void> closeUser() async {
    _uid = null;
    _userKv.clear();
    _lists.clear();
  }

  T? read<T>(String key) => _userKv[key] as T?;

  Future<void> write(String key, Object? value) async {
    final uid = _uid;
    if (uid == null) return;
    _userKv[key] = value;
    await _backend.putUserKv(uid, key, value);
    onUserChange?.call(uid, key, value);
  }

  List<Map<String, dynamic>> readList(String key) =>
      [for (final m in _lists[key] ?? const <Map<String, dynamic>>[]) Map<String, dynamic>.from(m)];

  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    final uid = _uid;
    if (uid == null) return;
    _lists[key] = items;
    if (collections.containsKey(key)) {
      await _backend.replaceList(uid, key, items);
    } else {
      await _backend.putUserKv(uid, key, items);
    }
    onUserChange?.call(uid, key, items);
  }

  Map<String, dynamic>? readMap(String key) {
    final v = _userKv[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> writeMap(String key, Map<String, dynamic> map) => write(key, map);

  Future<void> clearUser() async {
    final uid = _uid;
    if (uid == null) return;
    _userKv.clear();
    for (final k in collections.keys) {
      _lists[k] = [];
    }
    await _backend.clearUser(uid);
  }

  /// Snapshot of everything stored for the open user (used by cloud sync).
  Map<String, Object?> exportUser() => {
        ..._userKv,
        for (final e in _lists.entries) e.key: e.value,
      };

  /// Replaces local data with merged data from the cloud, without echoing
  /// the change back to [onUserChange].
  Future<void> importUser(Map<String, Object?> data) async {
    final uid = _uid;
    if (uid == null) return;
    for (final e in data.entries) {
      if (collections.containsKey(e.key)) {
        final items = [for (final m in (e.value as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
        _lists[e.key] = items;
        await _backend.replaceList(uid, e.key, items);
      } else {
        _userKv[e.key] = e.value;
        await _backend.putUserKv(uid, e.key, e.value);
      }
    }
  }
}

/// App-wide settings (language, theme, session…). Same API as the Hive box it replaced.
class AppKv {
  AppKv._();
  final Map<String, Object?> _cache = {};
  late _Backend _backend;

  dynamic get(String key, {Object? defaultValue}) => _cache.containsKey(key) ? _cache[key] : defaultValue;

  Future<void> put(String key, Object? value) async {
    _cache[key] = value;
    await _backend.putAppKv(key, value);
  }

  Future<void> delete(String key) async {
    _cache.remove(key);
    await _backend.deleteAppKv(key);
  }

  Future<void> clear() async {
    _cache.clear();
    await _backend.clearAppKv();
  }
}

// ── Backends ───────────────────────────────────────────────────────────────
abstract class _Backend {
  Future<void> open();
  Future<void> close();
  Future<Map<String, Object?>> loadAppKv();
  Future<void> putAppKv(String key, Object? value);
  Future<void> deleteAppKv(String key);
  Future<void> clearAppKv();
  Future<Map<String, Object?>> loadUserKv(String uid);
  Future<void> putUserKv(String uid, String key, Object? value);
  Future<List<Map<String, dynamic>>> loadList(String uid, String key);
  Future<void> replaceList(String uid, String key, List<Map<String, dynamic>> items);
  Future<void> clearUser(String uid);
}

class _SqliteBackend implements _Backend {
  final String path;
  final DatabaseFactory factory;
  late Database _db;
  _SqliteBackend(this.path, this.factory);

  static const _version = 1;

  @override
  Future<void> open() async {
    _db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: _version, onCreate: (db, v) => _create(db)));
  }

  static Future<void> _create(Database db) async {
    final b = db.batch()
      ..execute('CREATE TABLE app_kv (key TEXT PRIMARY KEY, value TEXT)')
      ..execute('CREATE TABLE user_kv (uid TEXT NOT NULL, key TEXT NOT NULL, value TEXT, PRIMARY KEY (uid, key))');
    for (final table in StorageService.collections.values) {
      b.execute('''CREATE TABLE $table (
        uid TEXT NOT NULL,
        id TEXT NOT NULL,
        sort_at TEXT,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (uid, id))''');
      b.execute('CREATE INDEX idx_${table}_sort ON $table (uid, sort_at)');
    }
    await b.commit(noResult: true);
  }

  @override
  Future<void> close() => _db.close();

  Future<int> count(String table, String uid) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM $table WHERE uid = ?', [uid]);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> rows(String table, String uid, int limit) => table == 'user_kv'
      ? _db.rawQuery('SELECT key, value FROM user_kv WHERE uid = ?', [uid])
      : _db.rawQuery(
          'SELECT id, sort_at, data, updated_at FROM $table WHERE uid = ? ORDER BY sort_at LIMIT ?', [uid, limit]);

  @override
  Future<Map<String, Object?>> loadAppKv() async => {
        for (final r in await _db.query('app_kv')) r['key'] as String: _decode(r['value']),
      };

  @override
  Future<void> putAppKv(String key, Object? value) =>
      _db.insert('app_kv', {'key': key, 'value': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteAppKv(String key) => _db.delete('app_kv', where: 'key = ?', whereArgs: [key]);

  @override
  Future<void> clearAppKv() => _db.delete('app_kv');

  @override
  Future<Map<String, Object?>> loadUserKv(String uid) async => {
        for (final r in await _db.query('user_kv', where: 'uid = ?', whereArgs: [uid]))
          r['key'] as String: _decode(r['value']),
      };

  @override
  Future<void> putUserKv(String uid, String key, Object? value) => _db.insert(
      'user_kv', {'uid': uid, 'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<List<Map<String, dynamic>>> loadList(String uid, String key) async {
    final rows = await _db.query(StorageService.collections[key]!,
        where: 'uid = ?', whereArgs: [uid], orderBy: 'sort_at, id');
    return [for (final r in rows) Map<String, dynamic>.from(jsonDecode(r['data'] as String))];
  }

  @override
  Future<void> replaceList(String uid, String key, List<Map<String, dynamic>> items) async {
    final table = StorageService.collections[key]!;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((tx) async {
      await tx.delete(table, where: 'uid = ?', whereArgs: [uid]);
      final b = tx.batch();
      for (final m in items) {
        b.insert(table, {
          'uid': uid,
          'id': m['id'] as String,
          // Lets SQL sort by time: tasks/sessions by start, daily tasks by date.
          'sort_at': (m['start'] ?? m['date'] ?? m['createdAt'] ?? '') as String,
          'data': jsonEncode(m),
          'updated_at': now,
        });
      }
      await b.commit(noResult: true);
    });
  }

  @override
  Future<void> clearUser(String uid) async {
    await _db.transaction((tx) async {
      await tx.delete('user_kv', where: 'uid = ?', whereArgs: [uid]);
      for (final t in StorageService.collections.values) {
        await tx.delete(t, where: 'uid = ?', whereArgs: [uid]);
      }
    });
  }

  static Object? _decode(Object? raw) => raw == null ? null : jsonDecode(raw as String);
}

/// Browser / test backend. Keeps the original Hive layout so existing web data still loads.
class _HiveBackend implements _Backend {
  late Box _app;
  Box? _user;

  @override
  Future<void> open() async => _app = await Hive.openBox('studysync_app');

  @override
  Future<void> close() async {
    await _user?.close();
    await _app.close();
  }

  @override
  Future<Map<String, Object?>> loadAppKv() async => {for (final k in _app.keys) k.toString(): _app.get(k)};

  @override
  Future<void> putAppKv(String key, Object? value) => _app.put(key, value);

  @override
  Future<void> deleteAppKv(String key) => _app.delete(key);

  @override
  Future<void> clearAppKv() async => _app.clear();

  Future<Box> _box(String uid) async {
    if (_user?.name == 'ss_user_$uid' && _user!.isOpen) return _user!;
    await _user?.close();
    return _user = await Hive.openBox('ss_user_$uid');
  }

  @override
  Future<Map<String, Object?>> loadUserKv(String uid) async {
    final box = await _box(uid);
    final out = <String, Object?>{};
    for (final k in box.keys) {
      if (StorageService.collections.containsKey(k)) continue;
      final v = box.get(k);
      // Older builds stored maps/lists as JSON strings.
      out[k.toString()] = v is String && (v.startsWith('{') || v.startsWith('[')) ? jsonDecode(v) : v;
    }
    return out;
  }

  @override
  Future<void> putUserKv(String uid, String key, Object? value) async =>
      (await _box(uid)).put(key, value is Map || value is List ? jsonEncode(value) : value);

  @override
  Future<List<Map<String, dynamic>>> loadList(String uid, String key) async {
    final raw = (await _box(uid)).get(key);
    if (raw is! String) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Future<void> replaceList(String uid, String key, List<Map<String, dynamic>> items) async =>
      (await _box(uid)).put(key, jsonEncode(items));

  @override
  Future<void> clearUser(String uid) async => (await _box(uid)).clear();
}
