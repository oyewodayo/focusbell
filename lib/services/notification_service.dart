import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

import '../models/project.dart';
import '../models/settings.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = fln.FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Exposed so the background task isolate can call show() directly.
  fln.FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const _channelBoth    = 'focusbell_both';
  static const _channelRing    = 'focusbell_ring';
  static const _channelVibrate = 'focusbell_vibrate';
  static const _channelSilent  = 'focusbell_silent';

  // ── Init ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final String localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));

    const android = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = fln.DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const fln.InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        fln.AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final vibPattern = Int64List.fromList([0, 400, 200, 400]);

      await androidPlugin.createNotificationChannel(
        fln.AndroidNotificationChannel(
          _channelBoth, 'Focus Reminders (Sound + Vibration)',
          description: 'Reminders with sound and vibration.',
          importance: fln.Importance.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: vibPattern,
        ),
      );
      await androidPlugin.createNotificationChannel(
        fln.AndroidNotificationChannel(
          _channelRing, 'Focus Reminders (Sound)',
          description: 'Reminders with sound only.',
          importance: fln.Importance.max,
          playSound: true,
          enableVibration: false,
        ),
      );
      await androidPlugin.createNotificationChannel(
        fln.AndroidNotificationChannel(
          _channelVibrate, 'Focus Reminders (Vibration)',
          description: 'Reminders with vibration only.',
          importance: fln.Importance.max,
          playSound: false,
          enableVibration: true,
          vibrationPattern: vibPattern,
        ),
      );
      await androidPlugin.createNotificationChannel(
        fln.AndroidNotificationChannel(
          _channelSilent, 'Focus Reminders (Silent)',
          description: 'Silent focus reminders.',
          importance: fln.Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );
    }

    _initialized = true;
  }

  // ── Permissions ───────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestExactAlarmsPermission();
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        fln.IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true, badge: true, sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  // ── Instant notification ──────────────────────────────────────

  Future<void> showInstant(
    Project project, {
    SoundMode soundMode = SoundMode.both,
  }) async {
    await _plugin.show(
      0,
      '${project.priority.emoji} Now focused: ${project.name}',
      "Priority set to ${project.priority.label}. You've got this!",
      buildDetails(soundMode),
      payload: project.id,
    );
  }

  // ── Cancel all scheduled (legacy exact alarms) ────────────────

  Future<void> cancelAll() => _plugin.cancelAll();

  // ── Public so the background isolate can call it ──────────────

  fln.NotificationDetails buildDetails(SoundMode mode) {
    final playSound  = mode == SoundMode.ring    || mode == SoundMode.both;
    final doVibrate  = mode == SoundMode.vibrate || mode == SoundMode.both;
    final vibPattern = doVibrate
        ? Int64List.fromList([0, 400, 200, 400])
        : null;

    final channelId = switch (mode) {
      SoundMode.both    => _channelBoth,
      SoundMode.ring    => _channelRing,
      SoundMode.vibrate => _channelVibrate,
      SoundMode.silent  => _channelSilent,
    };
    final channelName = switch (mode) {
      SoundMode.both    => 'Focus Reminders (Sound + Vibration)',
      SoundMode.ring    => 'Focus Reminders (Sound)',
      SoundMode.vibrate => 'Focus Reminders (Vibration)',
      SoundMode.silent  => 'Focus Reminders (Silent)',
    };

    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        channelId,
        channelName,
        importance:       fln.Importance.max,
        priority:         fln.Priority.max,
        enableVibration:  doVibrate,
        vibrationPattern: vibPattern,
        playSound:        playSound,
        fullScreenIntent: false,
      ),
      iOS: fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
    );
  }
}