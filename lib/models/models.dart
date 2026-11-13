import 'package:flutter/material.dart';

enum Difficulty { easy, medium, hard }

enum TaskStatus { pending, completed, missed, skipped }

/// Kind of study block — drives the spaced-repetition cycle in the AI planner.
enum SessionType { learn, practice, review, pastPaper, finalRevision, custom }

/// Preferred part of the day for studying.
enum StudyWindow { morning, afternoon, evening, night }

/// How the on-device AI shapes a plan.
enum PlanMode { balanced, examFocus, light }

extension DifficultyX on Difficulty {
  int get weight => index + 1;
}

extension StudyWindowX on StudyWindow {
  int get startHour => const [6, 13, 17, 20][index];
}

/// Icons available for subjects. Kept as a const map so icon tree-shaking works.
const subjectIcons = <String, IconData>{
  'code': Icons.code_rounded,
  'network': Icons.hub_rounded,
  'math': Icons.functions_rounded,
  'science': Icons.science_rounded,
  'book': Icons.menu_book_rounded,
  'phone': Icons.smartphone_rounded,
  'db': Icons.storage_rounded,
  'design': Icons.palette_rounded,
  'language': Icons.translate_rounded,
  'business': Icons.business_center_rounded,
  'security': Icons.shield_rounded,
  'cloud': Icons.cloud_rounded,
  'ai': Icons.psychology_rounded,
  'chart': Icons.insights_rounded,
  'globe': Icons.public_rounded,
  'gear': Icons.settings_suggest_rounded,
};

class Subject {
  final String id;
  String name;
  int colorValue;
  String icon;
  Difficulty difficulty;
  DateTime? examDate;
  int targetHours;

  Subject({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    this.difficulty = Difficulty.medium,
    this.examDate,
    this.targetHours = 20,
  });

  Color get color => Color(colorValue);
  IconData get iconData => subjectIcons[icon] ?? Icons.menu_book_rounded;

  /// Whole days until the exam (null if no exam is set).
  int? get daysToExam {
    if (examDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(examDate!.year, examDate!.month, examDate!.day);
    return exam.difference(today).inDays;
  }

  bool get examPassed => (daysToExam ?? 1) < 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'icon': icon,
        'difficulty': difficulty.name,
        'examDate': examDate?.toIso8601String(),
        'targetHours': targetHours,
      };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'],
        name: j['name'],
        colorValue: j['color'],
        icon: j['icon'] ?? 'book',
        difficulty: Difficulty.values.firstWhere((d) => d.name == j['difficulty'],
            orElse: () => Difficulty.medium),
        examDate: j['examDate'] != null ? DateTime.tryParse(j['examDate']) : null,
        targetHours: j['targetHours'] ?? 20,
      );
}

class StudyTask {
  final String id;
  String subjectId;
  String title;
  SessionType type;
  DateTime start;
  int durationMinutes;
  TaskStatus status;
  bool aiGenerated;
  int rescheduleCount;
  String notes;
  DateTime? completedAt;

  StudyTask({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.start,
    required this.durationMinutes,
    this.type = SessionType.custom,
    this.status = TaskStatus.pending,
    this.aiGenerated = false,
    this.rescheduleCount = 0,
    this.notes = '',
    this.completedAt,
  });

  DateTime get end => start.add(Duration(minutes: durationMinutes));
  bool get isOverdue => status == TaskStatus.pending && end.isBefore(DateTime.now());
  bool get isDone => status == TaskStatus.completed;

  StudyTask copy() => StudyTask.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'title': title,
        'type': type.name,
        'start': start.toIso8601String(),
        'duration': durationMinutes,
        'status': status.name,
        'ai': aiGenerated,
        'resched': rescheduleCount,
        'notes': notes,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory StudyTask.fromJson(Map<String, dynamic> j) => StudyTask(
        id: j['id'],
        subjectId: j['subjectId'],
        title: j['title'],
        type: SessionType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => SessionType.custom),
        start: DateTime.parse(j['start']),
        durationMinutes: j['duration'],
        status: TaskStatus.values.firstWhere((s) => s.name == j['status'],
            orElse: () => TaskStatus.pending),
        aiGenerated: j['ai'] ?? false,
        rescheduleCount: j['resched'] ?? 0,
        notes: j['notes'] ?? '',
        completedAt:
            j['completedAt'] != null ? DateTime.tryParse(j['completedAt']) : null,
      );
}

/// A block of actual study time — logged by the focus timer or by completing a task.
class StudySession {
  final String id;
  final String subjectId;
  final String? taskId;
  final DateTime start;
  final int minutes;
  final int? focusRating; // 1–5, self-reported after a focus session

  const StudySession({
    required this.id,
    required this.subjectId,
    required this.start,
    required this.minutes,
    this.taskId,
    this.focusRating,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'taskId': taskId,
        'start': start.toIso8601String(),
        'minutes': minutes,
        'rating': focusRating,
      };

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: j['id'],
        subjectId: j['subjectId'],
        taskId: j['taskId'],
        start: DateTime.parse(j['start']),
        minutes: j['minutes'],
        focusRating: j['rating'],
      );
}

/// User inputs the proposal asks for: available time, study goals and preferences.
class StudyPreferences {
  /// Available study minutes per weekday, index 0 = Monday … 6 = Sunday.
  List<int> availability;
  StudyWindow window;
  int sessionMinutes;
  int breakMinutes;
  int dailyGoalMinutes;
  int planHorizonDays;
  bool remindersOn;
  int reminderLeadMinutes;
  bool dailyDigestOn;
  int dailyDigestHour;
  PlanMode planMode;

  StudyPreferences({
    List<int>? availability,
    this.window = StudyWindow.morning,
    this.sessionMinutes = 50,
    this.breakMinutes = 10,
    this.dailyGoalMinutes = 180,
    this.planHorizonDays = 7,
    this.remindersOn = true,
    this.reminderLeadMinutes = 10,
    this.dailyDigestOn = true,
    this.dailyDigestHour = 7,
    this.planMode = PlanMode.balanced,
  }) : availability = availability ?? [180, 180, 180, 180, 150, 300, 240];

  int minutesFor(DateTime d) => availability[d.weekday - 1];
  int get weeklyMinutes => availability.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'availability': availability,
        'window': window.name,
        'session': sessionMinutes,
        'break': breakMinutes,
        'goal': dailyGoalMinutes,
        'horizon': planHorizonDays,
        'reminders': remindersOn,
        'lead': reminderLeadMinutes,
        'digest': dailyDigestOn,
        'digestHour': dailyDigestHour,
        'mode': planMode.name,
      };

  factory StudyPreferences.fromJson(Map<String, dynamic> j) => StudyPreferences(
        availability: (j['availability'] as List?)?.cast<int>(),
        window: StudyWindow.values.firstWhere((w) => w.name == j['window'],
            orElse: () => StudyWindow.morning),
        sessionMinutes: j['session'] ?? 50,
        breakMinutes: j['break'] ?? 10,
        dailyGoalMinutes: j['goal'] ?? 180,
        planHorizonDays: j['horizon'] ?? 7,
        remindersOn: j['reminders'] ?? true,
        reminderLeadMinutes: j['lead'] ?? 10,
        dailyDigestOn: j['digest'] ?? true,
        dailyDigestHour: j['digestHour'] ?? 7,
        planMode: PlanMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => PlanMode.balanced),
      );
}

/// One completed in-app evaluation survey (research Objective 3).
class SurveyResponse {
  final String id;
  final DateTime date;
  final List<int> sus; // 10 System Usability Scale items, 1–5
  final Map<String, int> research; // research-question items, 1–5
  final String language;
  final String comment;

  const SurveyResponse({
    required this.id,
    required this.date,
    required this.sus,
    required this.research,
    required this.language,
    required this.comment,
  });

  /// Standard SUS scoring → 0–100.
  double get susScore {
    var total = 0;
    for (var i = 0; i < sus.length; i++) {
      total += i.isEven ? sus[i] - 1 : 5 - sus[i];
    }
    return total * 2.5;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'sus': sus,
        'susScore': susScore,
        'research': research,
        'language': language,
        'comment': comment,
      };

  factory SurveyResponse.fromJson(Map<String, dynamic> j) => SurveyResponse(
        id: j['id'],
        date: DateTime.parse(j['date']),
        sus: (j['sus'] as List).cast<int>(),
        research: Map<String, int>.from(j['research'] ?? {}),
        language: j['language'] ?? 'EN',
        comment: j['comment'] ?? '',
      );
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final bool isGuest;
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.isGuest = false,
  });
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── Daily task management ────────────────────────────────────────────────

enum TaskPriority { low, medium, high }

enum TaskCategory { study, assignment, personal, health, errand, other }

enum Repeat { none, daily, weekdays, weekly }

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SubTask {
  String title;

  /// Days on which this step was ticked off (so repeating tasks reset each day).
  Set<String> doneDates;

  SubTask(this.title, [Set<String>? doneDates]) : doneDates = doneDates ?? {};

  bool doneOn(DateTime d) => doneDates.contains(dayKey(d));

  Map<String, dynamic> toJson() => {'title': title, 'done': doneDates.toList()};
  factory SubTask.fromJson(Map<String, dynamic> j) =>
      SubTask(j['title'], (j['done'] as List? ?? []).cast<String>().toSet());
}

/// A to-do in the student's day: assignments, errands, health, personal…
/// Separate from AI-planned study sessions ([StudyTask]).
class DailyTask {
  final String id;
  String title;
  String note;
  DateTime date; // the day it is due (or first day, for repeating tasks)
  int? dueMinutes; // time of day in minutes from midnight; null = any time
  TaskPriority priority;
  TaskCategory category;
  String? subjectId;
  Repeat repeat;
  bool remind;
  Set<String> doneDates;
  List<SubTask> subtasks;
  final DateTime createdAt;

  DailyTask({
    required this.id,
    required this.title,
    required DateTime date,
    this.note = '',
    this.dueMinutes,
    this.priority = TaskPriority.medium,
    this.category = TaskCategory.personal,
    this.subjectId,
    this.repeat = Repeat.none,
    this.remind = true,
    Set<String>? doneDates,
    List<SubTask>? subtasks,
    DateTime? createdAt,
  })  : date = dateOnly(date),
        doneDates = doneDates ?? {},
        subtasks = subtasks ?? [],
        createdAt = createdAt ?? DateTime.now();

  bool occursOn(DateTime d) {
    final day = dateOnly(d);
    if (day.isBefore(date)) return false;
    return switch (repeat) {
      Repeat.none => day == date,
      Repeat.daily => true,
      Repeat.weekdays => day.weekday <= 5,
      Repeat.weekly => day.weekday == date.weekday,
    };
  }

  bool doneOn(DateTime d) => doneDates.contains(dayKey(d));

  DateTime? dueOn(DateTime d) =>
      dueMinutes == null ? null : dateOnly(d).add(Duration(minutes: dueMinutes!));

  /// A one-off task from an earlier day that was never finished.
  bool isOverdue(DateTime today) =>
      repeat == Repeat.none && date.isBefore(dateOnly(today)) && !doneOn(date);

  int subtasksDoneOn(DateTime d) => subtasks.where((s) => s.doneOn(d)).length;

  DailyTask copy() => DailyTask.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'date': date.toIso8601String(),
        'due': dueMinutes,
        'priority': priority.name,
        'category': category.name,
        'subjectId': subjectId,
        'repeat': repeat.name,
        'remind': remind,
        'done': doneDates.toList(),
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory DailyTask.fromJson(Map<String, dynamic> j) => DailyTask(
        id: j['id'],
        title: j['title'],
        note: j['note'] ?? '',
        date: DateTime.parse(j['date']),
        dueMinutes: j['due'],
        priority: TaskPriority.values.firstWhere((p) => p.name == j['priority'], orElse: () => TaskPriority.medium),
        category: TaskCategory.values.firstWhere((c) => c.name == j['category'], orElse: () => TaskCategory.other),
        subjectId: j['subjectId'],
        repeat: Repeat.values.firstWhere((r) => r.name == j['repeat'], orElse: () => Repeat.none),
        remind: j['remind'] ?? true,
        doneDates: (j['done'] as List? ?? []).cast<String>().toSet(),
        subtasks: (j['subtasks'] as List? ?? []).map((s) => SubTask.fromJson(Map<String, dynamic>.from(s))).toList(),
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt']) : null,
      );
}
