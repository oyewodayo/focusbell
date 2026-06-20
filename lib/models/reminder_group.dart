// models/reminder_group.dart — NEW FILE

import 'package:flutter/material.dart';

class ReminderGroup {
  final String id;
  final String name;
  final Color  color;
  final String emoji;
  final int    sortOrder;

  const ReminderGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.emoji,
    this.sortOrder = 0,
  });

  ReminderGroup copyWith({
    String? name,
    Color?  color,
    String? emoji,
    int?    sortOrder,
  }) => ReminderGroup(
    id:        id,
    name:      name      ?? this.name,
    color:     color     ?? this.color,
    emoji:     emoji     ?? this.emoji,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  // ── Default groups ────────────────────────────────────────────

  static const List<ReminderGroup> defaults = [
    ReminderGroup(
      id: 'work', name: 'Work',
      color: Color(0xFF0A84FF), emoji: '💼', sortOrder: 0,
    ),
    ReminderGroup(
      id: 'health', name: 'Health',
      color: Color(0xFF30D158), emoji: '💊', sortOrder: 1,
    ),
    ReminderGroup(
      id: 'personal', name: 'Personal',
      color: Color(0xFFFF9F0A), emoji: '🏠', sortOrder: 2,
    ),
    ReminderGroup(
      id: 'shopping', name: 'Shopping',
      color: Color(0xFFFF453A), emoji: '🛒', sortOrder: 3,
    ),
    ReminderGroup(
      id: 'family', name: 'Family',
      color: Color(0xFFBF5AF2), emoji: '👨‍👩‍👧', sortOrder: 4,
    ),
    ReminderGroup(
      id: 'fitness', name: 'Fitness',
      color: Color(0xFFFF6B35), emoji: '🏋️', sortOrder: 5,
    ),
    ReminderGroup(
      id: 'travel', name: 'Travel',
      color: Color(0xFF5E5CE6), emoji: '✈️', sortOrder: 6,
    ),
    ReminderGroup(
      id: 'finance', name: 'Finance',
      color: Color(0xFF00C7BE), emoji: '💰', sortOrder: 7,
    ),
    ReminderGroup(
      id: 'education', name: 'Education',
      color: Color(0xFFFFD60A), emoji: '🎓', sortOrder: 8,
    ),
    ReminderGroup(
      id: 'entertainment', name: 'Entertainment',
      color: Color(0xFFFF2D55), emoji: '🎬', sortOrder: 9,
    ),
    ReminderGroup(
      id: 'social', name: 'Social',
      color: Color(0xFF5AC8FA), emoji: '👥', sortOrder: 10,
    ),
    ReminderGroup(
      id: 'misc', name: 'Miscellaneous',
      color: Color(0xFF8E8E93), emoji: '📦', sortOrder: 11,
    ),
  ];

  // ── Serialisation ─────────────────────────────────────────────

  Map<String, dynamic> toRow() => {
    'id':         id,
    'name':       name,
    'color_hex':  color.value.toRadixString(16).padLeft(8, '0'),
    'emoji':      emoji,
    'sort_order': sortOrder,
  };

  factory ReminderGroup.fromRow(Map<String, dynamic> r) => ReminderGroup(
    id:        r['id']        as String,
    name:      r['name']      as String,
    color:     Color(int.parse(r['color_hex'] as String, radix: 16)),
    emoji:     r['emoji']     as String,
    sortOrder: r['sort_order'] as int? ?? 0,
  );
}