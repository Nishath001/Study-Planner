import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

enum SuggestionType {
  examCoverage,
  rebalanceDay,
  moveToPeak,
  splitLong,
  neglectedSubject,
  shorterSessions,
  betterWindow,
}

/// One concrete change a suggestion makes when the student taps Apply.
class SuggestionAction {
  final String kind; // move | split | add | prefs
  final String? taskId;
  final DateTime? newStart;
  final int? newDuration;
  final DateTime? splitStart;
  final int? splitDuration;
  final StudyTask? newTask;
  final int? sessionMinutes;
  final StudyWindow? window;

  const SuggestionAction._(this.kind,
      {this.taskId, this.newStart, this.newDuration, this.splitStart, this.splitDuration,
      this.newTask, this.sessionMinutes, this.window});

  factory SuggestionAction.move(String id, DateTime to) => SuggestionAction._('move', taskId: id, newStart: to);
  factory SuggestionAction.split(String id, int firstMinutes, DateTime secondStart, int secondMinutes) =>
      SuggestionAction._('split', taskId: id, newDuration: firstMinutes, splitStart: secondStart, splitDuration: secondMinutes);
  factory SuggestionAction.add(StudyTask t) => SuggestionAction._('add', newTask: t);
  factory SuggestionAction.prefs({int? sessionMinutes, StudyWindow? window}) =>
      SuggestionAction._('prefs', sessionMinutes: sessionMinutes, window: window);
}

class Suggestion {
  final String id; // stable, so a dismissal sticks
  final SuggestionType type;
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String why; // the learned evidence behind it
  final double impact; // 0–1
  final List<SuggestionAction> actions;
  double score = 0;

  Suggestion({
    required this.id,
    required this.type,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.why,
    required this.impact,
    required this.actions,
  });
}

/// Accept / reject counts per suggestion type — the feedback the engine learns from.
class FeedbackStat {
  int accepted, rejected;
  FeedbackStat([this.accepted = 0, this.rejected = 0]);

  int get total => accepted + rejected;

  /// Beta(2,1) prior: new types start trusted, then follow the student's choices.
  double get acceptance => (accepted + 2) / (total + 3);

  List<int> toJson() => [accepted, rejected];
  factory FeedbackStat.fromJson(List v) => FeedbackStat(v[0] as int, v[1] as int);
}

/// What the engine has learned from the student's history.
class LearnedProfile {
  final Map<int, double> hourScore; // 0–1 per hour, shrunk toward 0.5 with little data
  final double hourEvidence;
  final double? focusSpan; // typical minutes per focus-timer session
  final int focusSamples;
  final Map<String, double> slipRate; // per subject

  LearnedProfile(this.hourScore, this.hourEvidence, this.focusSpan, this.focusSamples, this.slipRate);

  double scoreAt(int hour) => hourScore[hour] ?? 0.5;

  List<int> get peakHours {
    final h = hourScore.keys.where((k) => hourScore[k]! >= 0.6).toList()
      ..sort((a, b) => hourScore[b]!.compareTo(hourScore[a]!));
    return h.take(3).toList();
  }

  static LearnedProfile learn(List<StudyTask> tasks, List<StudySession> sessions, DateTime now) {
    // Beta counts per hour with recency weighting (≈ half-life of 3 weeks).
    final a = <int, double>{}, b = <int, double>{};
    void add(int hour, double success, DateTime when) {
      final w = pow(0.97, max(0, now.difference(when).inDays)).toDouble();
      a[hour] = (a[hour] ?? 0) + success * w;
      b[hour] = (b[hour] ?? 0) + (1 - success) * w;
    }

    final ratingByTask = {for (final s in sessions) if (s.taskId != null && s.focusRating != null) s.taskId!: s.focusRating!};
    for (final t in tasks) {
      if (t.status == TaskStatus.completed) {
        final r = ratingByTask[t.id];
        add(t.start.hour, r == null ? 1.0 : 0.4 + 0.6 * (r - 1) / 4, t.start);
      } else if (t.status == TaskStatus.missed || t.status == TaskStatus.skipped) {
        add(t.start.hour, 0, t.start);
      }
    }
    for (final s in sessions.where((s) => s.taskId == null && s.focusRating != null)) {
      add(s.start.hour, 0.4 + 0.6 * (s.focusRating! - 1) / 4, s.start);
    }
    final scores = <int, double>{};
    var evidence = 0.0;
    for (final h in {...a.keys, ...b.keys}) {
      final n = (a[h] ?? 0) + (b[h] ?? 0);
      evidence += n;
      final mean = ((a[h] ?? 0) + 1) / (n + 2);
      final conf = n / (n + 4);
      scores[h] = 0.5 * (1 - conf) + mean * conf;
    }

    // Real focus span: recent focus-timer sessions (these carry a rating).
    final timed = sessions.where((s) => s.focusRating != null).toList()..sort((x, y) => y.start.compareTo(x.start));
    final recent = timed.take(10).map((s) => s.minutes).toList();
    final span = recent.length >= 3 ? recent.reduce((x, y) => x + y) / recent.length : null;

    final slip = <String, double>{};
    final bySubject = <String, List<StudyTask>>{};
    for (final t in tasks.where((t) => t.status != TaskStatus.pending)) {
      bySubject.putIfAbsent(t.subjectId, () => []).add(t);
    }
    bySubject.forEach((id, list) {
      if (list.length >= 3) {
        slip[id] = list.where((t) => t.status != TaskStatus.completed).length / list.length;
      }
    });
    return LearnedProfile(scores, evidence, span, recent.length, slip);
  }
}

/// Analyses the plan and the student's history and proposes concrete,
/// one-tap improvements. Learns from accept / dismiss feedback: types the
/// student keeps rejecting are hidden, accepted ones rank higher.
class SuggestionEngine {
  static const _dayEndHour = 23;

  List<Suggestion> generate({
    required List<Subject> subjects,
    required List<StudyTask> tasks,
    required List<StudySession> sessions,
    required StudyPreferences prefs,
    required Map<SuggestionType, FeedbackStat> feedback,
    required Map<String, DateTime> dismissed,
    required String Function(String en, String si) t,
    required String Function(SessionType) typeLabel,
    DateTime? at,
    int limit = 6,
  }) {
    final now = at ?? DateTime.now();
    final profile = LearnedProfile.learn(tasks, sessions, now);
    final subjectById = {for (final s in subjects) s.id: s};
    final pending = tasks.where((x) => x.status == TaskStatus.pending && x.start.isAfter(now)).toList()
      ..sort((x, y) => x.start.compareTo(y.start));

    // Slots claimed by earlier suggestions, so suggestions never collide.
    final reserved = <StudyTask>[];
    final touched = <String>{};
    final out = <Suggestion>[];

    bool allowed(SuggestionType type, String id) {
      final f = feedback[type];
      if (f != null && f.total >= 3 && f.acceptance < 0.35) return false; // learned: not wanted
      final d = dismissed[id];
      return d == null || now.difference(d).inDays >= 7;
    }

    void emit(Suggestion s) {
      out.add(s);
      for (final a in s.actions) {
        if (a.taskId != null) touched.add(a.taskId!);
        if (a.kind == 'move') {
          final x = tasks.firstWhere((y) => y.id == a.taskId);
          reserved.add(x.copy()..start = a.newStart!);
        } else if (a.kind == 'split') {
          final x = tasks.firstWhere((y) => y.id == a.taskId);
          reserved.add(StudyTask.fromJson({...x.toJson(), 'id': '${x.id}-p1'})..durationMinutes = a.newDuration!);
          reserved.add(StudyTask.fromJson({...x.toJson(), 'id': '${x.id}-p2'})
            ..start = a.splitStart!
            ..durationMinutes = a.splitDuration!);
        } else if (a.kind == 'add') {
          reserved.add(a.newTask!);
        }
      }
    }

    // Busy = untouched pending tasks + where earlier suggestions put things.
    List<StudyTask> busy({String? except}) => [
          ...pending.where((x) => x.id != except && !touched.contains(x.id)),
          ...reserved.where((x) => x.id != except),
        ];

    DateTime? slot({
      required int minutes,
      required DateTime from,
      DateTime? before,
      List<int>? hours,
      String? except,
      int days = 7,
    }) {
      final taken = busy(except: except);
      for (var d = 0; d < days; d++) {
        final day = dateOnly(from).add(Duration(days: d));
        if (before != null && !day.isBefore(dateOnly(before))) break;
        final used = taken.where((x) => sameDay(x.start, day)).fold<int>(0, (s, x) => s + x.durationMinutes);
        if (used + minutes > prefs.minutesFor(day)) continue;
        final starts = hours != null
            ? hours.map((h) => day.add(Duration(hours: h))).toList()
            : [for (var m = prefs.window.startHour * 60; m <= (_dayEndHour * 60 - minutes); m += 15) day.add(Duration(minutes: m))];
        for (final s in starts) {
          if (!s.isAfter(from.add(const Duration(minutes: 14)))) continue;
          final e = s.add(Duration(minutes: minutes));
          if (e.hour >= _dayEndHour && e.minute > 0 || !sameDay(e, s)) continue;
          final clash = taken.any((x) =>
              s.isBefore(x.end.add(Duration(minutes: prefs.breakMinutes))) &&
              x.start.isBefore(e.add(Duration(minutes: prefs.breakMinutes))));
          if (!clash) return s;
        }
      }
      return null;
    }

    String hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';
    String pct(double v) => '${(v * 100).round()}%';

    // 1. Exam coverage — a close exam with too little planned revision.
    for (final s in subjects.where((s) => s.daysToExam != null && s.daysToExam! >= 1 && s.daysToExam! <= 14)) {
      final id = 'coverage:${s.id}:${dateOnly(s.examDate!).toIso8601String()}';
      if (!allowed(SuggestionType.examCoverage, id)) continue;
      final planned = pending.where((x) => x.subjectId == s.id && x.start.isBefore(dateOnly(s.examDate!))).length;
      final studied = sessions.where((x) => x.subjectId == s.id).fold<int>(0, (a, x) => a + x.minutes);
      final remaining = s.targetHours * 60 - studied;
      final want = s.daysToExam! <= 3 ? 2 : 3;
      if (planned >= want || remaining < 60) continue;
      final adds = <SuggestionAction>[];
      for (var k = 0; k < min(2, want - planned); k++) {
        final at = slot(minutes: prefs.sessionMinutes, from: now, before: s.examDate,
                hours: profile.peakHours.isEmpty ? null : profile.peakHours) ??
            slot(minutes: prefs.sessionMinutes, from: now, before: s.examDate);
        if (at == null) break;
        final type = s.daysToExam! <= 3 ? SessionType.pastPaper : SessionType.review;
        final task = StudyTask(
          id: 'sg_${s.id}_${at.millisecondsSinceEpoch}',
          subjectId: s.id,
          title: '${s.name} · ${typeLabel(type)}',
          type: type,
          start: at,
          durationMinutes: prefs.sessionMinutes,
          aiGenerated: true,
        );
        adds.add(SuggestionAction.add(task));
        reserved.add(task);
      }
      reserved.removeWhere((x) => adds.any((a) => a.newTask == x)); // re-added by emit
      if (adds.isEmpty) continue;
      emit(Suggestion(
        id: id,
        type: SuggestionType.examCoverage,
        icon: Icons.event_note_rounded,
        color: AppColors.rose,
        title: t('Add revision for ${s.name}', '${s.name} සඳහා පුනරීක්ෂණ එක් කරන්න'),
        body: t('Exam in ${s.daysToExam} day${s.daysToExam == 1 ? '' : 's'} but only $planned session${planned == 1 ? '' : 's'} planned. Add ${adds.length} more in your free time.',
            'විභාගයට දින ${s.daysToExam} යි, නමුත් සැසි $planned ක් පමණි. ඔබේ නිදහස් කාලයට තවත් ${adds.length} ක් එක් කරන්න.'),
        why: t('${(remaining / 60).toStringAsFixed(1)}h of your ${s.targetHours}h target still left.',
            'ඉලක්ක පැය ${s.targetHours} න් පැය ${(remaining / 60).toStringAsFixed(1)} ක් ඉතිරියි.'),
        impact: min(1.0, 0.55 + 0.3 * (1 - s.daysToExam! / 14)),
        actions: adds,
      ));
    }

    // 2. Overloaded day — more planned than the student said they have.
    for (var d = 0; d < 7; d++) {
      final day = dateOnly(now).add(Duration(days: d));
      final list = pending.where((x) => sameDay(x.start, day) && !touched.contains(x.id)).toList();
      final load = list.fold<int>(0, (a, x) => a + x.durationMinutes);
      final free = prefs.minutesFor(day);
      if (list.isEmpty || load <= free + 15) continue;
      // Move the least urgent session: easiest subject, furthest exam.
      list.sort((x, y) {
        final sx = subjectById[x.subjectId], sy = subjectById[y.subjectId];
        final ux = (sx?.difficulty.index ?? 0) * 100 - (sx?.daysToExam ?? 99);
        final uy = (sy?.difficulty.index ?? 0) * 100 - (sy?.daysToExam ?? 99);
        return ux.compareTo(uy);
      });
      final victim = list.first;
      final id = 'rebalance:${victim.id}';
      if (!allowed(SuggestionType.rebalanceDay, id)) continue;
      final exam = subjectById[victim.subjectId]?.examDate;
      final at = slot(minutes: victim.durationMinutes, from: day.add(const Duration(days: 1)), before: exam, except: victim.id);
      if (at == null) continue;
      emit(Suggestion(
        id: id,
        type: SuggestionType.rebalanceDay,
        icon: Icons.balance_rounded,
        color: AppColors.amber,
        title: t('Lighten ${relativeDayLabel(day, now, t)}', '${relativeDayLabel(day, now, t)} සැහැල්ලු කරන්න'),
        body: t('${fmtMin(load)} planned but only ${fmtMin(free)} free. Move "${victim.title}" to ${weekdayLabel(at, t)} ${hhmm(at)}.',
            '${fmtMin(load)} ක් සැලසුම් කර ඇති නමුත් නිදහස් ${fmtMin(free)} පමණි. "${victim.title}" ${weekdayLabel(at, t)} ${hhmm(at)} ට ගෙනයන්න.'),
        why: t('Overbooked days are where sessions get missed.', 'අධික දිනවලදී සැසි මඟහැරේ.'),
        impact: min(1.0, 0.4 + (load - free) / max(free, 60) * 0.5),
        actions: [SuggestionAction.move(victim.id, at)],
      ));
    }

    // 3. Move important work to the hours where the student actually performs best.
    if (profile.hourEvidence >= 6 && profile.peakHours.isNotEmpty) {
      final best = profile.scoreAt(profile.peakHours.first);
      var count = 0;
      for (final x in pending.where((x) => x.start.difference(now).inDays < 7)) {
        if (count >= 2 || touched.contains(x.id)) continue;
        final s = subjectById[x.subjectId];
        if (s == null) continue;
        final important = s.difficulty == Difficulty.hard || (s.daysToExam ?? 99) <= 10;
        final here = profile.scoreAt(x.start.hour);
        if (!important || best - here < 0.2) continue;
        final id = 'peak:${x.id}';
        if (!allowed(SuggestionType.moveToPeak, id)) continue;
        final at = slot(minutes: x.durationMinutes, from: now, before: s.examDate, hours: profile.peakHours, except: x.id);
        if (at == null) continue;
        final gain = profile.scoreAt(at.hour) - here;
        if (gain < 0.15) continue;
        emit(Suggestion(
          id: id,
          type: SuggestionType.moveToPeak,
          icon: Icons.wb_sunny_rounded,
          color: AppColors.violet,
          title: t('Study ${s.name} at your best time', '${s.name} ඔබේ හොඳම වේලාවේ ඉගෙන ගන්න'),
          body: t('Move "${x.title}" from ${hhmm(x.start)} to ${weekdayLabel(at, t)} ${hhmm(at)}.',
              '"${x.title}" ${hhmm(x.start)} සිට ${weekdayLabel(at, t)} ${hhmm(at)} ට ගෙනයන්න.'),
          why: t('Your sessions around ${hourLabel(at.hour)} go ${pct(gain)} better than around ${hourLabel(x.start.hour)}.',
              '${hourLabel(at.hour)} පමණ ඔබේ සැසි ${hourLabel(x.start.hour)} ට වඩා ${pct(gain)} සාර්ථකයි.'),
          impact: min(1.0, gain * 1.6) * (s.difficulty == Difficulty.hard ? 1 : 0.8),
          actions: [SuggestionAction.move(x.id, at)],
        ));
        count++;
      }
    }

    // 4. Split sessions longer than the student's real focus span.
    final span = profile.focusSpan;
    if (span != null) {
      var count = 0;
      for (final x in pending) {
        if (count >= 2 || touched.contains(x.id) || x.durationMinutes < 50 || x.durationMinutes <= span * 1.4) continue;
        final id = 'split:${x.id}';
        if (!allowed(SuggestionType.splitLong, id)) continue;
        final first = max(25, (span / 5).round() * 5);
        final rest = x.durationMinutes - first;
        final s = subjectById[x.subjectId];
        // The first half stays where it is; it must count as busy while we place the second.
        reserved.add(StudyTask.fromJson({...x.toJson(), 'id': '${x.id}-p1'})..durationMinutes = first);
        final from = x.start.add(Duration(minutes: first + 60));
        final at = (profile.peakHours.isEmpty
                ? null
                : slot(minutes: rest, from: from, before: s?.examDate, hours: profile.peakHours, except: x.id)) ??
            slot(minutes: rest, from: from, before: s?.examDate, except: x.id);
        reserved.removeLast();
        if (at == null) continue;
        emit(Suggestion(
          id: id,
          type: SuggestionType.splitLong,
          icon: Icons.call_split_rounded,
          color: AppColors.teal,
          title: t('Split a long session', 'දිගු සැසියක් බෙදන්න'),
          body: t('"${x.title}" is ${fmtMin(x.durationMinutes)}. Keep $first min at ${hhmm(x.start)} and move $rest min to ${weekdayLabel(at, t)} ${hhmm(at)}.',
              '"${x.title}" ${fmtMin(x.durationMinutes)} කි. ${hhmm(x.start)} ට මිනිත්තු $first ක් තබා, මිනිත්තු $rest ක් ${weekdayLabel(at, t)} ${hhmm(at)} ට ගෙනයන්න.'),
          why: t('Your focus sessions last about ${span.round()} min on average.',
              'ඔබේ අවධාන සැසි සාමාන්‍යයෙන් මිනිත්තු ${span.round()} ක් පමණ වේ.'),
          impact: 0.35 + 0.35 * (profile.slipRate[x.subjectId] ?? 0),
          actions: [SuggestionAction.split(x.id, first, at, rest)],
        ));
        count++;
      }
    }

    // 5. A subject that hasn't been touched for a while.
    for (final s in subjects.where((s) => !s.examPassed)) {
      final last = sessions.where((x) => x.subjectId == s.id).fold<DateTime?>(null,
          (m, x) => m == null || x.start.isAfter(m) ? x.start : m);
      final idle = last == null ? null : now.difference(last).inDays;
      if (idle == null || idle < 5) continue;
      if (out.any((o) => o.id.startsWith('coverage:${s.id}'))) continue;
      final soon = pending.any((x) => x.subjectId == s.id && x.start.difference(now).inHours < 48);
      if (soon) continue;
      final id = 'neglected:${s.id}:${dateOnly(now).toIso8601String()}';
      if (!allowed(SuggestionType.neglectedSubject, id)) continue;
      final at = slot(minutes: prefs.sessionMinutes, from: now, before: s.examDate, days: 3);
      if (at == null) continue;
      emit(Suggestion(
        id: id,
        type: SuggestionType.neglectedSubject,
        icon: Icons.history_rounded,
        color: AppColors.sky,
        title: t('Revisit ${s.name}', '${s.name} නැවත බලන්න'),
        body: t('Add a ${prefs.sessionMinutes}-min review on ${weekdayLabel(at, t)} ${hhmm(at)} so it stays fresh.',
            '${weekdayLabel(at, t)} ${hhmm(at)} ට මිනිත්තු ${prefs.sessionMinutes} ක පුනරීක්ෂණයක් එක් කරන්න.'),
        why: t('Not studied for $idle days — spaced review prevents forgetting.',
            'දින $idle ක් ඉගෙන නොගත්තා — පරතර පුනරීක්ෂණය අමතක වීම වළක්වයි.'),
        impact: min(0.7, 0.3 + idle * 0.03),
        actions: [
          SuggestionAction.add(StudyTask(
            id: 'sg_${s.id}_${at.millisecondsSinceEpoch}',
            subjectId: s.id,
            title: '${s.name} · ${typeLabel(SessionType.review)}',
            type: SessionType.review,
            start: at,
            durationMinutes: prefs.sessionMinutes,
            aiGenerated: true,
          )),
        ],
      ));
    }

    // 6. Settings tuned to learned behaviour: session length.
    if (span != null && profile.focusSamples >= 4 && span < prefs.sessionMinutes * 0.8) {
      final options = [25, 45, 50, 60, 90].where((m) => m <= span + 5).toList();
      final target = options.isEmpty ? 25 : options.last;
      final id = 'session:$target';
      if (target < prefs.sessionMinutes && allowed(SuggestionType.shorterSessions, id)) {
        emit(Suggestion(
          id: id,
          type: SuggestionType.shorterSessions,
          icon: Icons.timer_outlined,
          color: AppColors.primary,
          title: t('Use $target-minute sessions', 'මිනිත්තු $target සැසි භාවිතා කරන්න'),
          body: t('Plan future sessions at $target min instead of ${prefs.sessionMinutes} min.',
              'ඉදිරි සැසි මිනිත්තු ${prefs.sessionMinutes} වෙනුවට $target ක් ලෙස සැලසුම් කරන්න.'),
          why: t('Your last ${profile.focusSamples} focus sessions averaged ${span.round()} min.',
              'ඔබේ අවසන් අවධාන සැසි ${profile.focusSamples} සාමාන්‍යය මිනිත්තු ${span.round()}.'),
          impact: 0.4,
          actions: [SuggestionAction.prefs(sessionMinutes: target)],
        ));
      }
    }

    // 7. Settings tuned to learned behaviour: preferred part of the day.
    if (profile.hourEvidence >= 10) {
      double windowScore(StudyWindow w) {
        final hours = switch (w) {
          StudyWindow.morning => [6, 7, 8, 9, 10, 11, 12],
          StudyWindow.afternoon => [13, 14, 15, 16],
          StudyWindow.evening => [17, 18, 19],
          StudyWindow.night => [20, 21, 22],
        };
        final known = hours.where(profile.hourScore.containsKey).toList();
        if (known.isEmpty) return -1;
        return known.map(profile.scoreAt).reduce((a, b) => a + b) / known.length;
      }

      final current = windowScore(prefs.window);
      final best = StudyWindow.values.reduce((a, b) => windowScore(a) >= windowScore(b) ? a : b);
      final id = 'window:${best.name}';
      if (best != prefs.window && current >= 0 && windowScore(best) - current >= 0.2 &&
          allowed(SuggestionType.betterWindow, id)) {
        final names = {
          StudyWindow.morning: t('mornings', 'උදෑසන'),
          StudyWindow.afternoon: t('afternoons', 'දහවල්'),
          StudyWindow.evening: t('evenings', 'සවස'),
          StudyWindow.night: t('nights', 'රාත්‍රී'),
        };
        emit(Suggestion(
          id: id,
          type: SuggestionType.betterWindow,
          icon: Icons.schedule_rounded,
          color: AppColors.green,
          title: t('Plan around ${names[best]}', '${names[best]} වටා සැලසුම් කරන්න'),
          body: t('Start future plans in the ${names[best]} instead of ${names[prefs.window]}.',
              'ඉදිරි සැලසුම් ${names[prefs.window]} වෙනුවට ${names[best]} ආරම්භ කරන්න.'),
          why: t('You complete and focus ${pct(windowScore(best) - current)} better in the ${names[best]}.',
              '${names[best]} ඔබ ${pct(windowScore(best) - current)} වඩා සාර්ථකයි.'),
          impact: min(0.8, 0.35 + windowScore(best) - current),
          actions: [SuggestionAction.prefs(window: best)],
        ));
      }
    }

    // Rank by expected benefit × how much this student values this kind of advice.
    for (final s in out) {
      s.score = s.impact * (feedback[s.type]?.acceptance ?? 2 / 3);
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  static String fmtMin(int m) => m < 60 ? '${m}m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m');
  static String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String weekdayLabel(DateTime d, String Function(String, String) t) {
    final diff = dateOnly(d).difference(dateOnly(DateTime.now())).inDays;
    if (diff == 0) return t('today', 'අද');
    if (diff == 1) return t('tomorrow', 'හෙට');
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const si = ['සඳුදා', 'අඟහරුවාදා', 'බදාදා', 'බ්‍රහස්පතින්දා', 'සිකුරාදා', 'සෙනසුරාදා', 'ඉරිදා'];
    return t(en[d.weekday - 1], si[d.weekday - 1]);
  }

  static String relativeDayLabel(DateTime d, DateTime now, String Function(String, String) t) {
    final diff = dateOnly(d).difference(dateOnly(now)).inDays;
    if (diff == 0) return t('today', 'අද');
    if (diff == 1) return t('tomorrow', 'හෙට');
    return weekdayLabel(d, t);
  }
}
