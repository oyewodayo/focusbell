import 'dart:convert';

// ── Focus sound option ────────────────────────────────────────────

enum FocusSound {
  tick,
  binauralBeats,
  brownNoise,
  rain,
  silent;

  String get label => switch (this) {
    FocusSound.tick => 'Tick',
    FocusSound.binauralBeats => 'Binaural Beats (40Hz)',
    FocusSound.brownNoise => 'Brown Noise',
    FocusSound.rain => 'Rain',
    FocusSound.silent => 'Silent',
  };

  String get emoji => switch (this) {
    FocusSound.tick => '🕐',
    FocusSound.binauralBeats => '🧠',
    FocusSound.brownNoise => '🌫️',
    FocusSound.rain => '🌧️',
    FocusSound.silent => '🔇',
  };
}

// ── Settings model ────────────────────────────────────────────────

class FocusSettings {
  final bool autostartBreak;
  final bool autostartSession;
  final bool strictMode;
  final bool tickEnabled; // kept for legacy callers — mirrors focusSound
  final FocusSound focusSound; // ← NEW

  const FocusSettings({
    this.autostartBreak = false,
    this.autostartSession = false,
    this.strictMode = false,
    this.tickEnabled = true,
    this.focusSound = FocusSound.tick, // ← NEW
  });

  FocusSettings copyWith({
    bool? autostartBreak,
    bool? autostartSession,
    bool? strictMode,
    bool? tickEnabled,
    FocusSound? focusSound, // ← NEW
  }) => FocusSettings(
    autostartBreak: autostartBreak ?? this.autostartBreak,
    autostartSession: autostartSession ?? this.autostartSession,
    strictMode: strictMode ?? this.strictMode,
    tickEnabled: tickEnabled ?? this.tickEnabled,
    focusSound: focusSound ?? this.focusSound, // ← NEW
  );

  Map<String, dynamic> toJson() => {
    'autostartBreak': autostartBreak,
    'autostartSession': autostartSession,
    'strictMode': strictMode,
    'tickEnabled': tickEnabled,
    'focusSound': focusSound.index, // ← NEW
  };

  factory FocusSettings.fromJson(Map<String, dynamic> j) => FocusSettings(
    autostartBreak: j['autostartBreak'] as bool? ?? false,
    autostartSession: j['autostartSession'] as bool? ?? false,
    strictMode: j['strictMode'] as bool? ?? false,
    tickEnabled: j['tickEnabled'] as bool? ?? true,
    focusSound:
        FocusSound.values[ // ← NEW
        j['focusSound'] as int? ?? 0],
  );

  static FocusSettings fromPrefs(String? raw) {
    if (raw == null) return const FocusSettings();
    try {
      return FocusSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FocusSettings();
    }
  }

  String toPrefs() => jsonEncode(toJson());
}