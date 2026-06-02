// models/focus_session.dart
//
// Data models for Focus Sessions (Pomodoro / Deep Work) and Analytics.
// Drop this file into lib/models/.

// ── Session type ──────────────────────────────────────────────────

enum SessionType {
  work,
  shortBreak,
  longBreak;

  String get label => switch (this) {
        SessionType.work       => 'Focus',
        SessionType.shortBreak => 'Short Break',
        SessionType.longBreak  => 'Long Break',
      };

  String get emoji => switch (this) {
        SessionType.work       => '🔴',
        SessionType.shortBreak => '🟢',
        SessionType.longBreak  => '🔵',
      };
}

// ── Timer preset ──────────────────────────────────────────────────

enum TimerPreset {
  pomodoro,
  deepWork,
  ultraFocus;

  String get label => switch (this) {
        TimerPreset.pomodoro   => 'Pomodoro',
        TimerPreset.deepWork   => 'Deep Work',
        TimerPreset.ultraFocus => 'Ultra Focus',
      };

  String get subtitle => switch (this) {
        TimerPreset.pomodoro   => '25 min work · 5 min break',
        TimerPreset.deepWork   => '50 min work · 10 min break',
        TimerPreset.ultraFocus => '90 min work · 20 min break',
      };

  int get workMinutes => switch (this) {
        TimerPreset.pomodoro   => 25,
        TimerPreset.deepWork   => 50,
        TimerPreset.ultraFocus => 90,
      };

  int get shortBreakMinutes => switch (this) {
        TimerPreset.pomodoro   => 5,
        TimerPreset.deepWork   => 10,
        TimerPreset.ultraFocus => 20,
      };

  int get longBreakMinutes => switch (this) {
        TimerPreset.pomodoro   => 15,
        TimerPreset.deepWork   => 30,
        TimerPreset.ultraFocus => 45,
      };

  /// Sessions before a long break kicks in.
  int get sessionsUntilLongBreak => switch (this) {
        TimerPreset.pomodoro   => 4,
        TimerPreset.deepWork   => 3,
        TimerPreset.ultraFocus => 2,
      };
}

// ── Focus session record ──────────────────────────────────────────

/// A single completed (or interrupted) timer session.
class FocusSession {
  final String      id;
  final String      projectId;
  final SessionType type;
  final TimerPreset preset;

  /// When the timer actually started.
  final DateTime startedAt;

  /// When the session ended (completed or abandoned).
  final DateTime endedAt;

  /// Planned duration in seconds (from the preset).
  final int plannedSeconds;

  /// Actual seconds the user was focused (≤ plannedSeconds).
  final int actualSeconds;

  /// True only when the user let the timer run to completion.
  final bool completed;

  const FocusSession({
    required this.id,
    required this.projectId,
    required this.type,
    required this.preset,
    required this.startedAt,
    required this.endedAt,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.completed,
  });

  // ── Derived ──────────────────────────────────────────────────

  Duration get duration => Duration(seconds: actualSeconds);

  /// Focus efficiency 0.0–1.0.
  double get efficiency =>
      plannedSeconds == 0 ? 0 : (actualSeconds / plannedSeconds).clamp(0, 1);

  // ── Serialisation ─────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':             id,
        'projectId':      projectId,
        'type':           type.index,
        'preset':         preset.index,
        'startedAt':      startedAt.toIso8601String(),
        'endedAt':        endedAt.toIso8601String(),
        'plannedSeconds': plannedSeconds,
        'actualSeconds':  actualSeconds,
        'completed':      completed ? 1 : 0,
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
        id:             json['id']             as String,
        projectId:      json['projectId']      as String,
        type:           SessionType.values[json['type'] as int],
        preset:         TimerPreset.values[json['preset'] as int],
        startedAt:      DateTime.parse(json['startedAt'] as String),
        endedAt:        DateTime.parse(json['endedAt']   as String),
        plannedSeconds: json['plannedSeconds'] as int,
        actualSeconds:  json['actualSeconds']  as int,
        completed:      (json['completed'] as int) == 1,
      );
}

// ── Analytics aggregates ──────────────────────────────────────────

/// Daily roll-up of focus time for one project.
class DailyFocusStat {
  final DateTime date;           // midnight-normalised
  final String   projectId;
  final int      totalSeconds;
  final int      completedSessions;
  final int      totalSessions;

  const DailyFocusStat({
    required this.date,
    required this.projectId,
    required this.totalSeconds,
    required this.completedSessions,
    required this.totalSessions,
  });

  Duration get totalDuration => Duration(seconds: totalSeconds);
  double   get completionRate =>
      totalSessions == 0 ? 0 : completedSessions / totalSessions;
}

/// Project-level summary over a given date range.
class ProjectFocusSummary {
  final String projectId;
  final String projectName;
  final int    totalFocusSeconds;
  final int    completedSessions;
  final int    totalSessions;
  final int    currentStreak;     // consecutive days with ≥1 completed session
  final int    longestStreak;
  final List<DailyFocusStat> dailyStats;

  const ProjectFocusSummary({
    required this.projectId,
    required this.projectName,
    required this.totalFocusSeconds,
    required this.completedSessions,
    required this.totalSessions,
    required this.currentStreak,
    required this.longestStreak,
    required this.dailyStats,
  });

  Duration get totalDuration => Duration(seconds: totalFocusSeconds);
  double   get completionRate =>
      totalSessions == 0 ? 0 : completedSessions / totalSessions;
}