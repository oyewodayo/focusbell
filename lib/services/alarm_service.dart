// services/alarm_service.dart — FULL REPLACEMENT
// Adds: silenceAlarm(), stopAlarm() used by the new AlarmScreen
// Focus Guard integration: checks FocusTimerService before ringing

import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder_model.dart';
import '../screens/alarm_screen.dart';
import '../services/focus_timer_service.dart';
import 'reminder_service.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<dynamic>? _ringSub;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    await Alarm.init();
    _ringSub = Alarm.ringing.listen(_onAlarmRing);
    debugPrint('[AlarmService] ready (alarm v5.5.0).');
  }

  // ── Schedule ──────────────────────────────────────────────────

  Future<void> scheduleForReminder(Reminder reminder) async {
    if (reminder.isPast) return;

    final alarmId = _alarmId(reminder.dateTime);
    final dt      = _truncateToMinute(reminder.dateTime);

    final existing = await Alarm.getAlarm(alarmId);
    if (existing != null) {
      debugPrint('[AlarmService] slot $alarmId already set for $dt — skipping.');
      return;
    }

    final settings = AlarmSettings(
      id:             alarmId,
      dateTime:       dt,
      assetAudioPath: 'assets/sounds/complete.wav',
      loopAudio:      true,
      vibrate:        true,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent:   true,
      volumeSettings: VolumeSettings.fixed(volume: 0.9, volumeEnforced: true),
      notificationSettings: NotificationSettings(
        title:       '⏰ FocusBell',
        body:        reminder.title,
        stopButton:  'Dismiss',
        icon:        'notification_icon',
        iconColor:   const Color(0xFFD4640A),
      ),
    );

    await Alarm.set(alarmSettings: settings);
    debugPrint('[AlarmService] alarm $alarmId set for $dt');
  }

  Future<void> cancelForReminder(Reminder reminder) async {
    final alarmId = _alarmId(reminder.dateTime);
    final minute  = _truncateToMinute(reminder.dateTime);

    final others = ReminderService.instance.reminders.value
        .where((r) =>
            r.id != reminder.id &&
            _truncateToMinute(r.dateTime) == minute)
        .toList();

    if (others.isEmpty) {
      await Alarm.stop(alarmId);
      debugPrint('[AlarmService] alarm $alarmId cancelled.');
    } else {
      debugPrint('[AlarmService] alarm $alarmId kept — ${others.length} other(s) at $minute.');
    }
  }

  // ── Ring handler ──────────────────────────────────────────────

  void _onAlarmRing(dynamic alarmSet) {
    debugPrint('[AlarmService] ${alarmSet.alarms.length} alarm(s) fired.');

    final Set<String>  shownIds = {};
    final List<Reminder> due    = [];

    for (final settings in alarmSet.alarms) {
      final alarmMinute = _truncateToMinute(settings.dateTime);
      final matching = ReminderService.instance.reminders.value
          .where((r) =>
              !shownIds.contains(r.id) &&
              _truncateToMinute(r.dateTime) == alarmMinute)
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

    // ── Feature #6: Focus Guard ───────────────────────────────
    // If a focus session is running or paused, queue silently.
    // AlarmScreen will show the "Held for focus" UI and the
    // FocusGuardQueue will release them when the session ends.
    final focusActive = FocusTimerService.instance.state.isActive;
    if (focusActive) {
      debugPrint('[AlarmService] Focus session active — holding ${due.length} reminder(s).');
      FocusGuardQueue.instance.hold(due);
      // Stop audio immediately — don't interrupt the session
      for (final s in alarmSet.alarms) Alarm.stop(s.id);
      // Still push the screen so user sees "Held for focus" if they look
      _pushAlarmScreen(due);
      return;
    }

    _pushAlarmScreen(due);
  }

  void _pushAlarmScreen(List<Reminder> due) {
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

  // ── Silence / Stop (called from AlarmScreen) ──────────────────

  /// Stops alarm audio only — does NOT remove reminders.
  /// Used by Focus Guard to silence without dismissing.
  Future<void> silenceAlarm(List<Reminder> reminders) async {
    if (reminders.isEmpty) return;
    final alarmId = _alarmId(reminders.first.dateTime);
    await Alarm.stop(alarmId);
    debugPrint('[AlarmService] silenced alarm $alarmId (focus guard).');
  }

  /// Stops alarm audio. Used by the Snooze action —
  /// ReminderService.snoozeAll() reschedules the reminders separately.
  Future<void> stopAlarm(List<Reminder> reminders) async {
    if (reminders.isEmpty) return;
    final alarmId = _alarmId(reminders.first.dateTime);
    await Alarm.stop(alarmId);
    debugPrint('[AlarmService] stopped alarm $alarmId (snooze).');
  }

  /// Stops alarm audio and reschedules repeating reminders to their next
  /// occurrence. Used by the Done action.
  ///
  /// Non-repeating reminders are deliberately left in place — they should
  /// only disappear when the user deletes them, or via the auto-delete
  /// grace period configured in Settings (see ReminderService.sweepAutoDelete).
  Future<void> stopAll(List<Reminder> reminders) async {
    if (reminders.isEmpty) return;
    await Alarm.stop(_alarmId(reminders.first.dateTime));
    for (final r in reminders) {
      if (r.isRepeating) {
        await ReminderService.instance.rescheduleRepeating(r);
      }
    }
    debugPrint('[AlarmService] stopped alarm for ${reminders.length} reminder(s).');
  }

  void dispose() => _ringSub?.cancel();

  // ── Helpers ───────────────────────────────────────────────────

  int _alarmId(DateTime dt) =>
      _truncateToMinute(dt).millisecondsSinceEpoch ~/ 60000 % 0x7FFFFFFF;

  DateTime _truncateToMinute(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
}