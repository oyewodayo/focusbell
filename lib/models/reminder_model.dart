import 'package:flutter/foundation.dart';

enum RepeatMode {
  once,
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  String get label {
    switch (this) {
      case RepeatMode.once:      return 'Once';
      case RepeatMode.monday:    return 'Every Monday';
      case RepeatMode.tuesday:   return 'Every Tuesday';
      case RepeatMode.wednesday: return 'Every Wednesday';
      case RepeatMode.thursday:  return 'Every Thursday';
      case RepeatMode.friday:    return 'Every Friday';
      case RepeatMode.saturday:  return 'Every Saturday';
      case RepeatMode.sunday:    return 'Every Sunday';
    }
  }

  String get shortLabel {
    switch (this) {
      case RepeatMode.once:      return 'Once';
      case RepeatMode.monday:    return 'Mon';
      case RepeatMode.tuesday:   return 'Tue';
      case RepeatMode.wednesday: return 'Wed';
      case RepeatMode.thursday:  return 'Thu';
      case RepeatMode.friday:    return 'Fri';
      case RepeatMode.saturday:  return 'Sat';
      case RepeatMode.sunday:    return 'Sun';
    }
  }

  /// ISO weekday (1=Mon…7=Sun), null for Once
  int? get weekday {
    switch (this) {
      case RepeatMode.once:      return null;
      case RepeatMode.monday:    return DateTime.monday;
      case RepeatMode.tuesday:   return DateTime.tuesday;
      case RepeatMode.wednesday: return DateTime.wednesday;
      case RepeatMode.thursday:  return DateTime.thursday;
      case RepeatMode.friday:    return DateTime.friday;
      case RepeatMode.saturday:  return DateTime.saturday;
      case RepeatMode.sunday:    return DateTime.sunday;
    }
  }
}

enum ReminderPriority { low, normal, high }

/// A single reminder entry.
class Reminder {
  final String          id;
  final String          title;
  final DateTime        dateTime;
  final RepeatMode      repeat;
  final ReminderPriority priority;
  final String?         notes;

  const Reminder({
    required this.id,
    required this.title,
    required this.dateTime,
    this.repeat   = RepeatMode.once,
    this.priority = ReminderPriority.normal,
    this.notes,
  });

  /// Minutes until this reminder fires (negative = past).
  int get minutesFromNow =>
      dateTime.difference(DateTime.now()).inMinutes;

  bool get isPast => DateTime.now().isAfter(dateTime);

  bool get isRepeating => repeat != RepeatMode.once;

  /// For a repeating reminder, compute the next occurrence after [from].
  DateTime nextOccurrence([DateTime? from]) {
    from ??= DateTime.now();
    if (repeat == RepeatMode.once) return dateTime;

    final targetWeekday = repeat.weekday!;
    var candidate = DateTime(
      from.year, from.month, from.day,
      dateTime.hour, dateTime.minute,
    );
    // Advance until we land on the right weekday and it's in the future
    for (int i = 0; i < 8; i++) {
      if (candidate.weekday == targetWeekday &&
          candidate.isAfter(from)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Reminder copyWith({
    String?           id,
    String?           title,
    DateTime?         dateTime,
    RepeatMode?       repeat,
    ReminderPriority? priority,
    String?           notes,
  }) =>
      Reminder(
        id:       id       ?? this.id,
        title:    title    ?? this.title,
        dateTime: dateTime ?? this.dateTime,
        repeat:   repeat   ?? this.repeat,
        priority: priority ?? this.priority,
        notes:    notes    ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id':       id,
        'title':    title,
        'dateTime': dateTime.toIso8601String(),
        'repeat':   repeat.name,
        'priority': priority.name,
        'notes':    notes,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id:       j['id']    as String,
        title:    j['title'] as String,
        dateTime: DateTime.parse(j['dateTime'] as String),
        repeat:   RepeatMode.values.firstWhere(
          (e) => e.name == (j['repeat'] ?? 'once'),
          orElse: () => RepeatMode.once,
        ),
        priority: ReminderPriority.values.firstWhere(
          (e) => e.name == (j['priority'] ?? 'normal'),
          orElse: () => ReminderPriority.normal,
        ),
        notes: j['notes'] as String?,
      );
}