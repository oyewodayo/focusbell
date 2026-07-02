import 'package:flutter/material.dart';

// ── ReminderInterval ──────────────────────────────────────────────

enum ReminderInterval {
  fifteenMin, // index 0 — legacy saves used 0 for this
  thirtyMin,  // index 1
  oneHour,    // index 2
  twoHours,   // index 3
  fourHours,  // index 4
  fiveMin;    // index 5 — appended last to avoid shifting legacy indexes

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

  static const displayOrder = [
    ReminderInterval.fiveMin,
    ReminderInterval.fifteenMin,
    ReminderInterval.thirtyMin,
    ReminderInterval.oneHour,
    ReminderInterval.twoHours,
    ReminderInterval.fourHours,
  ];

  static const _legacyIndexMap = {
    0: ReminderInterval.fifteenMin,
    1: ReminderInterval.thirtyMin,
    2: ReminderInterval.oneHour,
    3: ReminderInterval.twoHours,
    4: ReminderInterval.fourHours,
    5: ReminderInterval.fiveMin,
  };

  static ReminderInterval fromJson(dynamic raw) {
    if (raw is String) {
      return ReminderInterval.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => ReminderInterval.oneHour,
      );
    }
    if (raw is int) return _legacyIndexMap[raw] ?? ReminderInterval.oneHour;
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

// ── AppThemeMode ──────────────────────────────────────────────────
//
// • dark   — always dark
// • light  — always light
// • system — follow OS setting
// • auto   — dark 8 PM–7 AM, light otherwise (time-of-day)

enum AppThemeMode { dark, light, system, auto }

extension AppThemeModeX on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.dark   => 'Dark',
        AppThemeMode.light  => 'Light',
        AppThemeMode.system => 'System',
        AppThemeMode.auto   => 'Auto (day/night)',
      };

  String get emoji => switch (this) {
        AppThemeMode.dark   => '🌑',
        AppThemeMode.light  => '☀️',
        AppThemeMode.system => '📱',
        AppThemeMode.auto   => '🌗',
      };

  /// Resolves this preference to a concrete [Brightness].
  /// Called at build time; [platformBrightness] is only used when [system].
  Brightness resolve(Brightness platformBrightness) {
    switch (this) {
      case AppThemeMode.dark:
        return Brightness.dark;
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.system:
        return platformBrightness;
      case AppThemeMode.auto:
        final hour = DateTime.now().hour;
        // Dark from 8 PM (20:00) to 7 AM (07:00).
        return (hour >= 20 || hour < 7)
            ? Brightness.dark
            : Brightness.light;
    }
  }

  /// Maps to Flutter's [ThemeMode] for MaterialApp.
  /// [auto] behaves like [dark] or [light] at a given moment —
  /// we handle it via a resolved [ThemeData] swap, not ThemeMode.system.
  ThemeMode toFlutterThemeMode() => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light  => ThemeMode.light,
        _                   => ThemeMode.dark,
      };

  static AppThemeMode fromJson(dynamic raw) {
    if (raw is String) {
      return AppThemeMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => AppThemeMode.dark,
      );
    }
    return AppThemeMode.dark;
  }
}

// ── AppSettings ───────────────────────────────────────────────────

class AppSettings {
  final SoundMode      soundMode;
  final bool           notificationsEnabled;
  final ReminderInterval interval;
  final int            quietStartHour;
  final int            quietEndHour;
  final String?        pinHash;
  final bool           pinEnabled;
  final AppThemeMode   themeMode;

  const AppSettings({
    this.notificationsEnabled = true,
    this.interval             = ReminderInterval.oneHour,
    this.quietStartHour       = 22,
    this.quietEndHour         = 7,
    this.soundMode            = SoundMode.both,
    this.pinHash              = null,
    this.pinEnabled           = false,
    this.themeMode            = AppThemeMode.dark,
  });

  AppSettings copyWith({
    bool?              notificationsEnabled,
    ReminderInterval?  interval,
    int?               quietStartHour,
    int?               quietEndHour,
    SoundMode?         soundMode,
    Object?            pinHash   = _sentinel,
    bool?              pinEnabled,
    AppThemeMode?      themeMode,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        interval:             interval             ?? this.interval,
        quietStartHour:       quietStartHour       ?? this.quietStartHour,
        quietEndHour:         quietEndHour         ?? this.quietEndHour,
        soundMode:            soundMode            ?? this.soundMode,
        pinHash: identical(pinHash, _sentinel) ? this.pinHash : pinHash as String?,
        pinEnabled:           pinEnabled           ?? this.pinEnabled,
        themeMode:            themeMode            ?? this.themeMode,
      );

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'interval':             interval.name,
        'quietStartHour':       quietStartHour,
        'quietEndHour':         quietEndHour,
        'soundMode':            soundMode.index,
        if (pinHash != null) 'pinHash': pinHash,
        'pinEnabled':           pinEnabled,
        'themeMode':            themeMode.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        interval:             ReminderInterval.fromJson(json['interval']),
        quietStartHour:       json['quietStartHour'] as int? ?? 22,
        quietEndHour:         json['quietEndHour']   as int? ?? 7,
        soundMode: SoundMode.values[
            (json['soundMode'] as int?) ?? SoundMode.both.index],
        pinHash:    json['pinHash']    as String?,
        pinEnabled: json['pinEnabled'] as bool? ?? false,
        themeMode:  AppThemeModeX.fromJson(json['themeMode']),
      );
}