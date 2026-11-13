import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/models.dart';
import 'storage_service.dart';

/// Firebase: Authentication (email + password, reset emails) and Cloud
/// Firestore backup/sync of each student's data.
///
/// SQLite stays the source of truth on the phone (works offline). Every local
/// write is pushed to Firestore (queued offline by the Firestore SDK); on
/// sign-in the cloud copy is merged in, so data follows the student to a new
/// phone. If Firebase isn't configured, [enabled] is false and the app keeps
/// using local accounts.
///
/// Firestore layout:
///   users/{uid}                     { name, email, kv: {prefs, flags, …}, updatedAt }
///   users/{uid}/{collection}/{id}   one document per subject / task / session / daily task / survey
class CloudService {
  CloudService._();
  static final instance = CloudService._();

  bool enabled = false;
  String? disabledReason;
  DateTime? lastSync;
  String? lastError;

  final _store = StorageService.instance;
  String? _uid;

  /// What was last uploaded, per collection: id → JSON. Used to send only changes.
  final Map<String, Map<String, String>> _pushed = {};
  final Map<String, String> _pushedKv = {};

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Firebase project the app is connected to (for the Database & Cloud screen).
  String? get projectId => enabled ? Firebase.app().options.projectId : null;
  String? get signedInUid => _uid;

  /// Number of documents per collection in Firestore for the signed-in student.
  Future<Map<String, int>> remoteCounts() async {
    final uid = _uid;
    if (!enabled || uid == null) return {};
    final ref = _db.collection('users').doc(uid);
    return {
      for (final key in StorageService.collections.keys)
        key: (await ref.collection(key).count().get().timeout(const Duration(seconds: 10))).count ?? 0,
    };
  }
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Wait for Firebase to restore a signed-in student from the last run.
      await _auth.authStateChanges().first.timeout(const Duration(seconds: 3), onTimeout: () => null);
      enabled = true;
    } catch (e) {
      enabled = false;
      disabledReason = e is UnsupportedError ? 'not_configured' : '$e';
      debugPrint('Firebase disabled: $e');
    }
  }

  // ── Authentication ───────────────────────────────────────────────────────
  AppUser? get currentUser {
    if (!enabled) return null;
    final u = _auth.currentUser;
    if (u == null) return null;
    return AppUser(id: u.uid, name: u.displayName ?? u.email?.split('@').first ?? 'Student', email: u.email ?? '');
  }

  /// Creates the account, then signs out so the student signs in next (same flow as offline mode).
  Future<String?> register(String name, String email, String password) async {
    if (name.trim().length < 2) return 'name';
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      await cred.user?.updateDisplayName(name.trim());
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _auth.signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      return authError(e.code);
    } catch (e) {
      return 'network';
    }
  }

  Future<(AppUser?, String?)> signIn(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) return (null, 'empty');
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return (currentUser, null);
    } on FirebaseAuthException catch (e) {
      return (null, authError(e.code));
    } catch (e) {
      return (null, 'network');
    }
  }

  /// Sends Firebase's password-reset email.
  Future<String?> sendPasswordReset(String email) async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) return 'email';
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return authError(e.code);
    } catch (e) {
      return 'network';
    }
  }

  Future<void> signOut() async {
    detach();
    if (enabled) await _auth.signOut();
  }

  /// Firebase error codes → the app's existing (bilingual) error messages.
  static String authError(String code) => switch (code) {
        'email-already-in-use' => 'exists',
        'invalid-email' => 'email',
        'weak-password' => 'password',
        'user-not-found' => 'notfound',
        'wrong-password' || 'invalid-credential' || 'INVALID_LOGIN_CREDENTIALS' => 'credentials',
        'network-request-failed' => 'network',
        'too-many-requests' => 'toomany',
        'user-disabled' => 'disabled',
        'operation-not-allowed' => 'notenabled',
        _ => 'unknown',
      };

  // ── Sync ─────────────────────────────────────────────────────────────────
  /// Merge cloud data into SQLite, then upload every later local change.
  Future<void> attach(String uid) async {
    if (!enabled) return;
    _uid = uid;
    _pushed.clear();
    _pushedKv.clear();
    await pull();
    _store.onUserChange = _onLocalChange;
  }

  void detach() {
    _store.onUserChange = null;
    _uid = null;
  }

  /// Download, merge with local, save to SQLite, upload anything the cloud lacks.
  Future<void> pull() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final userRef = _db.collection('users').doc(uid);
      final doc = await userRef.get().timeout(const Duration(seconds: 10));
      final remoteKv = Map<String, Object?>.from((doc.data()?['kv'] as Map?) ?? {});
      final remoteLists = <String, List<Map<String, dynamic>>>{};
      for (final key in StorageService.collections.keys) {
        final snap = await userRef.collection(key).get().timeout(const Duration(seconds: 10));
        remoteLists[key] = [for (final d in snap.docs) _fromFirestore(d.data())];
      }

      final local = _store.exportUser();
      final merged = <String, Object?>{};
      for (final key in StorageService.collections.keys) {
        final localList = [for (final m in (local[key] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
        merged[key] = mergeById(localList, remoteLists[key]!);
        _pushed[key] = {for (final m in remoteLists[key]!) m['id'] as String: jsonEncode(m)};
      }
      final localKv = {for (final e in local.entries) if (!StorageService.collections.containsKey(e.key)) e.key: e.value};
      merged.addAll(mergeKv(localKv, remoteKv));
      for (final e in remoteKv.entries) {
        _pushedKv[e.key] = jsonEncode(e.value);
      }

      await _store.importUser(merged);
      // Upload what only this phone had.
      for (final key in StorageService.collections.keys) {
        await _pushList(uid, key, merged[key] as List<Map<String, dynamic>>);
      }
      for (final e in merged.entries.where((e) => !StorageService.collections.containsKey(e.key))) {
        await _pushKv(uid, e.key, e.value);
      }
      lastSync = DateTime.now();
      lastError = null;
    } catch (e) {
      // Offline or rules not deployed: keep working locally, retry next sign-in / "Sync now".
      lastError = '$e';
      debugPrint('Cloud pull failed: $e');
    }
  }

  void _onLocalChange(String uid, String key, Object? value) {
    if (uid != _uid) return;
    final f = StorageService.collections.containsKey(key)
        ? _pushList(uid, key, [for (final m in value as List) Map<String, dynamic>.from(m as Map)])
        : _pushKv(uid, key, value);
    f.then((_) {
      lastSync = DateTime.now();
      lastError = null;
    }).catchError((Object e) {
      lastError = '$e';
      debugPrint('Cloud push failed: $e');
    });
  }

  Future<void> _pushList(String uid, String key, List<Map<String, dynamic>> items) async {
    final before = _pushed[key] ?? {};
    final now = {for (final m in items) m['id'] as String: jsonEncode(m)};
    final changed = [for (final e in now.entries) if (before[e.key] != e.value) e.key];
    final removed = [for (final id in before.keys) if (!now.containsKey(id)) id];
    if (changed.isEmpty && removed.isEmpty) return;
    _pushed[key] = now;
    final col = _db.collection('users').doc(uid).collection(key);
    final byId = {for (final m in items) m['id'] as String: m};
    // Firestore batches hold up to 500 writes.
    final ops = [...changed.map((id) => (id, true)), ...removed.map((id) => (id, false))];
    for (var i = 0; i < ops.length; i += 450) {
      final batch = _db.batch();
      for (final (id, set) in ops.skip(i).take(450)) {
        set ? batch.set(col.doc(id), _toFirestore(byId[id]!)) : batch.delete(col.doc(id));
      }
      await batch.commit();
    }
  }

  Future<void> _pushKv(String uid, String key, Object? value) async {
    final json = jsonEncode(value);
    if (_pushedKv[key] == json) return;
    _pushedKv[key] = json;
    await _db.collection('users').doc(uid).set({
      'kv': {key: value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> _toFirestore(Map<String, dynamic> m) => {...m, '_updatedAt': FieldValue.serverTimestamp()};

  static Map<String, dynamic> _fromFirestore(Map<String, dynamic> d) => Map<String, dynamic>.from(d)..remove('_updatedAt');

  /// Union by id. This phone's copy wins when both have the same item.
  static List<Map<String, dynamic>> mergeById(List<Map<String, dynamic>> local, List<Map<String, dynamic>> remote) {
    final ids = {for (final m in local) m['id']};
    return [...local, for (final m in remote) if (!ids.contains(m['id'])) m];
  }

  /// Settings: keep this phone's values, fill in anything only the cloud has.
  static Map<String, Object?> mergeKv(Map<String, Object?> local, Map<String, Object?> remote) =>
      {...remote, ...local};
}
