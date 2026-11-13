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

  /// Number of security questions offered (texts live in the UI, bilingual).
  static const questionCount = 6;
  static const _maxAttempts = 5;
  static const _lockMinutes = 15;

  /// Answers are compared case- and space-insensitively.
  static String _normalise(String answer) => answer.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<(AppUser?, String?)> register(String name, String email, String password,
      {int? questionId, String answer = ''}) async {
    final e = email.trim().toLowerCase();
    if (name.trim().length < 2) return (null, 'name');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return (null, 'email');
    if (password.length < 6) return (null, 'password');
    if (questionId == null || questionId < 0 || questionId >= questionCount) return (null, 'question');
    if (_normalise(answer).length < 2) return (null, 'answer');
    final users = _users;
    if (users.containsKey(e)) return (null, 'exists');
    final salt = _salt();
    final id = 'u${DateTime.now().millisecondsSinceEpoch}';
    users[e] = {
      'id': id,
      'name': name.trim(),
      'salt': salt,
      'hash': _hash(password, salt),
      'q': questionId,
      'ahash': _hash(_normalise(answer), salt),
    };
    await _saveUsers(users);
    // No session yet: the student signs in with the new details next.
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

  // ── Forgot password (offline: security question) ──────────────────────
  /// The account's security question, or an error code:
  /// notfound | noquestion | email | locked:<minutes>.
  (int?, String?) recoveryQuestion(String email) {
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return (null, 'email');
    final raw = _users[e];
    if (raw == null) return (null, 'notfound');
    final u = Map<String, dynamic>.from(raw);
    final lock = _lockedFor(u);
    if (lock > 0) return (null, 'locked:$lock');
    if (u['q'] == null || u['ahash'] == null) return (null, 'noquestion');
    return (u['q'] as int, null);
  }

  /// Resets the password if the answer matches. Errors: notfound | noquestion |
  /// password | wrong_answer:<attemptsLeft> | locked:<minutes>.
  Future<String?> resetPassword(String email, String answer, String newPassword) async {
    final e = email.trim().toLowerCase();
    final users = _users;
    final raw = users[e];
    if (raw == null) return 'notfound';
    final u = Map<String, dynamic>.from(raw);
    if (u['ahash'] == null) return 'noquestion';
    final lock = _lockedFor(u);
    if (lock > 0) return 'locked:$lock';
    if (newPassword.length < 6) return 'password';
    if (_hash(_normalise(answer), u['salt']) != u['ahash']) {
      final attempts = (u['fails'] as int? ?? 0) + 1;
      if (attempts >= _maxAttempts) {
        u['fails'] = 0;
        u['lockUntil'] = DateTime.now().add(const Duration(minutes: _lockMinutes)).toIso8601String();
        users[e] = u;
        await _saveUsers(users);
        return 'locked:$_lockMinutes';
      }
      u['fails'] = attempts;
      users[e] = u;
      await _saveUsers(users);
      return 'wrong_answer:${_maxAttempts - attempts}';
    }
    // New salt for the new password; re-hash the answer with it.
    final salt = _salt();
    u
      ..['salt'] = salt
      ..['hash'] = _hash(newPassword, salt)
      ..['ahash'] = _hash(_normalise(answer), salt)
      ..remove('fails')
      ..remove('lockUntil');
    users[e] = u;
    await _saveUsers(users);
    return null;
  }

  bool hasRecovery(String email) => Map<String, dynamic>.from(_users[email.trim().toLowerCase()] ?? {})['ahash'] != null;

  int? questionOf(String email) => Map<String, dynamic>.from(_users[email.trim().toLowerCase()] ?? {})['q'] as int?;

  /// Signed-in students add or change their security question (password required).
  Future<String?> setRecovery(String email, String password, int questionId, String answer) async {
    final e = email.trim().toLowerCase();
    final users = _users;
    final raw = users[e];
    if (raw == null) return 'notfound';
    final u = Map<String, dynamic>.from(raw);
    if (_hash(password, u['salt']) != u['hash']) return 'wrong';
    if (questionId < 0 || questionId >= questionCount) return 'question';
    if (_normalise(answer).length < 2) return 'answer';
    u
      ..['q'] = questionId
      ..['ahash'] = _hash(_normalise(answer), u['salt']);
    users[e] = u;
    await _saveUsers(users);
    return null;
  }

  int _lockedFor(Map<String, dynamic> u) {
    final until = u['lockUntil'] == null ? null : DateTime.tryParse(u['lockUntil']);
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left <= 0 ? 0 : (left / 60).ceil();
  }

  Future<AppUser> continueAsGuest() async {
    await _store.app.put('session_uid', 'guest');
    return guestUser;
  }

  Future<void> signOut() => _store.app.delete('session_uid');
}
