// alarm_service.dart  — alarm ^5.5.0  (verified against official README)
//
// Stream API in v5.x:
//   Alarm.ringing.listen((AlarmSet alarmSet) { ... })
//   AlarmSet has a List<AlarmSettings> alarms field
//
// pubspec.yaml:
//   alarm: ^5.5.0
//   timezone: ^0.9.4
//
// flutter:
//   assets:
//     - assets/audio/alarm.mp3

import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder_model.dart';
import '../screens/alarm_screen.dart';
import 'reminder_service.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  /// Attach this to MaterialApp.navigatorKey so we can push AlarmScreen
  /// from outside the widget tree (including when the app is backgrounded).
  static final navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<dynamic>? _ringSub;

  // ── Init ──────────────────────────────────────────────────────

  /// Call once from main() after ReminderService.instance.init().
  Future<void> init() async {
    await Alarm.init();

    // v5.x correct API: Alarm.ringing returns a Stream<AlarmSet>
    // AlarmSet.alarms is List<AlarmSettings>
    _ringSub = Alarm.ringing.listen(_onAlarmRing);

    debugPrint('[AlarmService] ready (alarm v5.5.0).');
  }

  // ── Schedule ──────────────────────────────────────────────────

  /// Schedule a real device alarm for [reminder].
  /// Reminders sharing the same wall-clock minute get one alarm slot —
  /// _onAlarmRing collects all reminders due at that minute.
  Future<void> scheduleForReminder(Reminder reminder) async {
    if (reminder.isPast) return;

    final alarmId = _alarmId(reminder.dateTime);
    final dt = _truncateToMinute(reminder.dateTime);

    // Skip if a slot already exists for this minute.
    final existing = await Alarm.getAlarm(alarmId);
    if (existing != null) {
      debugPrint(
        '[AlarmService] slot $alarmId already set for $dt — skipping.',
      );
      return;
    }

    final settings = AlarmSettings(
      id: alarmId,
      dateTime: dt,
      assetAudioPath: 'assets/sounds/complete.mp3',
      loopAudio: true,
      vibrate: true,

      // warningNotificationOnKill is recommended for iOS only in v5
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent: true,

      // v5: volume lives inside VolumeSettings
   
      volumeSettings: VolumeSettings.fixed(
        volume: 0.9,
        volumeEnforced: true,
      ),

      notificationSettings: NotificationSettings(
        title: '⏰ FocusBell',
        body: reminder.title,
        stopButton: 'Stop',
        icon: 'notification_icon',
        iconColor: const Color(0xFFD4640A),
      ),
    );

    await Alarm.set(alarmSettings: settings);
    debugPrint('[AlarmService] alarm $alarmId set for $dt');
  }

  /// Cancel the alarm slot only if no other reminder still uses that minute.
  Future<void> cancelForReminder(Reminder reminder) async {
    final alarmId = _alarmId(reminder.dateTime);
    final minute = _truncateToMinute(reminder.dateTime);

    final others = ReminderService.instance.reminders.value
        .where(
          (r) => r.id != reminder.id && _truncateToMinute(r.dateTime) == minute,
        )
        .toList();

    if (others.isEmpty) {
      await Alarm.stop(alarmId);
      debugPrint('[AlarmService] alarm $alarmId cancelled.');
    } else {
      debugPrint(
        '[AlarmService] alarm $alarmId kept — ${others.length} other(s) at $minute.',
      );
    }
  }

  // ── Ring handler ──────────────────────────────────────────────

  /// Called by the package when one or more alarms fire.
  /// [alarmSet.alarms] contains every AlarmSettings that fired simultaneously.
  // alarm package exposes a stream with a package-defined type for the
  // fired alarms. Use a dynamic parameter to avoid analyzer errors when the
  // concrete class isn't available to the analyzer.
  void _onAlarmRing(dynamic alarmSet) {
    debugPrint('[AlarmService] ${alarmSet.alarms.length} alarm(s) fired.');

    // For each fired alarm, collect all reminders due at that minute.
    final Set<String> shownIds = {};
    final List<Reminder> due = [];

    for (final settings in alarmSet.alarms) {
      final alarmMinute = _truncateToMinute(settings.dateTime);
      final matching = ReminderService.instance.reminders.value
          .where(
            (r) =>
                !shownIds.contains(r.id) &&
                _truncateToMinute(r.dateTime) == alarmMinute,
          )
          .toList();
      for (final r in matching) {
        shownIds.add(r.id);
        due.add(r);
      }
    }

    if (due.isEmpty) {
      for (final s in alarmSet.alarms) Alarm.stop(s.id);
      return;
    }

    // Push AlarmScreen over whatever is currently showing.
    navigatorKey.currentState?.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => AlarmScreen(reminders: due),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ── Snooze / Stop ─────────────────────────────────────────────

  /// Snooze all listed reminders by 10 minutes and reschedule their alarm.
  Future<void> snoozeAll(List<Reminder> reminders) async {
    await Alarm.stop(_alarmId(reminders.first.dateTime));
    for (final r in reminders) {
      final snoozed = Reminder(
        id: r.id,
        title: r.title,
        dateTime: DateTime.now().add(const Duration(minutes: 10)),
      );
      await ReminderService.instance.remove(r.id);
      await ReminderService.instance.add(snoozed);
    }
    debugPrint(
      '[AlarmService] snoozed ${reminders.length} reminder(s) +10 min.',
    );
  }

  /// Stop alarm and permanently remove all listed reminders.
Future<void> stopAll(List<Reminder> reminders) async {
  await Alarm.stop(_alarmId(reminders.first.dateTime));
  for (final r in reminders) {
    if (r.isRepeating) {
      // Auto-queue next occurrence instead of deleting
      await ReminderService.instance.rescheduleRepeating(r);
    } else {
      await ReminderService.instance.remove(r.id);
    }
  }
  debugPrint(
    '[AlarmService] stopped ${reminders.length} reminder(s).',
  );
}

  void dispose() => _ringSub?.cancel();

  // ── Helpers ───────────────────────────────────────────────────

  int _alarmId(DateTime dt) =>
      _truncateToMinute(dt).millisecondsSinceEpoch ~/ 60000 % 0x7FFFFFFF;

  DateTime _truncateToMinute(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
}

/*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AndroidManifest.xml  (android/app/src/main/AndroidManifest.xml)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Inside <manifest> block:

    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>

Inside <application> block (v5 requires explicit service + receiver):

    <service
        android:name="com.gdelataillade.alarm.AlarmService"
        android:exported="false"
        android:foregroundServiceType="mediaPlayback"/>

    <receiver
        android:name="com.gdelataillade.alarm.AlarmReceiver"
        android:exported="false"/>

    <receiver
        android:name="com.gdelataillade.alarm.AlarmRebootReceiver"
        android:exported="false">
        <intent-filter>
            <action android:name="android.intent.action.BOOT_COMPLETED"/>
        </intent-filter>
    </receiver>

On your existing <activity> tag, add these two attributes:

    android:showWhenLocked="true"
    android:turnScreenOn="true"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
*/
