import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studysync/models/models.dart';
import 'package:studysync/services/storage_service.dart';
import 'package:studysync/state/app_state.dart';

/// Full app flow on real SQLite: data must survive sign-out and app restarts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final store = StorageService.instance;
  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_flow');
    dbPath = p.join(dir.path, 'studysync.db');
    await store.initSqliteAt(dbPath, databaseFactoryFfi);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  /// Like closing the app and opening it again: new state, storage re-opened from disk.
  Future<AppState> restart() async {
    await store.close();
    await store.initSqliteAt(dbPath, databaseFactoryFfi);
    final app = AppState();
    await app.boot();
    return app;
  }

  Subject subject(String id) => Subject(id: id, name: 'Networks', colorValue: 0, icon: 'book');

  test('account: data survives sign-out + restart + sign-in', () async {
    var app = AppState();
    await app.boot();
    expect(await app.register('Nimal Perera', 'nimal@test.lk', 'study123', questionId: 1, answer: 'Mr Silva'), isNull);
    expect(await app.signIn('nimal@test.lk', 'study123'), isNull);
    await app.upsertSubject(subject('s1'));
    await app.addQuickDaily('Submit lab report');
    await app.signOut();

    app = await restart();
    expect(app.user, isNull, reason: 'signed out stays signed out');
    expect(await app.signIn('nimal@test.lk', 'study123'), isNull);
    expect(app.subjects.map((s) => s.id), ['s1']);
    expect(app.dailyTasks.map((t) => t.title), ['Submit lab report']);
  });

  test('account: restart while signed in keeps the session and data', () async {
    var app = AppState();
    await app.boot();
    await app.register('Amaya Silva', 'amaya@test.lk', 'study123', questionId: 2, answer: 'Kandy');
    await app.signIn('amaya@test.lk', 'study123');
    await app.upsertSubject(subject('s1'));

    app = await restart();
    expect(app.user?.email, 'amaya@test.lk');
    expect(app.subjects, hasLength(1));
  });

  test('guest: data survives sign-out + restart + continue as guest', () async {
    var app = AppState();
    await app.boot();
    await app.continueAsGuest();
    await app.upsertSubject(subject('g1'));
    await app.signOut();

    app = await restart();
    await app.continueAsGuest();
    expect(app.subjects.map((s) => s.id), ['g1']);
  });

  test('two accounts on one phone keep separate data', () async {
    var app = AppState();
    await app.boot();
    await app.register('A Student', 'a@test.lk', 'study123', questionId: 0, answer: 'Royal');
    await app.register('B Student', 'b@test.lk', 'study123', questionId: 0, answer: 'Trinity');
    await app.signIn('a@test.lk', 'study123');
    await app.upsertSubject(subject('a1'));
    await app.signOut();
    await app.signIn('b@test.lk', 'study123');
    expect(app.subjects, isEmpty);
    await app.signOut();

    app = await restart();
    await app.signIn('a@test.lk', 'study123');
    expect(app.subjects.single.id, 'a1');
  });
}
