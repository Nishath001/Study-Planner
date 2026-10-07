import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Offline-first local storage (Hive). One box for app-wide settings and
/// accounts, plus one box per user so each student's data stays separate.
class StorageService {
  StorageService._();
  static final instance = StorageService._();

  late Box _app;
  Box? _user;

  Future<void> init() async {
    await Hive.initFlutter();
    _app = await Hive.openBox('studysync_app');
  }

  Box get app => _app;

  Future<void> openUser(String uid) async {
    if (_user?.name == 'ss_user_$uid' && _user!.isOpen) return;
    await _user?.close();
    _user = await Hive.openBox('ss_user_$uid');
  }

  Future<void> closeUser() async {
    await _user?.close();
    _user = null;
  }

  T? read<T>(String key) => _user?.get(key) as T?;
  Future<void> write(String key, Object? value) async => _user?.put(key, value);

  List<Map<String, dynamic>> readList(String key) {
    final raw = _user?.get(key);
    if (raw is! String) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> items) async =>
      _user?.put(key, jsonEncode(items));

  Map<String, dynamic>? readMap(String key) {
    final raw = _user?.get(key);
    if (raw is! String) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeMap(String key, Map<String, dynamic> map) async =>
      _user?.put(key, jsonEncode(map));

  Future<void> clearUser() async => _user?.clear();
}
