// services/geofence_service.dart — FULL REPLACEMENT
// Location polling + fires full AlarmService alarm on geofence trigger

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder_model.dart';
import '../screens/alarm_screen.dart';
import 'alarm_service.dart';
import 'reminder_service.dart';

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  final Map<String, bool> _insideMap = {};
  Timer? _pollTimer;
  bool _permissionGranted = false;
  bool _initialized = false;

  static const _kPollInterval = Duration(seconds: 30);
  static const _kPrefsKey = 'geofence_inside_map';

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadInsideMap();
    _permissionGranted = await _checkPermission();
    if (_permissionGranted) _startPolling();
    debugPrint('[GeofenceService] init — permission: $_permissionGranted');
  }

  // ── Permission ────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      debugPrint('[GeofenceService] Permission permanently denied.');
      return false;
    }
    _permissionGranted =
        perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
    if (_permissionGranted && _pollTimer == null) _startPolling();
    return _permissionGranted;
  }

  Future<bool> _checkPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  bool get hasPermission => _permissionGranted;

  // ── Current position (for picker UI) ─────────────────────────

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

  // ── Polling ───────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _poll());
    Future.microtask(_poll);
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (!_permissionGranted) return;

    final geofenced = ReminderService.instance.reminders.value
        .where((r) => r.geofence != null)
        .toList();
    if (geofenced.isEmpty) return;

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('[GeofenceService] poll position failed: $e');
      return;
    }

    for (final reminder in geofenced) {
      final fence = reminder.geofence!;
      final dist = _distanceMeters(
        pos.latitude,
        pos.longitude,
        fence.latitude,
        fence.longitude,
      );
      final inside = dist <= fence.radiusMeters;
      final wasInside = _insideMap[reminder.id] ?? false;

      if (inside == wasInside) continue;
      _insideMap[reminder.id] = inside;
      _persistInsideMap();

      final entered = inside && !wasInside;
      final left = !inside && wasInside;

      if ((fence.trigger == GeofenceTrigger.onArrive && entered) ||
          (fence.trigger == GeofenceTrigger.onLeave && left)) {
        await _fireGeofenceAlarm(reminder, fence, entered);
      }
    }
  }

  // ── Fire alarm (full AlarmScreen + audio) ─────────────────────

  Future<void> _fireGeofenceAlarm(
    Reminder reminder,
    ReminderGeofence fence,
    bool entered,
  ) async {
    final action = entered ? 'Arrived at' : 'Left';
    debugPrint(
      '[GeofenceService] FIRE: ${reminder.title} ($action ${fence.placeName})',
    );

    // Build a one-shot reminder that carries the location context in notes
    final triggered = reminder.copyWith(
      title: reminder.title,
      notes:
          '$action ${fence.placeName}${reminder.notes != null ? '\n${reminder.notes}' : ''}',
    );

    // Push full AlarmScreen — same rich UI as time-based reminders
    AlarmService.navigatorKey.currentState?.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => AlarmScreen(reminders: [triggered]),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    // Remove one-shot reminders after firing; keep repeating ones active
    if (!reminder.isRepeating) {
      await ReminderService.instance.remove(reminder.id);
    }
  }

  // ── Haversine distance ────────────────────────────────────────

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  // ── Persistence ───────────────────────────────────────────────

  Future<void> _loadInsideMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in prefs.getStringList(_kPrefsKey) ?? []) {
        final parts = entry.split(':');
        if (parts.length == 2) _insideMap[parts[0]] = parts[1] == '1';
      }
    } catch (e) {
      debugPrint('[GeofenceService] load failed: $e');
    }
  }

  Future<void> _persistInsideMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kPrefsKey,
        _insideMap.entries
            .map((e) => '${e.key}:${e.value ? '1' : '0'}')
            .toList(),
      );
    } catch (e) {
      debugPrint('[GeofenceService] persist failed: $e');
    }
  }

  void removeGeofence(String reminderId) {
    _insideMap.remove(reminderId);
    _persistInsideMap();
  }

  void dispose() => stopPolling();
}
