import 'package:flutter/material.dart';

// ── Priority ──────────────────────────────────────────────────────

enum Priority {
  low,
  medium,
  high,
  critical;

  String get label {
    switch (this) {
      case Priority.low:      return 'Low';
      case Priority.medium:   return 'Medium';
      case Priority.high:     return 'High';
      case Priority.critical: return 'Critical';
    }
  }

  String get emoji {
    switch (this) {
      case Priority.low:      return '🟢';
      case Priority.medium:   return '🟡';
      case Priority.high:     return '🟠';
      case Priority.critical: return '🔴';
    }
  }

  Color get color {
    switch (this) {
      case Priority.low:      return const Color(0xFF4CAF50);
      case Priority.medium:   return const Color(0xFFFFCC00);
      case Priority.high:     return const Color(0xFFFF8C00);
      case Priority.critical: return const Color(0xFFFF3B30);
    }
  }

  Color get bgColor {
    switch (this) {
      case Priority.low:      return const Color(0xFF1A2E1A);
      case Priority.medium:   return const Color(0xFF2E2A0A);
      case Priority.high:     return const Color(0xFF2E1A00);
      case Priority.critical: return const Color(0xFF2E0A0A);
    }
  }
}

// ── Task status ───────────────────────────────────────────────────

enum TaskStatus {
  todo,
  ongoing,
  blocked,
  completed;

  String get label {
    switch (this) {
      case TaskStatus.todo:      return 'To Do';
      case TaskStatus.ongoing:   return 'Ongoing';
      case TaskStatus.blocked:   return 'Blocked';
      case TaskStatus.completed: return 'Done';
    }
  }

  String get emoji {
    switch (this) {
      case TaskStatus.todo:      return '⬜';
      case TaskStatus.ongoing:   return '🔵';
      case TaskStatus.blocked:   return '🔴';
      case TaskStatus.completed: return '✅';
    }
  }

  Color get color {
    switch (this) {
      case TaskStatus.todo:      return const Color(0xFF8E8E93);
      case TaskStatus.ongoing:   return const Color(0xFF0A84FF);
      case TaskStatus.blocked:   return const Color(0xFFFF3B30);
      case TaskStatus.completed: return const Color(0xFF34C759);
    }
  }

  Color get bgColor {
    switch (this) {
      case TaskStatus.todo:      return const Color(0xFF1C1C1E);
      case TaskStatus.ongoing:   return const Color(0xFF001A33);
      case TaskStatus.blocked:   return const Color(0xFF2E0A0A);
      case TaskStatus.completed: return const Color(0xFF0A2E14);
    }
  }
}

// ── Task ──────────────────────────────────────────────────────────

class Task {
  final String id;
  final String title;
  final TaskStatus status;
  final DateTime createdAt;

  const Task({
    required this.id,
    required this.title,
    this.status = TaskStatus.todo,
    required this.createdAt,
  });

  Task copyWith({String? title, TaskStatus? status}) => Task(
        id: id,
        title: title ?? this.title,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        status: TaskStatus.values[json['status'] as int? ?? 0],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ── Project ───────────────────────────────────────────────────────

class Project {
  final String id;
  final String name;
  final String description;
  final Priority priority;
  final bool isActive;
  final int      sortOrder; 
  final DateTime createdAt;
  final List<Task> tasks;

  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.priority,
    this.isActive = false,
    this.sortOrder = 0, 
    required this.createdAt,
    this.tasks = const [],
  });

  Project copyWith({
    String? name,
    String? description,
    Priority? priority,
    bool? isActive,
    int?      sortOrder,
    List<Task>? tasks,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        priority: priority ?? this.priority,
        isActive: isActive ?? this.isActive,
        sortOrder:   sortOrder   ?? this.sortOrder,
        createdAt: createdAt,
        tasks: tasks ?? this.tasks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'priority': priority.index,
        'isActive': isActive,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        description:
            json['description'] == null ? '' : json['description'] as String,
        priority: Priority.values[json['priority'] as int],
        isActive: json['isActive'] as bool? ?? false,
        sortOrder:   json['sort_order']  as int?  ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        tasks: (json['tasks'] as List<dynamic>? ?? [])
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}