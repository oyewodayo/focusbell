import 'package:flutter/material.dart';

enum Priority {
  low,
  medium,
  high,
  critical;

  String get label {
    switch (this) {
      case Priority.low:
        return 'Low';
      case Priority.medium:
        return 'Medium';
      case Priority.high:
        return 'High';
      case Priority.critical:
        return 'Critical';
    }
  }

  String get emoji {
    switch (this) {
      case Priority.low:
        return '🟢';
      case Priority.medium:
        return '🟡';
      case Priority.high:
        return '🟠';
      case Priority.critical:
        return '🔴';
    }
  }

  Color get color {
    switch (this) {
      case Priority.low:
        return const Color(0xFF4CAF50);
      case Priority.medium:
        return const Color(0xFFFFCC00);
      case Priority.high:
        return const Color(0xFFFF8C00);
      case Priority.critical:
        return const Color(0xFFFF3B30);
    }
  }

  Color get bgColor {
    switch (this) {
      case Priority.low:
        return const Color(0xFF1A2E1A);
      case Priority.medium:
        return const Color(0xFF2E2A0A);
      case Priority.high:
        return const Color(0xFF2E1A00);
      case Priority.critical:
        return const Color(0xFF2E0A0A);
    }
  }
}

class Project {
  final String id;
  final String name;
  final String description;
  final Priority priority;
  final bool isActive;
  final DateTime createdAt;

  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.priority,
    this.isActive = false,
    required this.createdAt,
  });

  Project copyWith({
    String? name,
    String? description,
    Priority? priority,
    bool? isActive,
  }) => Project(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'priority': priority.index,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] == null
        ? ''
        : json['description'] as String,
    priority: Priority.values[json['priority'] as int],
    isActive: json['isActive'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
