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

  static const _channelId = 'focusbell_reminders';
  static const _channelName = 'Focus Reminders';
  static const _channelDesc = 'Periodic reminders about your priority project.';

  Future<void> initialize() async {
    if (_initialized) return;

    // ── 1. Set timezone correctly ──────────────────────────────
    tz.initializeTimeZones();
    final String localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));

    // ── 2. Init plugin ─────────────────────────────────────────
    const android = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = fln.DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const fln.InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        print('Notification tapped: ${details.payload}');
      },
    );

    _initialized = true;
  }

    Future<bool> requestPermissions() async {
    // Android 13+ runtime permission
    final android = _plugin.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
    }

    // iOS
    final ios = _plugin.resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
        final granted = await ios.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
    }

    return true; // Android < 13
    }
    Future<void> scheduleReminders(Project project, AppSettings settings) async {
    await cancelAll();
    if (!settings.notificationsEnabled) return;

    final intervalMins = settings.interval.minutes;
    final now = tz.TZDateTime.now(tz.local);

    int scheduled = 0;
    for (int i = 1; i <= 200 && scheduled < 64; i++) {
      final time = now.add(Duration(minutes: intervalMins * i));
      if (_isQuietHour(time.hour, settings)) continue;

      await _plugin.zonedSchedule(
        100 + scheduled,
        '${project.priority.emoji} Focus: ${project.name}',
        'Priority: ${project.priority.label} — stay locked in.',
        time,
        _notificationDetails(),
        uiLocalNotificationDateInterpretation:
            fln.UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        payload: null,
      );
      scheduled++;
    }

    print('[NotificationService] Scheduled $scheduled reminders '
        'every $intervalMins min from ${now.toIso8601String()}');
  }

  Future<void> showInstant(Project project) async {
    await _plugin.show(
      0,
      '${project.priority.emoji} Now focused: ${project.name}',
      'Priority set to ${project.priority.label}. You\'ve got this!',
      _notificationDetails(),
      payload: null,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  bool _isQuietHour(int hour, AppSettings s) {
    if (s.quietStartHour > s.quietEndHour) {
      // Wraps midnight e.g. 22:00 → 06:00
      return hour >= s.quietStartHour || hour < s.quietEndHour;
    }
    return hour >= s.quietStartHour && hour < s.quietEndHour;
  }

  fln.NotificationDetails _notificationDetails() =>
      const fln.NotificationDetails(
        android: fln.AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: fln.Importance.max,   // max, not just high
          priority: fln.Priority.max,
          enableVibration: true,
          playSound: true,
          fullScreenIntent: false,
        ),
        iOS: fln.DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
}