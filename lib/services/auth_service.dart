import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/models.dart';
import 'storage_service.dart';

/// Local account store. Passwords are salted + SHA-256 hashed, never stored
/// in plain text. Works offline on Android, iOS and web.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _store = StorageService.instance;

  Map<String, dynamic> get _users =>
      Map<String, dynamic>.from(jsonDecode(_store.app.get('users', defaultValue: '{}')));

  Future<void> _saveUsers(Map<String, dynamic> u) => _store.app.put('users', jsonEncode(u));

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  String _salt() {
    final r = Random.secure();
    return base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
  }

  AppUser? restore() {
    final uid = _store.app.get('session_uid') as String?;
    if (uid == null) return null;
    if (uid == 'guest') return guestUser;
    for (final e in _users.entries) {
      final u = Map<String, dynamic>.from(e.value);
      if (u['id'] == uid) return AppUser(id: uid, name: u['name'], email: e.key);
    }
    return null;
  }

  static const guestUser = AppUser(id: 'guest', name: 'Guest', email: '', isGuest: true);

  Future<(AppUser?, String?)> register(String name, String email, String password) async {
    final e = email.trim().toLowerCase();
    if (name.trim().length < 2) return (null, 'name');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return (null, 'email');
    if (password.length < 6) return (null, 'password');
    final users = _users;
    if (users.containsKey(e)) return (null, 'exists');
    final salt = _salt();
    final id = 'u${DateTime.now().millisecondsSinceEpoch}';
    users[e] = {'id': id, 'name': name.trim(), 'salt': salt, 'hash': _hash(password, salt)};
    await _saveUsers(users);
    await _store.app.put('session_uid', id);
    return (AppUser(id: id, name: name.trim(), email: e), null);
  }

  Future<(AppUser?, String?)> signIn(String email, String password) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || password.isEmpty) return (null, 'empty');
    final raw = _users[e];
    if (raw == null) return (null, 'notfound');
    final u = Map<String, dynamic>.from(raw);
    if (_hash(password, u['salt']) != u['hash']) return (null, 'wrong');
    await _store.app.put('session_uid', u['id']);
    return (AppUser(id: u['id'], name: u['name'], email: e), null);
  }

  Future<AppUser> continueAsGuest() async {
    await _store.app.put('session_uid', 'guest');
    return guestUser;
  }

  Future<void> signOut() => _store.app.delete('session_uid');
}
