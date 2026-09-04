// services/geofence_service.dart — FULL REPLACEMENT
//
// Fix 1: Trigger accuracy — priming baseline on first encounter so
//         onArrive/onLeave only fire on REAL transitions, not cold-start
//         defaults. Uses a _seenIds set to distinguish "never seen"
//         from "seen and was outside".
//
// Fix 2: Focus-zone monitoring — when a focus session is active and
//         isWork is true, we watch a 50m radius around the location
//         where the session started. If the user leaves that radius,
//         we fire a "Go back and focus" nudge (not a full alarm —
//         a dismissible overlay so it doesn't break flow).
//
// Fix 3: onLeave trigger for watched places fires correctly now
//         because we always prime state before firing.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder_model.dart';
import '../models/saved_place.dart';
import '../screens/alarm_screen.dart';
import 'alarm_service.dart';
import 'focus_timer_service.dart';
import 'reminder_service.dart';
import 'saved_places_service.dart';

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  // ── Inside-state maps ─────────────────────────────────────────
  // Key absent  = never seen (prime on next poll, don't fire)
  // Key present = seen at least once, value = last known inside state

  final Map<String, bool> _reminderInsideMap = {};
  final Map<String, bool> _placeInsideMap    = {};

  // IDs that have been primed (seen at least once) — fire only after this
  final Set<String> _reminderPrimed = {};
  final Set<String> _placePrimed    = {};

  // ── Focus-zone state ──────────────────────────────────────────

  /// Where the focus session started (captured on session start)
  Position? _focusAnchor;

  /// Whether we have already nudged the user this session
  bool _focusNudgeSent = false;

  /// Cooldown between focus nudges (don't spam every 30s)
  DateTime? _lastFocusNudge;
  static const _kFocusNudgeCooldown = Duration(minutes: 3);

  static const _kFocusRadius = 50.0; // metres

  // ── Poll timer ────────────────────────────────────────────────

  Timer? _pollTimer;
  bool   _permissionGranted = false;
  bool   _initialized       = false;

  static const _kPollInterval     = Duration(seconds: 30);
  static const _kReminderPrefsKey = 'geo_reminder_inside_v2';
  static const _kPlacePrefsKey    = 'geo_place_inside_v2';

  // Expose for UI
  Map<String, bool> get placeInsideMap => Map.unmodifiable(_placeInsideMap);
  bool isInsidePlace(String placeId)   => _placeInsideMap[placeId] ?? false;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadPersistedMaps();
    _permissionGranted = await _checkPermission();
    if (_permissionGranted) _startPolling();
    debugPrint('[GeofenceService] init  permission=$_permissionGranted');
  }

  // ── Permission ────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    _permissionGranted = perm == LocationPermission.whileInUse ||
                         perm == LocationPermission.always;
    if (_permissionGranted && _pollTimer == null) _startPolling();
    return _permissionGranted;
  }

  Future<bool> _checkPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  bool get hasPermission => _permissionGranted;

  // ── Current position ─────────────────────────────────────────

  Future<Position?> getCurrentPosition() async {
    if (!_permissionGranted) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[GeofenceService] getCurrentPosition failed: $e');
      return null;
    }
  }

  // ── Capture focus anchor (called by FocusTimerService on start) ─

  void onFocusSessionStarted() {
    _focusNudgeSent = false;
    _lastFocusNudge = null;
    // Capture current position asynchronously as the anchor
    getCurrentPosition().then((pos) {
      _focusAnchor = pos;
      debugPrint('[GeofenceService] focus anchor set: '
          '${pos?.latitude}, ${pos?.longitude}');
    });
  }

  void onFocusSessionEnded() {
    _focusAnchor    = null;
    _focusNudgeSent = false;
    _lastFocusNudge = null;
    debugPrint('[GeofenceService] focus anchor cleared');
  }

  // ── Poll ──────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _poll());
    Future.microtask(_poll);
  }

  void stopPolling() { _pollTimer?.cancel(); _pollTimer = null; }

  Future<void> _poll() async {
    if (!_permissionGranted) return;

    final geofencedReminders = ReminderService.instance.reminders.value
        .where((r) => r.geofence != null).toList();
    final watchedPlaces = SavedPlacesService.instance.watchedPlaces;
    final focusActive   = FocusTimerService.instance.state.isActive &&
                          FocusTimerService.instance.state.isWork;

    if (geofencedReminders.isEmpty &&
        watchedPlaces.isEmpty &&
        (!focusActive || _focusAnchor == null)) return;

    // Single GPS read for all checks this tick
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy:  LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('[GeofenceService] poll failed: $e');
      return;
    }

    bool reminderStateChanged = false;
    bool placeStateChanged    = false;

    // ── 1. Reminder-linked geofences ─────────────────────────────
    for (final reminder in geofencedReminders) {
      final fence  = reminder.geofence!;
      final dist   = _dist(pos, fence.latitude, fence.longitude);
      final inside = dist <= fence.radiusMeters;
      final id     = reminder.id;

      if (!_reminderPrimed.contains(id)) {
        // FIRST ENCOUNTER — prime silently, never fire
        _reminderInsideMap[id] = inside;
        _reminderPrimed.add(id);
        reminderStateChanged = true;
        debugPrint('[GeoService] primed reminder "$id" inside=$inside '
            'trigger=${fence.trigger.name}');
        continue;
      }

      final wasInside = _reminderInsideMap[id]!;
      if (inside == wasInside) continue; // no transition

      // Real transition detected
      _reminderInsideMap[id] = inside;
      reminderStateChanged = true;

      final entered = inside;   // true = just entered, false = just left
      final shouldFire =
          (fence.trigger == GeofenceTrigger.onArrive && entered) ||
          (fence.trigger == GeofenceTrigger.onLeave  && !entered);

      debugPrint('[GeoService] reminder "${reminder.title}" '
          '${entered ? "ENTERED" : "LEFT"} ${fence.placeName}  '
          'trigger=${fence.trigger.name}  shouldFire=$shouldFire');

      if (shouldFire) {
        await _fireReminderAlarm(reminder, fence, entered);
      }
    }

    // ── 2. Watched places (always-on) ────────────────────────────
    for (final place in watchedPlaces) {
      final dist   = _dist(pos, place.latitude, place.longitude);
      final inside = dist <= place.radiusMeters;
      final id     = place.id;

      if (!_placePrimed.contains(id)) {
        // FIRST ENCOUNTER — prime silently
        _placeInsideMap[id] = inside;
        _placePrimed.add(id);
        placeStateChanged = true;
        debugPrint('[GeoService] primed place "${place.name}" inside=$inside');
        continue;
      }

      final wasInside = _placeInsideMap[id]!;
      if (inside == wasInside) continue;

      _placeInsideMap[id] = inside;
      placeStateChanged   = true;

      final entered = inside;
      debugPrint('[GeoService] place "${place.name}" '
          '${entered ? "ENTERED" : "LEFT"}  dist=${dist.round()}m');

      await _firePlaceAlarm(place, entered);
    }

    // ── 3. Focus-zone monitoring ──────────────────────────────────
    if (focusActive && _focusAnchor != null) {
      final distFromAnchor = _distPos(pos, _focusAnchor!);
      final outsideFocusZone = distFromAnchor > _kFocusRadius;

      if (outsideFocusZone) {
        final now     = DateTime.now();
        final canNudge = _lastFocusNudge == null ||
            now.difference(_lastFocusNudge!) > _kFocusNudgeCooldown;

        if (canNudge) {
          _lastFocusNudge = now;
          _focusNudgeSent = true;
          debugPrint('[GeoService] FOCUS ZONE BREACH  '
              'dist=${distFromAnchor.round()}m > ${_kFocusRadius}m');
          _showFocusNudge(distFromAnchor.round());
        }
      } else if (_focusNudgeSent) {
        // Returned to focus zone — reset so next leave fires again
        _focusNudgeSent = false;
        debugPrint('[GeoService] returned to focus zone');
      }
    }

    await _persistMaps(
      reminderChanged: reminderStateChanged,
      placeChanged:    placeStateChanged,
    );
  }

  // ── Fire: reminder alarm ──────────────────────────────────────

  Future<void> _fireReminderAlarm(
    Reminder reminder,
    ReminderGeofence fence,
    bool entered,
  ) async {
    final action = entered ? 'Arrived at' : 'Left';
    final triggered = reminder.copyWith(
      notes: '$action ${fence.placeName}'
          '${reminder.notes != null ? '\n${reminder.notes}' : ''}',
    );
    _pushAlarmScreen([triggered]);
    // Non-repeating location reminders are left in place after firing —
    // only the user deleting them, or the auto-delete grace period in
    // Settings, removes them (see ReminderService.sweepAutoDelete).
  }

  // ── Fire: watched place alarm ─────────────────────────────────

  Future<void> _firePlaceAlarm(SavedPlace place, bool entered) async {
    final message = entered ? place.arriveMessage() : place.leaveMessage();
    final synthetic = Reminder(
      id:       'place_${place.id}_${DateTime.now().millisecondsSinceEpoch}',
      title:    message,
      dateTime: DateTime.now(),
      notes:    entered ? 'You arrived at ${place.name}'
                        : 'You left ${place.name}',
    );
    _pushAlarmScreen([synthetic]);
  }

  // ── Show focus nudge overlay (non-blocking) ───────────────────

  void _showFocusNudge(int distMetres) {
    final ctx = AlarmService.navigatorKey.currentContext;
    if (ctx == null) return;

    final projectName =
        FocusTimerService.instance.state.projectName ?? 'your session';

    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'focus_nudge',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (_, anim, __, child) => ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) => _FocusNudgeOverlay(
        projectName: projectName,
        distMetres:  distMetres,
        onGoBack: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  // ── Push alarm screen ─────────────────────────────────────────

  void _pushAlarmScreen(List<Reminder> reminders) {
    AlarmService.navigatorKey.currentState?.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => AlarmScreen(reminders: reminders),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ── Distance helpers ──────────────────────────────────────────

  double _dist(Position pos, double lat2, double lng2) =>
      _distanceMeters(pos.latitude, pos.longitude, lat2, lng2);

  double _distPos(Position a, Position b) =>
      _distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  static double _distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const R    = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a    = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180;

  // ── Persistence ───────────────────────────────────────────────

  Future<void> _loadPersistedMaps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in prefs.getStringList(_kReminderPrefsKey) ?? []) {
        final p = e.split(':');
        if (p.length == 2) {
          _reminderInsideMap[p[0]] = p[1] == '1';
          _reminderPrimed.add(p[0]);
        }
      }
      for (final e in prefs.getStringList(_kPlacePrefsKey) ?? []) {
        final p = e.split(':');
        if (p.length == 2) {
          _placeInsideMap[p[0]] = p[1] == '1';
          _placePrimed.add(p[0]);
        }
      }
    } catch (e) { debugPrint('[GeofenceService] load failed: $e'); }
  }

  Future<void> _persistMaps({
    bool reminderChanged = false,
    bool placeChanged    = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reminderChanged) {
        await prefs.setStringList(_kReminderPrefsKey,
            _reminderInsideMap.entries
                .map((e) => '${e.key}:${e.value ? '1' : '0'}').toList());
      }
      if (placeChanged) {
        await prefs.setStringList(_kPlacePrefsKey,
            _placeInsideMap.entries
                .map((e) => '${e.key}:${e.value ? '1' : '0'}').toList());
      }
    } catch (e) { debugPrint('[GeofenceService] persist failed: $e'); }
  }

  void removeGeofence(String reminderId) {
    _reminderInsideMap.remove(reminderId);
    _reminderPrimed.remove(reminderId);
    _persistMaps(reminderChanged: true);
  }

  void dispose() => stopPolling();
}

// ════════════════════════════════════════════════════════════════
// Focus Nudge Overlay
// Non-blocking, personality-rich dialog that nudges the user back.
// ════════════════════════════════════════════════════════════════

class _FocusNudgeOverlay extends StatelessWidget {
  final String     projectName;
  final int        distMetres;
  final VoidCallback onGoBack;

  const _FocusNudgeOverlay({
    required this.projectName,
    required this.distMetres,
    required this.onGoBack,
  });

  static const _messages = [
    'Hey! Where are you going?',
    'Focus zone breached 🚨',
    'Come back. You were doing great.',
    'Your session is waiting for you.',
    'Step away from the distraction.',
  ];

  String get _randomMessage {
    final idx = DateTime.now().millisecond % _messages.length;
    return _messages[idx];
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFFFF453A).withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF453A).withOpacity(0.15),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing warning icon
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF453A).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF453A).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Text('🚶', style: TextStyle(fontSize: 32)),
                  ),
                ),
                const SizedBox(height: 20),

                // Headline
                Text(
                  _randomMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),

                // Sub message
                Text(
                  'You\'re ${distMetres}m away from your\n"$projectName" focus zone.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Go back and stay focused. You\'ve got this.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // Go back button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: onGoBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          '🔴  Back to Focus',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Dismiss link
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text(
                    'I\'ll be back shortly',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}