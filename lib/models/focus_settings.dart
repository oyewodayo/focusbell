// models/focus_settings.dart
// Drop into lib/models/
// Session settings: autostart toggles, strict mode, tick sound.
// Persisted to SharedPreferences as JSON.

import 'dart:convert';

class FocusSettings {
  final bool autostartBreak;     // after work → auto-start break
  final bool autostartSession;   // after break → auto-start work
  final bool strictMode;         // lock sheet open during work
  final bool tickEnabled;        // looping tick sound while running

  const FocusSettings({
    this.autostartBreak    = false,
    this.autostartSession  = false,
    this.strictMode        = false,
    this.tickEnabled       = true,
  });

  FocusSettings copyWith({
    bool? autostartBreak,
    bool? autostartSession,
    bool? strictMode,
    bool? tickEnabled,
  }) =>
      FocusSettings(
        autostartBreak:   autostartBreak   ?? this.autostartBreak,
        autostartSession: autostartSession  ?? this.autostartSession,
        strictMode:       strictMode        ?? this.strictMode,
        tickEnabled:      tickEnabled       ?? this.tickEnabled,
      );

  Map<String, dynamic> toJson() => {
        'autostartBreak':   autostartBreak,
        'autostartSession': autostartSession,
        'strictMode':       strictMode,
        'tickEnabled':      tickEnabled,
      };

  factory FocusSettings.fromJson(Map<String, dynamic> j) => FocusSettings(
        autostartBreak:   j['autostartBreak']   as bool? ?? false,
        autostartSession: j['autostartSession']  as bool? ?? false,
        strictMode:       j['strictMode']        as bool? ?? false,
        tickEnabled:      j['tickEnabled']       as bool? ?? true,
      );

  static FocusSettings fromPrefs(String? raw) {
    if (raw == null) return const FocusSettings();
    try {
      return FocusSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FocusSettings();
    }
  }

  String toPrefs() => jsonEncode(toJson());
}