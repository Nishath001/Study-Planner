import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

/// Automatic study reminders (local notifications, work offline).
/// On web this is a no-op; the in-app reminder centre still works.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const _channel = AndroidNotificationDetails(
    'study_reminders',
    'Study reminders',
    channelDescription: 'Reminders before planned study sessions',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Rebuilds every scheduled reminder from the current plan.
  Future<void> sync({
    required List<StudyTask> tasks,
    required Map<String, Subject> subjects,
    required StudyPreferences prefs,
    required String Function(String en, String si) t,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();

      if (prefs.remindersOn) {
        final upcoming = tasks
            .where((x) => x.status == TaskStatus.pending && x.start.isAfter(now))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        var id = 1;
        for (final task in upcoming.take(40)) {
          final at = task.start.subtract(Duration(minutes: prefs.reminderLeadMinutes));
          if (at.isBefore(now)) continue;
          await _schedule(
            id++,
            t('📚 Study session in ${prefs.reminderLeadMinutes} min',
                '📚 මිනිත්තු ${prefs.reminderLeadMinutes} කින් අධ්‍යයන සැසිය'),
            '${task.title} · ${task.durationMinutes} min',
            at,
          );
        }
      }

      if (prefs.dailyDigestOn) {
        for (var d = 0; d < 7; d++) {
          final day = dateOnly(now).add(Duration(days: d));
          final at = day.add(Duration(hours: prefs.dailyDigestHour));
          if (at.isBefore(now)) continue;
          final count = tasks
              .where((x) => sameDay(x.start, day) && x.status == TaskStatus.pending)
              .length;
          if (count == 0) continue;
          await _schedule(
            1000 + d,
            t('☀️ Your plan for today', '☀️ අද ඔබේ සැලැස්ම'),
            t('$count study sessions planned. Let\'s keep the streak going!',
                'අධ්‍යයන සැසි $count ක් සැලසුම් කර ඇත. දිගටම කරගෙන යමු!'),
            at,
          );
        }
      }
    } catch (e) {
      debugPrint('Notification sync failed: $e');
    }
  }

  Future<void> _schedule(int id, String title, String body, DateTime at) =>
      _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.UTC),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

  Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(0, title, body, _details);
  }
}
