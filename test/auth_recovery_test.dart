import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:studysync/services/auth_service.dart';
import 'package:studysync/services/storage_service.dart';

void main() {
  final auth = AuthService.instance;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_auth');
    await StorageService.instance.initAt(dir.path);
    await StorageService.instance.app.clear();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> registerNimal() async {
    final (u, err) = await auth.register('Nimal Perera', 'nimal@test.lk', 'study123', questionId: 2, answer: 'Kandy');
    expect(err, isNull);
    expect(u, isNotNull);
  }

  test('registration requires a security question and answer', () async {
    expect((await auth.register('Ann', 'a@test.lk', 'secret1')).$2, 'question');
    expect((await auth.register('Ann', 'a@test.lk', 'secret1', questionId: 1, answer: ' ')).$2, 'answer');
  });

  test('registering does not sign the student in', () async {
    await registerNimal();
    expect(auth.restore(), isNull);
  });

  test('shows the right question; unknown email is reported', () async {
    await registerNimal();
    expect(auth.recoveryQuestion('NIMAL@test.lk '), (2, null));
    expect(auth.recoveryQuestion('nobody@test.lk').$2, 'notfound');
    expect(auth.recoveryQuestion('not-an-email').$2, 'email');
  });

  test('correct answer (any case / spacing) resets the password', () async {
    await registerNimal();
    expect(await auth.resetPassword('nimal@test.lk', '  kANDY ', 'newpass9'), isNull);
    expect((await auth.signIn('nimal@test.lk', 'study123')).$2, 'wrong');
    expect((await auth.signIn('nimal@test.lk', 'newpass9')).$1, isNotNull);
    // The answer still works for a later reset.
    expect(await auth.resetPassword('nimal@test.lk', 'Kandy', 'another1'), isNull);
  });

  test('wrong answers count down and then lock recovery', () async {
    await registerNimal();
    expect(await auth.resetPassword('nimal@test.lk', 'Galle', 'newpass9'), 'wrong_answer:4');
    for (var i = 0; i < 3; i++) {
      await auth.resetPassword('nimal@test.lk', 'Galle', 'newpass9');
    }
    expect(await auth.resetPassword('nimal@test.lk', 'Galle', 'newpass9'), 'locked:15');
    // Even the right answer is refused while locked, and the old password still works.
    expect(await auth.resetPassword('nimal@test.lk', 'Kandy', 'newpass9'), startsWith('locked'));
    expect(auth.recoveryQuestion('nimal@test.lk').$2, startsWith('locked'));
    expect((await auth.signIn('nimal@test.lk', 'study123')).$1, isNotNull);
  });

  test('new password must be at least 6 characters', () async {
    await registerNimal();
    expect(await auth.resetPassword('nimal@test.lk', 'Kandy', '123'), 'password');
  });

  test('older accounts without a question can add one after signing in', () async {
    // Simulate an account created before security questions existed.
    await registerNimal();
    final users = StorageService.instance.app.get('users') as String;
    await StorageService.instance.app.put('users', users.replaceAll(RegExp(r',"q":2,"ahash":"[0-9a-f]+"'), ''));
    expect(auth.recoveryQuestion('nimal@test.lk').$2, 'noquestion');

    expect(await auth.setRecovery('nimal@test.lk', 'wrongpass', 0, 'Royal'), 'wrong');
    expect(await auth.setRecovery('nimal@test.lk', 'study123', 0, 'Royal College'), isNull);
    expect(auth.recoveryQuestion('nimal@test.lk'), (0, null));
    expect(await auth.resetPassword('nimal@test.lk', 'royal college', 'newpass9'), isNull);
  });
}
