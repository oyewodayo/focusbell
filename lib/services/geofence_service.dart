// services/geofence_service.dart — NEW FILE
//
// Responsibilities:
//   • Request & check location permissions at runtime
//   • Register / unregister geofences per reminder
//   • Poll current position in the foreground task tick (every 30s)
//   • Detect enter/leave events and fire a notification
//   • Persist which geofences are "active" across restarts
//
// Uses geolocator (position polling) — no Google Play Services dependency.
// Background execution piggybacks on the existing flutter_foreground_task.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder_model.dart';
import 'notification_service.dart';
import 'reminder_service.dart';

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  // ── State ─────────────────────────────────────────────────────

  /// reminderId → whether the user was INSIDE the fence last check.
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

    if (_permissionGranted) {
      _startPolling();
    }
    debugPrint('[GeofenceService] init — permission: $_permissionGranted');
  }

  // ── Permission ────────────────────────────────────────────────

  /// Requests location permission if not already granted.
  /// Returns true if we have at least "while in use" permission.
  /// Call this from the UI before showing the location picker.
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

    debugPrint('[GeofenceService] permission: $perm');
    return _permissionGranted;
  }

  Future<bool> _checkPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  bool get hasPermission => _permissionGranted;

  // ── Current position (for the picker UI) ─────────────────────

  /// Returns current position or null if unavailable.
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
    // Also poll immediately
    Future.microtask(_poll);
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (!_permissionGranted) return;

    // Only process reminders that have a geofence attached
    final geofenced = ReminderService.instance.reminders.value
        .where((r) => r.geofence != null)
        .toList();

    if (geofenced.isEmpty) return;

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
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

      if (inside != wasInside) {
        _insideMap[reminder.id] = inside;
        _persistInsideMap();

        // Fire notification on the relevant transition
        final entered = inside && !wasInside;
        final left = !inside && wasInside;

        if ((fence.trigger == GeofenceTrigger.onArrive && entered) ||
            (fence.trigger == GeofenceTrigger.onLeave && left)) {
          await _fireGeofenceNotification(reminder, fence, entered);
        }
      }
    }
  }

  // ── Notification ──────────────────────────────────────────────

  static const _kGeofenceChannelId = 'focusbell_geofence';
  static const _kGeofenceChannelName = 'Location Reminders';
  static int _nextNotifId = 90000;

  Future<void> _fireGeofenceNotification(
    Reminder reminder,
    ReminderGeofence fence,
    bool entered,
  ) async {
    debugPrint(
      '[GeofenceService] FIRE: ${reminder.title} '
      '(${entered ? "entered" : "left"} ${fence.placeName})',
    );

    final plugin = NotificationService.instance.plugin;

    // Ensure the geofence channel exists
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      try {
        await androidPlugin.createNotificationChannel(
          const fln.AndroidNotificationChannel(
            _kGeofenceChannelId,
            _kGeofenceChannelName,
            description: 'Reminders triggered by your location.',
            importance: fln.Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      } catch (_) {}
    }

    final action = entered ? 'Arrived at' : 'Left';
    final id = _nextNotifId++;

    await plugin.show(
      id,
      '📍 $action ${fence.placeName}',
      reminder.title,
      fln.NotificationDetails(
        android: fln.AndroidNotificationDetails(
          _kGeofenceChannelId,
          _kGeofenceChannelName,
          importance: fln.Importance.max,
          priority: fln.Priority.max,
          enableVibration: true,
          playSound: true,
          fullScreenIntent: false,
        ),
        iOS: const fln.DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: reminder.id,
    );

    // For repeating reminders, leave it active.
    // For one-shot, remove after firing.
    if (!reminder.isRepeating) {
      await ReminderService.instance.remove(reminder.id);
    }
  }

  // ── Distance helper (Haversine) ───────────────────────────────

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0; // Earth radius in metres
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
      final raw = prefs.getStringList(_kPrefsKey) ?? [];
      for (final entry in raw) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          _insideMap[parts[0]] = parts[1] == '1';
        }
      }
    } catch (e) {
      debugPrint('[GeofenceService] loadInsideMap failed: $e');
    }
  }

  Future<void> _persistInsideMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _insideMap.entries
          .map((e) => '${e.key}:${e.value ? '1' : '0'}')
          .toList();
      await prefs.setStringList(_kPrefsKey, raw);
    } catch (e) {
      debugPrint('[GeofenceService] persistInsideMap failed: $e');
    }
  }

  /// Called when a reminder with a geofence is deleted — clears its state.
  void removeGeofence(String reminderId) {
    _insideMap.remove(reminderId);
    _persistInsideMap();
  }

  void dispose() {
    stopPolling();
  }
}
