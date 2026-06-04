import 'package:flutter/material.dart';

// ── Priority ──────────────────────────────────────────────────────

enum Priority {
  low,
  medium,
  high,
  critical;

  String get label => switch (this) {
        Priority.low      => 'Low',
        Priority.medium   => 'Medium',
        Priority.high     => 'High',
        Priority.critical => 'Critical',
      };

  String get emoji => switch (this) {
        Priority.low      => '🟢',
        Priority.medium   => '🟡',
        Priority.high     => '🟠',
        Priority.critical => '🔴',
      };

  Color get color => switch (this) {
        Priority.low      => const Color(0xFF4CAF50),
        Priority.medium   => const Color(0xFFFFCC00),
        Priority.high     => const Color(0xFFFF8C00),
        Priority.critical => const Color(0xFFFF3B30),
      };

  Color get bgColor => switch (this) {
        Priority.low      => const Color(0xFF1A2E1A),
        Priority.medium   => const Color(0xFF2E2A0A),
        Priority.high     => const Color(0xFF2E1A00),
        Priority.critical => const Color(0xFF2E0A0A),
      };
}

// ── ReminderOffset ────────────────────────────────────────────────

/// How far ahead of [Task.dueDate] the notification should fire.
enum ReminderOffset {
  atTime,
  fiveMin,
  fifteenMin,
  thirtyMin,
  oneHour;

  String get label => switch (this) {
        ReminderOffset.atTime      => 'At due time',
        ReminderOffset.fiveMin     => '5 min before',
        ReminderOffset.fifteenMin  => '15 min before',
        ReminderOffset.thirtyMin   => '30 min before',
        ReminderOffset.oneHour     => '1 hour before',
      };

  String get shortLabel => switch (this) {
        ReminderOffset.atTime      => 'At time',
        ReminderOffset.fiveMin     => '-5 min',
        ReminderOffset.fifteenMin  => '-15 min',
        ReminderOffset.thirtyMin   => '-30 min',
        ReminderOffset.oneHour     => '-1 hr',
      };

  Duration get offset => switch (this) {
        ReminderOffset.atTime      => Duration.zero,
        ReminderOffset.fiveMin     => const Duration(minutes: 5),
        ReminderOffset.fifteenMin  => const Duration(minutes: 15),
        ReminderOffset.thirtyMin   => const Duration(minutes: 30),
        ReminderOffset.oneHour     => const Duration(hours: 1),
      };
}

// ── TaskStatus ────────────────────────────────────────────────────

enum TaskStatus {
  todo,
  ongoing,
  blocked,
  completed;

  String get label => switch (this) {
        TaskStatus.todo      => 'To Do',
        TaskStatus.ongoing   => 'Ongoing',
        TaskStatus.blocked   => 'Blocked',
        TaskStatus.completed => 'Done',
      };

  String get emoji => switch (this) {
        TaskStatus.todo      => '⬜',
        TaskStatus.ongoing   => '🔵',
        TaskStatus.blocked   => '🔴',
        TaskStatus.completed => '✅',
      };

  Color get color => switch (this) {
        TaskStatus.todo      => const Color(0xFF8E8E93),
        TaskStatus.ongoing   => const Color(0xFF0A84FF),
        TaskStatus.blocked   => const Color(0xFFFF3B30),
        TaskStatus.completed => const Color(0xFF34C759),
      };

  Color get bgColor => switch (this) {
        TaskStatus.todo      => const Color(0xFF1C1C1E),
        TaskStatus.ongoing   => const Color(0xFF001A33),
        TaskStatus.blocked   => const Color(0xFF2E0A0A),
        TaskStatus.completed => const Color(0xFF0A2E14),
      };
}

// ── Task ──────────────────────────────────────────────────────────

class Task {
  final String id;
  final String title;
  final TaskStatus status;
  final DateTime createdAt;

  /// Optional due date/time. When set, a local notification is scheduled
  /// [reminderOffset] before this moment (unless the task is completed).
  final DateTime? dueDate;

  /// How early to fire the reminder notification relative to [dueDate].
  /// Defaults to [ReminderOffset.atTime].
  final ReminderOffset reminderOffset;

  /// Stable notification ID stored in the DB so we can cancel reliably
  /// without hash collisions. Assigned by [StorageService] on insert.
  final int? notifId;
  final String?   note;
  final DateTime? noteUpdatedAt;

  const Task({
    required this.id,
    required this.title,
    this.status          = TaskStatus.todo,
    required this.createdAt,
    this.dueDate,
    this.reminderOffset  = ReminderOffset.atTime,
    this.notifId,
    this.note,            // ← NEW
    this.noteUpdatedAt,   // ← NEW
  });
  // ── Derived helpers ──────────────────────────────────────────

  /// True when [dueDate] is in the past and the task is not completed.
  bool get isOverdue {
    if (dueDate == null || status == TaskStatus.completed) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// True when due within the next 24 hours (and not yet overdue).
  bool get isDueSoon {
    if (dueDate == null || status == TaskStatus.completed) return false;
    final now = DateTime.now();
    return dueDate!.isAfter(now) &&
        dueDate!.isBefore(now.add(const Duration(hours: 24)));
  }

  /// The exact moment the notification should fire.
  /// Returns null when [dueDate] is null.
  DateTime? get notificationFireTime =>
      dueDate?.subtract(reminderOffset.offset);

  // ── copyWith ─────────────────────────────────────────────────

  /// Pass [clearDueDate] = true to explicitly set [dueDate] to null.
 Task copyWith({
    String?        title,
    TaskStatus?    status,
    DateTime?      dueDate,
    bool           clearDueDate   = false,
    ReminderOffset? reminderOffset,
    int?           notifId,
    String?        note,
    bool           clearNote      = false,
    DateTime?      noteUpdatedAt,
  }) =>
      Task(
        id:             id,
        title:          title          ?? this.title,
        status:         status         ?? this.status,
        createdAt:      createdAt,
        dueDate:        clearDueDate ? null : (dueDate ?? this.dueDate),
        reminderOffset: reminderOffset ?? this.reminderOffset,
        notifId:        notifId        ?? this.notifId,
        note:           clearNote ? null : (note ?? this.note),
        noteUpdatedAt:  noteUpdatedAt  ?? this.noteUpdatedAt,
      );
  // ── Serialisation ─────────────────────────────────────────────

 Map<String, dynamic> toJson() => {
        'id':             id,
        'title':          title,
        'status':         status.index,
        'createdAt':      createdAt.toIso8601String(),
        'dueDate':        dueDate?.toIso8601String(),
        'reminderOffset': reminderOffset.index,
        'notifId':        notifId,
        'note':           note,
        'noteUpdatedAt':  noteUpdatedAt?.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id:             json['id']    as String,
        title:          json['title'] as String,
        status:         TaskStatus.values[json['status'] as int? ?? 0],
        createdAt:      DateTime.parse(json['createdAt'] as String),
        dueDate:        json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate'] as String),
        reminderOffset: ReminderOffset
            .values[json['reminderOffset'] as int? ?? 0],
        notifId:        json['notifId'] as int?,
        note:           json['note']          as String?,
        noteUpdatedAt:  json['noteUpdatedAt'] == null
            ? null
            : DateTime.tryParse(json['noteUpdatedAt'] as String),
      );
}

// ── Project ───────────────────────────────────────────────────────

class Project {
  final String id;
  final String name;
  final String description;
  final Priority priority;
  final bool isActive;
  final int sortOrder;
  final bool isArchived;
  final List<Task> tasks;
  final String?   note;
  final DateTime? noteUpdatedAt;
  final DateTime createdAt;

  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.priority,
    this.isActive = false,
    this.sortOrder = 0,
    this.isArchived = false,
    this.tasks = const [],
    this.note,            // ← NEW
    this.noteUpdatedAt, 
    required this.createdAt,
  });

  // ── Derived helpers ──────────────────────────────────────────

  /// True when any non-completed task is overdue.
  bool get hasOverdueTasks => tasks.any((t) => t.isOverdue);

  bool get hasNote => note != null && note!.isNotEmpty;

  /// Number of non-completed tasks that are overdue.
  int get overdueCount => tasks.where((t) => t.isOverdue).length;

  /// Number of non-completed tasks due within 24 hours.
  int get dueSoonCount => tasks.where((t) => t.isDueSoon).length;

  /// Earliest overdue task due date, or null.
  DateTime? get earliestOverdue {
    final overdue = tasks.where((t) => t.isOverdue).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return overdue.isEmpty ? null : overdue.first.dueDate;
  }

 Project copyWith({
    String?     name,
    String?     description,
    Priority?   priority,
    bool?       isActive,
    int?        sortOrder,
    bool?       isArchived,
    List<Task>? tasks,
    String?     note,
    bool        clearNote     = false,   // ← NEW: pass true to set note=null
    DateTime?   noteUpdatedAt,
  }) =>
      Project(
        id:            id,
        name:          name          ?? this.name,
        description:   description   ?? this.description,
        priority:      priority      ?? this.priority,
        isActive:      isActive      ?? this.isActive,
        sortOrder:     sortOrder     ?? this.sortOrder,
        createdAt:     createdAt,
        isArchived:    isArchived    ?? this.isArchived,
        tasks:         tasks         ?? this.tasks,
        note:          clearNote ? null : (note ?? this.note),
        noteUpdatedAt: noteUpdatedAt ?? this.noteUpdatedAt,
      );


  Map<String, dynamic> toJson() => {
        'id':            id,
        'name':          name,
        'description':   description,
        'priority':      priority.index,
        'isActive':      isActive,
        'sortOrder':     sortOrder,
        'createdAt':     createdAt.toIso8601String(),
        'tasks':         tasks.map((t) => t.toJson()).toList(),
        'note':          note,
        'noteUpdatedAt': noteUpdatedAt?.toIso8601String(),
      };

   factory Project.fromJson(Map<String, dynamic> json) => Project(
        id:            json['id']          as String,
        name:          json['name']        as String,
        description:   json['description'] as String? ?? '',
        priority:      Priority.values[json['priority'] as int],
        isActive:      json['isActive']    as bool? ?? false,
        sortOrder:     json['sort_order']  as int?  ?? 0,
        createdAt:     DateTime.parse(json['createdAt'] as String),
        tasks:         (json['tasks'] as List<dynamic>? ?? [])
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
        note:          json['note']          as String?,
        noteUpdatedAt: json['noteUpdatedAt'] == null
            ? null
            : DateTime.tryParse(json['noteUpdatedAt'] as String),
      );
}