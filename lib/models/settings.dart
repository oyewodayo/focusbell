import 'package:flutter/material.dart';

// ── ReminderInterval ──────────────────────────────────────────────

enum ReminderInterval {
  fifteenMin,  // index 0 — legacy saves used 0 for this
  thirtyMin,   // index 1
  oneHour,     // index 2
  twoHours,    // index 3
  fourHours,   // index 4
  fiveMin;     // index 5 — appended last to avoid shifting legacy indexes

  String get label {
    switch (this) {
      case ReminderInterval.fiveMin:    return 'Every 5 min';
      case ReminderInterval.fifteenMin: return 'Every 15 min';
      case ReminderInterval.thirtyMin:  return 'Every 30 min';
      case ReminderInterval.oneHour:    return 'Every hour';
      case ReminderInterval.twoHours:   return 'Every 2 hours';
      case ReminderInterval.fourHours:  return 'Every 4 hours';
    }
  }

  int get minutes {
    switch (this) {
      case ReminderInterval.fiveMin:    return 5;
      case ReminderInterval.fifteenMin: return 15;
      case ReminderInterval.thirtyMin:  return 30;
      case ReminderInterval.oneHour:    return 60;
      case ReminderInterval.twoHours:   return 120;
      case ReminderInterval.fourHours:  return 240;
    }
  }

  /// Ascending display order for the settings UI.
  /// Decoupled from enum declaration order so we never need to shift indexes.
  static const displayOrder = [
    ReminderInterval.fiveMin,
    ReminderInterval.fifteenMin,
    ReminderInterval.thirtyMin,
    ReminderInterval.oneHour,
    ReminderInterval.twoHours,
    ReminderInterval.fourHours,
  ];

  /// Maps legacy int indexes (saved before name-based serialization).
  static const _legacyIndexMap = {
    0: ReminderInterval.fifteenMin,
    1: ReminderInterval.thirtyMin,
    2: ReminderInterval.oneHour,
    3: ReminderInterval.twoHours,
    4: ReminderInterval.fourHours,
    5: ReminderInterval.fiveMin,
  };

  /// Deserializes from either a name string (new) or an int index (legacy).
  static ReminderInterval fromJson(dynamic raw) {
    if (raw is String) {
      return ReminderInterval.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => ReminderInterval.oneHour,
      );
    }
    if (raw is int) {
      return _legacyIndexMap[raw] ?? ReminderInterval.oneHour;
    }
    return ReminderInterval.oneHour;
  }
}

// ── SoundMode ─────────────────────────────────────────────────────

enum SoundMode { silent, vibrate, ring, both }

extension SoundModeX on SoundMode {
  String get label => switch (this) {
    SoundMode.silent  => 'Silent',
    SoundMode.vibrate => 'Vibrate',
    SoundMode.ring    => 'Ring',
    SoundMode.both    => 'Vibrate & Ring',
  };

  String get emoji => switch (this) {
    SoundMode.silent  => '🔇',
    SoundMode.vibrate => '📳',
    SoundMode.ring    => '🔔',
    SoundMode.both    => '🔔',
  };
}

// ── AppSettings ───────────────────────────────────────────────────

class AppSettings {
  final SoundMode soundMode;
  final bool notificationsEnabled;
  final ReminderInterval interval;
  final int quietStartHour;
  final int quietEndHour;

  const AppSettings({
    this.notificationsEnabled = true,
    this.interval             = ReminderInterval.oneHour,
    this.quietStartHour       = 22,
    this.quietEndHour         = 7,
    this.soundMode            = SoundMode.both,
  });

  AppSettings copyWith({
    bool?             notificationsEnabled,
    ReminderInterval? interval,
    int?              quietStartHour,
    int?              quietEndHour,
    SoundMode?        soundMode,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        interval:             interval             ?? this.interval,
        quietStartHour:       quietStartHour       ?? this.quietStartHour,
        quietEndHour:         quietEndHour         ?? this.quietEndHour,
        soundMode:            soundMode            ?? this.soundMode,
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'interval':             interval.name,   // ← name string, not index
        'quietStartHour':       quietStartHour,
        'quietEndHour':         quietEndHour,
        'soundMode':            soundMode.index,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        interval:             ReminderInterval.fromJson(json['interval']),
        quietStartHour:       json['quietStartHour'] as int? ?? 22,
        quietEndHour:         json['quietEndHour']   as int? ?? 7,
        soundMode: SoundMode.values[
            (json['soundMode'] as int?) ?? SoundMode.both.index],
      );
}