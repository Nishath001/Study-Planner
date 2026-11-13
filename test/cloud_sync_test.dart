import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/services/cloud_service.dart';

void main() {
  test('merge keeps everything from both phones, this phone wins on conflicts', () {
    final local = [
      {'id': 'a', 'title': 'Edited here'},
      {'id': 'b', 'title': 'Only here'},
    ];
    final remote = [
      {'id': 'a', 'title': 'Old cloud copy'},
      {'id': 'c', 'title': 'From other phone'},
    ];
    final merged = CloudService.mergeById(local, remote);
    expect(merged.map((m) => m['id']), ['a', 'b', 'c']);
    expect(merged.first['title'], 'Edited here');
  });

  test('new phone (empty) restores everything from the cloud', () {
    final remote = [
      {'id': 's1', 'name': 'Networks'},
      {'id': 's2', 'name': 'Databases'},
    ];
    expect(CloudService.mergeById([], remote), remote);
  });

  test('settings: phone values win, cloud fills the gaps', () {
    final merged = CloudService.mergeKv(
      {'prefs': {'session': 45}, 'setupDone': true},
      {'prefs': {'session': 50}, 'consent': true},
    );
    expect(merged, {'prefs': {'session': 45}, 'setupDone': true, 'consent': true});
  });

  test('Firebase errors map to the app\'s messages', () {
    expect(CloudService.authError('email-already-in-use'), 'exists');
    expect(CloudService.authError('invalid-email'), 'email');
    expect(CloudService.authError('weak-password'), 'password');
    expect(CloudService.authError('invalid-credential'), 'credentials');
    expect(CloudService.authError('wrong-password'), 'credentials');
    expect(CloudService.authError('network-request-failed'), 'network');
    expect(CloudService.authError('too-many-requests'), 'toomany');
    expect(CloudService.authError('operation-not-allowed'), 'notenabled');
    expect(CloudService.authError('something-new'), 'unknown');
  });
}
