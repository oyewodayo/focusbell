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

  fln.FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const _channelBoth    = 'focusbell_both';
  static const _channelRing    = 'focusbell_ring';
  static const _channelVibrate = 'focusbell_vibrate';
  static const _channelSilent  = 'focusbell_silent';

  // ── Init ──────────────────────────────────────────────────────

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
        debugPrint('[Notifications] Tapped: ${details.payload}');
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        fln.AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await _recreateChannels(androidPlugin);
    }

    _initialized = true;
    debugPrint('[Notifications] Initialized.');
  }

  /// Deletes then recreates every channel so Android always picks up the
  /// correct sound/vibration settings, even if the channel was previously
  /// registered silently from an earlier build.
  Future<void> _recreateChannels(
    fln.AndroidFlutterLocalNotificationsPlugin androidPlugin,
  ) async {
    final vibPattern = Int64List.fromList([0, 400, 200, 400]);

    // Delete stale channels first — no-op if they don't exist yet.
    for (final id in [
      _channelBoth,
      _channelRing,
      _channelVibrate,
      _channelSilent,
    ]) {
      await androidPlugin.deleteNotificationChannel(id);
      debugPrint('[Notifications] Deleted channel: $id');
    }

    // Sound + Vibration
    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelBoth,
        'Focus Reminders (Sound + Vibration)',
        description:      'Reminders with sound and vibration.',
        importance:       fln.Importance.max,
        playSound:        true,
        enableVibration:  true,
        vibrationPattern: vibPattern,
      ),
    );

    // Sound only
    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelRing,
        'Focus Reminders (Sound)',
        description:     'Reminders with sound only.',
        importance:      fln.Importance.max,
        playSound:       true,
        enableVibration: false,
      ),
    );

    // Vibration only
    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelVibrate,
        'Focus Reminders (Vibration)',
        description:      'Reminders with vibration only.',
        importance:       fln.Importance.max,
        playSound:        false,
        enableVibration:  true,
        vibrationPattern: vibPattern,
      ),
    );

    // Silent
    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelSilent,
        'Focus Reminders (Silent)',
        description:     'Silent focus reminders.',
        importance:      fln.Importance.low,
        playSound:       false,
        enableVibration: false,
      ),
    );

    debugPrint('[Notifications] All channels recreated.');
  }

  // ── Permissions ───────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestExactAlarmsPermission();
      final granted = await android.requestNotificationsPermission();
      debugPrint('[Notifications] Android permission granted: $granted');
      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        fln.IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[Notifications] iOS permission granted: $granted');
      return granted ?? false;
    }

    return true;
  }

  // ── Instant notification ──────────────────────────────────────

  Future<void> showInstant(
    Project project, {
    SoundMode soundMode = SoundMode.both,
  }) async {
    debugPrint(
      '[Notifications] showInstant → ${project.name} | mode: $soundMode',
    );
    await _plugin.show(
      0,
      '${project.priority.emoji} Now focused: ${project.name}',
      "Priority set to ${project.priority.label}. You've got this!",
      buildDetails(soundMode),
      payload: project.id,
    );
  }

  // ── Cancel all ────────────────────────────────────────────────

  Future<void> cancelAll() => _plugin.cancelAll();

  // ── Build NotificationDetails ─────────────────────────────────

  fln.NotificationDetails buildDetails(SoundMode mode, {String? bigBody}) {
    final playSound = mode == SoundMode.ring  || mode == SoundMode.both;
    final doVibrate = mode == SoundMode.vibrate || mode == SoundMode.both;
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

    debugPrint(
      '[Notifications] buildDetails → channel: $channelId | '
      'sound: $playSound | vibrate: $doVibrate',
    );

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
        styleInformation: bigBody != null
            ? fln.BigTextStyleInformation(
                bigBody,
                contentTitle: null,
                summaryText:  null,
              )
            : null,
      ),
      iOS: fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      ),
    );
  }
}