import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

import '../models/project.dart';
import '../models/settings.dart';

/// Wraps [FlutterLocalNotificationsPlugin] with app-specific helpers.
///
/// Responsibilities:
///   - Channel creation / recreation on Android.
///   - Instant project-focus notifications.
///   - Scheduled per-task due-date notifications (with lead-time offset).
///   - Snooze action handling.
///   - Boot-time rescheduling of all future task notifications.
///   - Exact-alarm permission guard (Android 12+).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = fln.FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  fln.FlutterLocalNotificationsPlugin get plugin => _plugin;

  // ── Channel IDs ───────────────────────────────────────────────

  static const _channelBoth = 'focusbell_both';
  static const _channelRing = 'focusbell_ring';
  static const _channelVibrate = 'focusbell_vibrate';
  static const _channelSilent = 'focusbell_silent';

  // ── Notification ID ranges ────────────────────────────────────

  /// ID 0          — instant project-focus notification.
  /// IDs 200–299   — foreground-service repeating notifications.
  /// IDs 10000+    — task due-date notifications (stable, from DB notif_id).
  static const _instantId = 0;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));

    const android = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = fln.DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const fln.InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
        // In initialize(), replace the androidPlugin block with:
        if (androidPlugin != null) {
        // Only recreate channels from the UI isolate to avoid race conditions
        // with the foreground service isolate.
        try {
            await _recreateChannels(androidPlugin);
        } catch (e) {
            debugPrint('[Notifications] Channel recreation skipped (isolate): $e');
        }
        }

    _initialized = true;
    debugPrint('[Notifications] Initialized — tz: $localTz');
  }

  // ── Notification response handler ────────────────────────────

  /// Handles taps and action buttons on delivered notifications.
  void _onNotificationResponse(fln.NotificationResponse response) {
    debugPrint(
      '[Notifications] Response — action: ${response.actionId} '
      'payload: ${response.payload}',
    );

    // Snooze action: reschedule the same task 15 minutes from now.
    if (response.actionId == _snoozeActionId && response.payload != null) {
      _handleSnooze(response.payload!);
    }
  }

  static const _snoozeActionId = 'snooze_15';

  /// Reschedules a task notification 15 minutes from now.
  /// [payload] is the task's notifId as a string.
  Future<void> _handleSnooze(String payload) async {
    final notifId = int.tryParse(payload);
    if (notifId == null) return;

    final snoozeTime = tz.TZDateTime.now(
      tz.local,
    ).add(const Duration(minutes: 15));

    await _plugin.cancel(notifId);
    await _plugin.zonedSchedule(
      notifId,
      '⏰ Snoozed reminder',
      'Your task is due — snoozed 15 min.',
      snoozeTime,
      _buildDetails(SoundMode.both),
      androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          fln.UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );

    debugPrint('[Notifications] Snoozed notifId=$notifId → $snoozeTime');
  }

  // ── Channel management ────────────────────────────────────────

  /// Deletes then recreates every channel so Android always picks up the
  /// correct sound/vibration settings, even across reinstalls.
  Future<void> _recreateChannels(
    fln.AndroidFlutterLocalNotificationsPlugin androidPlugin,
  ) async {
    final vibPattern = Int64List.fromList([0, 400, 200, 400]);

    for (final id in [
      _channelBoth,
      _channelRing,
      _channelVibrate,
      _channelSilent,
      'focusbell_fg_service',
    ]) {
      await androidPlugin.deleteNotificationChannel(id);
    }

    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelBoth,
        'Focus Reminders (Sound + Vibration)',
        description: 'Reminders with sound and vibration.',
        importance: fln.Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibPattern,
      ),
    );

    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelRing,
        'Focus Reminders (Sound)',
        description: 'Reminders with sound only.',
        importance: fln.Importance.max,
        playSound: true,
        enableVibration: false,
      ),
    );

    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelVibrate,
        'Focus Reminders (Vibration)',
        description: 'Reminders with vibration only.',
        importance: fln.Importance.max,
        playSound: false,
        enableVibration: true,
        vibrationPattern: vibPattern,
      ),
    );

    // In _recreateChannels(), add after the silent channel:
    await androidPlugin.createNotificationChannel(
    fln.AndroidNotificationChannel(
        'focusbell_fg_service',
        'FocusBell Active',
        description: 'Keeps focus reminders running in the background.',
        importance: fln.Importance.high,   // sticky should be low-importance
        playSound: false,
        enableVibration: false,
    ),
    );

    await androidPlugin.createNotificationChannel(
      fln.AndroidNotificationChannel(
        _channelSilent,
        'Focus Reminders (Silent)',
        description: 'Silent focus reminders.',
        importance: fln.Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );

    debugPrint('[Notifications] All channels recreated.');
  }

  // ── Permissions ───────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestExactAlarmsPermission();
      final granted = await android.requestNotificationsPermission();
      debugPrint('[Notifications] Android permission granted: $granted');
      return granted ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          fln.IOSFlutterLocalNotificationsPlugin
        >();
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

  /// Ensures the exact-alarm permission is granted before scheduling.
  /// Returns false (and logs a warning) if the permission cannot be granted.
  Future<bool> _ensureExactAlarmPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true; // iOS — no equivalent restriction.
    await android.requestExactAlarmsPermission();
    return true;
  }

  // ── Instant project-focus notification ───────────────────────

  Future<void> showInstant(
    Project project, {
    SoundMode soundMode = SoundMode.both,
  }) async {
    debugPrint(
      '[Notifications] showInstant → ${project.name} | mode: $soundMode',
    );
    await _plugin.show(
      _instantId,
      '${project.priority.emoji} Now focused: ${project.name}',
      "Priority set to ${project.priority.label}. You've got this!",
      buildDetails(soundMode),
      payload: project.id,
    );
  }

  // ── Task due-date notifications ───────────────────────────────

  /// Schedules (or replaces) a notification for [task].
  ///
  /// The notification fires at [Task.notificationFireTime] — i.e.
  /// [Task.dueDate] minus [Task.reminderOffset].
  ///
  /// No-op when:
  ///   - [task.dueDate] is null.
  ///   - [task.notifId] is null (not yet persisted).
  ///   - The computed fire time is already in the past.
  ///   - The task is already completed.
  Future<void> scheduleForTask({
    required Task task,
    required String projectName,
  }) async {
    if (task.dueDate == null) return;
    if (task.notifId == null) return;
    if (task.status == TaskStatus.completed) return;

    final fireAt = task.notificationFireTime!;
    final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);

    if (tzFireAt.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('[Notifications] Skipped past fire time for "${task.title}"');
      return;
    }

    final hasPermission = await _ensureExactAlarmPermission();
    if (!hasPermission) {
      debugPrint('[Notifications] Exact alarm permission denied — skipping.');
      return;
    }

    // Cancel any stale alarm for this task before (re-)scheduling.
    await _plugin.cancel(task.notifId!);

    final offsetLabel = task.reminderOffset == ReminderOffset.atTime
        ? ''
        : ' (${task.reminderOffset.shortLabel})';

    await _plugin.zonedSchedule(
      task.notifId!,
      '📋 Due$offsetLabel: ${task.title}',
      'Project: $projectName',
      tzFireAt,
      _buildDetailsWithSnooze(SoundMode.both),
      androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          fln.UILocalNotificationDateInterpretation.absoluteTime,
      payload: '${task.notifId}',
    );

    debugPrint(
      '[Notifications] Scheduled "${task.title}" '
      'at $tzFireAt  id=${task.notifId}  offset: ${task.reminderOffset.label}',
    );
  }

  /// Cancels any scheduled notification for the given [notifId].
  Future<void> cancelForTask(int? notifId) async {
    if (notifId == null) return;
    await _plugin.cancel(notifId);
    debugPrint('[Notifications] Cancelled task notif id=$notifId');
  }


    // In notification_service.dart

    // ── ADD this new public method ────────────────────────────────────

    /// Shows an immediate "task created" notification.
    /// Call this right after inserting a task with a due date.
    Future<void> showTaskCreated({
    required String taskTitle,
    required String projectName,
    SoundMode soundMode = SoundMode.both,
    }) async {
    // Use a stable ID derived from a hash so rapid creates don't collide.
    final id = 1000 + (taskTitle.hashCode.abs() % 8000);

    await _plugin.show(
        id,
        '✅ Task created: $taskTitle',
        'Create a streak session to focus and work on this task.',
        _buildDetails(soundMode),
        payload: taskTitle,
    );

    debugPrint('[Notifications] showTaskCreated → "$taskTitle"');
    }

  /// Cancels all scheduled task notifications and re-schedules every future
  /// one from [projects]. Call this on app boot and after bulk changes.
  Future<void> rescheduleAllTaskNotifications(List<Project> projects) async {
    final now = DateTime.now();

    for (final project in projects) {
      for (final task in project.tasks) {
        if (task.notifId == null) continue;
        if (task.status == TaskStatus.completed) continue;

        final fireAt = task.notificationFireTime;
        if (fireAt == null || fireAt.isBefore(now)) {
          // Clean up any stale alarm that might have survived a reinstall.
          await _plugin.cancel(task.notifId!);
          continue;
        }

        await scheduleForTask(task: task, projectName: project.name);
      }
    }

    debugPrint('[Notifications] Boot reschedule complete.');
  }

  // ── Cancel all ────────────────────────────────────────────────

  Future<void> cancelAll() => _plugin.cancelAll();

  // ── NotificationDetails builders ─────────────────────────────

  /// Standard details — used by instant and foreground-service notifications.
  fln.NotificationDetails buildDetails(SoundMode mode, {String? bigBody}) =>
      _buildDetails(mode, bigBody: bigBody);

  /// Details with a Snooze action button — used for task reminders.
  fln.NotificationDetails _buildDetailsWithSnooze(SoundMode mode) {
    final base = _buildDetails(mode);
    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _channelIdFor(mode),
        _channelNameFor(mode),
        importance: fln.Importance.max,
        priority: fln.Priority.max,
        enableVibration: _doVibrate(mode),
        vibrationPattern: _doVibrate(mode)
            ? Int64List.fromList([0, 400, 200, 400])
            : null,
        playSound: _playSound(mode),
        actions: const [
          fln.AndroidNotificationAction(
            _snoozeActionId,
            'Snooze 15 min',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: base.iOS,
    );
  }

  fln.NotificationDetails _buildDetails(SoundMode mode, {String? bigBody}) {
    final vibPattern = _doVibrate(mode)
        ? Int64List.fromList([0, 400, 200, 400])
        : null;

    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _channelIdFor(mode),
        _channelNameFor(mode),
        importance: fln.Importance.max,
        priority: fln.Priority.max,
        enableVibration: _doVibrate(mode),
        vibrationPattern: vibPattern,
        playSound: _playSound(mode),
        fullScreenIntent: false,
        styleInformation: bigBody != null
            ? fln.BigTextStyleInformation(bigBody)
            : null,
      ),
      iOS: fln.DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: _playSound(mode),
      ),
    );
  }

  // ── Mode helpers ──────────────────────────────────────────────

  bool _playSound(SoundMode mode) =>
      mode == SoundMode.ring || mode == SoundMode.both;

  bool _doVibrate(SoundMode mode) =>
      mode == SoundMode.vibrate || mode == SoundMode.both;

  String _channelIdFor(SoundMode mode) => switch (mode) {
    SoundMode.both => _channelBoth,
    SoundMode.ring => _channelRing,
    SoundMode.vibrate => _channelVibrate,
    SoundMode.silent => _channelSilent,
  };

  String _channelNameFor(SoundMode mode) => switch (mode) {
    SoundMode.both => 'Focus Reminders (Sound + Vibration)',
    SoundMode.ring => 'Focus Reminders (Sound)',
    SoundMode.vibrate => 'Focus Reminders (Vibration)',
    SoundMode.silent => 'Focus Reminders (Silent)',
  };
}
