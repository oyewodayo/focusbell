enum ReminderInterval {
  fiveenMin,
  fifteenMin,
  thirtyMin,
  oneHour,
  twoHours,
  fourHours;

  String get label {
    switch (this) {
      case ReminderInterval.fiveenMin: return 'Every 5 min';
      case ReminderInterval.fifteenMin: return 'Every 15 min';
      case ReminderInterval.thirtyMin:  return 'Every 30 min';
      case ReminderInterval.oneHour:    return 'Every hour';
      case ReminderInterval.twoHours:   return 'Every 2 hours';
      case ReminderInterval.fourHours:  return 'Every 4 hours';
    }
  }

  int get minutes {
    switch (this) {
      case ReminderInterval.fiveenMin: return 5;
      case ReminderInterval.fifteenMin: return 15;
      case ReminderInterval.thirtyMin:  return 30;
      case ReminderInterval.oneHour:    return 60;
      case ReminderInterval.twoHours:   return 120;
      case ReminderInterval.fourHours:  return 240;
    }
  }
}

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


class AppSettings {
  final SoundMode soundMode;
  final bool notificationsEnabled;
  final ReminderInterval interval;
  final int quietStartHour;
  final int quietEndHour;

  const AppSettings({
    this.notificationsEnabled = true,
    this.interval = ReminderInterval.oneHour,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
    this.soundMode = SoundMode.both,
  });

  AppSettings copyWith({
    bool? notificationsEnabled,
    ReminderInterval? interval,
    int? quietStartHour,
    int? quietEndHour,
    SoundMode? soundMode,          // ← optional, not required
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        interval:             interval             ?? this.interval,
        quietStartHour:       quietStartHour       ?? this.quietStartHour,
        quietEndHour:         quietEndHour         ?? this.quietEndHour,
        soundMode:            soundMode            ?? this.soundMode, // ← actually applied
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'interval':             interval.index,
        'quietStartHour':       quietStartHour,
        'quietEndHour':         quietEndHour,
        'soundMode':            soundMode.index,   // ← persisted
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        interval: ReminderInterval.values[
            (json['interval'] as int?) ?? ReminderInterval.oneHour.index],
        quietStartHour: json['quietStartHour'] as int? ?? 22,
        quietEndHour:   json['quietEndHour']   as int? ?? 7,
        soundMode: SoundMode.values[            // ← restored
            (json['soundMode'] as int?) ?? SoundMode.both.index],
      );
}