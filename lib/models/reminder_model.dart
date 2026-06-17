import 'package:flutter/foundation.dart';

/// Weekday constants matching DateTime.monday … DateTime.sunday (1–7).
class Weekday {
  static const int mon = DateTime.monday;    // 1
  static const int tue = DateTime.tuesday;   // 2
  static const int wed = DateTime.wednesday; // 3
  static const int thu = DateTime.thursday;  // 4
  static const int fri = DateTime.friday;    // 5
  static const int sat = DateTime.saturday;  // 6
  static const int sun = DateTime.sunday;    // 7

  static const List<int> ordered = [mon, tue, wed, thu, fri, sat, sun];

  static String shortName(int day) {
    const names = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return names[day]!;
  }

  static String initial(int day) {
    const initials = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};
    return initials[day]!;
  }

  static String fullName(int day) {
    const names = {
      1: 'Monday', 2: 'Tuesday', 3: 'Wednesday',
      4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday',
    };
    return names[day]!;
  }
}

/// Immutable set of repeat weekdays.
/// Empty set = fire once (no repeat).
class RepeatDays {
  final Set<int> days;

  const RepeatDays(this.days);

  factory RepeatDays.once()     => const RepeatDays({});
  factory RepeatDays.daily()    => const RepeatDays({1, 2, 3, 4, 5, 6, 7});
  factory RepeatDays.weekdays() => const RepeatDays({1, 2, 3, 4, 5});
  factory RepeatDays.weekends() => const RepeatDays({6, 7});

  bool get isOnce      => days.isEmpty;
  bool get isDaily     => days.length == 7;
  bool get isRepeating => days.isNotEmpty;
  bool contains(int day) => days.contains(day);

  String get label {
    if (isOnce)  return 'Once';
    if (isDaily) return 'Every day';
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'Weekdays';
    if (days.length == 2 && days.contains(6) && days.contains(7))   return 'Weekends';
    return Weekday.ordered.where(days.contains).map(Weekday.shortName).join(', ');
  }

  String get shortLabel {
    if (isOnce)  return 'Once';
    if (isDaily) return 'Daily';
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'Weekdays';
    if (days.length == 2 && days.contains(6) && days.contains(7))   return 'Weekends';
    return Weekday.ordered.where(days.contains).map(Weekday.initial).join('·');
  }

  RepeatDays toggle(int day) {
    final next = Set<int>.from(days);
    if (next.contains(day)) next.remove(day); else next.add(day);
    return RepeatDays(next);
  }

  DateTime nextOccurrence(DateTime time, [DateTime? from]) {
    from ??= DateTime.now();
    if (isOnce) return time;
    var candidate = DateTime(from.year, from.month, from.day, time.hour, time.minute);
    for (int i = 0; i < 8; i++) {
      if (days.contains(candidate.weekday) && candidate.isAfter(from)) return candidate;
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String toStorageString() {
    if (days.isEmpty) return '';
    final sorted = days.toList()..sort();
    return sorted.join(',');
  }

  factory RepeatDays.fromStorage(String? s) {
    if (s == null || s.isEmpty) return RepeatDays.once();
    final parts = s.split(',').map(int.tryParse).whereType<int>().toSet();
    return RepeatDays(parts);
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatDays && setEquals(days, other.days);

  @override
  int get hashCode => Object.hashAll(days.toList()..sort());
}

enum ReminderPriority { low, normal, high }

class Reminder {
  final String           id;
  final String           title;
  final DateTime         dateTime;
  final RepeatDays       repeat;
  final ReminderPriority priority;
  final String?          notes;

  const Reminder({
    required this.id,
    required this.title,
    required this.dateTime,
    RepeatDays? repeat,
    this.priority = ReminderPriority.normal,
    this.notes,
  }) : repeat = repeat ?? const RepeatDays({});

  bool get isPast      => DateTime.now().isAfter(dateTime);
  bool get isRepeating => repeat.isRepeating;
  int  get minutesFromNow => dateTime.difference(DateTime.now()).inMinutes;

  DateTime nextOccurrence([DateTime? from]) =>
      repeat.nextOccurrence(dateTime, from);

  Reminder copyWith({
    String? id, String? title, DateTime? dateTime,
    RepeatDays? repeat, ReminderPriority? priority, String? notes,
  }) => Reminder(
    id: id ?? this.id, title: title ?? this.title,
    dateTime: dateTime ?? this.dateTime, repeat: repeat ?? this.repeat,
    priority: priority ?? this.priority, notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title,
    'dateTime': dateTime.toIso8601String(),
    'repeat': repeat.toStorageString(),
    'priority': priority.name,
    'notes': notes,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] as String, title: j['title'] as String,
    dateTime: DateTime.parse(j['dateTime'] as String),
    repeat: RepeatDays.fromStorage(j['repeat'] as String?),
    priority: ReminderPriority.values.firstWhere(
      (e) => e.name == (j['priority'] ?? 'normal'),
      orElse: () => ReminderPriority.normal,
    ),
    notes: j['notes'] as String?,
  );
}