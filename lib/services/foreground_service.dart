import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart'; // add this import
import '../models/project.dart';
import '../models/settings.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void focusBellTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_FocusBellTaskHandler());
}

class _FocusBellTaskHandler extends TaskHandler {
  int _notifId = 200;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[FocusBell] Service started');

    await NotificationService.instance.initialize();

    debugPrint('[FocusBell] Notifications initialized');
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
        debugPrint('[FocusBell] Repeat fired: $timestamp');
        final projectName = await FlutterForegroundTask.getData<String>(
        key: 'projectName',
        );
        final priorityLabel = await FlutterForegroundTask.getData<String>(
        key: 'priorityLabel',
        );
        final priorityEmoji = await FlutterForegroundTask.getData<String>(
        key: 'priorityEmoji',
        );
        final soundModeIdx = await FlutterForegroundTask.getData<int>(
        key: 'soundModeIndex',
        );
        final taskSummary = await FlutterForegroundTask.getData<String>(
        key: 'taskSummary',
        );

        if (projectName == null) return;

        final soundMode = SoundMode.values[soundModeIdx ?? 0];

        // Collapsed body (one line shown before user expands).
        final collapsedBody =
            'Priority: ${priorityLabel ?? 'Unknown'} — stay locked in.';

        // Expanded body (shown when notification is pulled down).
        // Two separate lines joined with a real newline.
        final expandedBody = _buildExpandedBody(priorityLabel, taskSummary);

        final details = NotificationService.instance.buildDetails(
        soundMode,
        bigBody: expandedBody, // ← passed into BigTextStyleInformation
        );

        _notifId = (_notifId >= 299) ? 200 : _notifId + 1;

        await NotificationService.instance.plugin.show(
        _notifId,
        '$priorityEmoji Focus: $projectName',
        collapsedBody, // ← shown collapsed
        details,
        );
    } catch (e, st) {
        debugPrint('[FocusBell] Repeat failed: $e');
        debugPrint('$st');
    }
  }

  /// Collapsed line:  "Priority: Critical — stay locked in."
  /// Expanded line 2: "Tasks: 1/3 done · ⬜ To Do 2  🔵 Ongoing 1  ✅ Done 1  🔴 Blocked 0"
  String _buildExpandedBody(String? priorityLabel, String? taskSummary) {
    final line1 = 'Priority: ${priorityLabel ?? 'Unknown'} — stay locked in.';
    if (taskSummary == null || taskSummary.isEmpty) return line1;
    return '$line1\n$taskSummary';
  }

  /// Composes the notification body.
  ///
  /// Example output (with tasks):
  ///   "Priority: Critical — 1/3 done · ⬜ Write intro  🔵 Review PR  ✅ Setup env"
  ///
  /// Example output (no tasks):
  ///   "Priority: Critical — stay locked in."
  String _buildBody(String? priorityLabel, String? taskSummary) {
    final priority = 'Priority: ${priorityLabel ?? 'Unknown'}';
    if (taskSummary == null || taskSummary.isEmpty) {
      return '$priority — stay locked in.';
    }
    return '$priority — $taskSummary';
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class ForegroundServiceManager {
  ForegroundServiceManager._();
  static final ForegroundServiceManager instance = ForegroundServiceManager._();

  void configure(AppSettings settings) {
    final intervalMs = settings.interval.minutes * 60 * 1000;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'focusbell_fg_service',
        channelName: 'FocusBell Active',
        channelDescription: 'Keeps focus reminders running in the background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(intervalMs),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

Future<void> startOrUpdate(Project project, AppSettings settings) async {
    configure(settings);
    await _saveData(project, settings);

    if (await FlutterForegroundTask.isRunningService) {
      // Stop completely so the new eventAction interval is picked up.
      await FlutterForegroundTask.stopService();
    }

    await FlutterForegroundTask.startService(
      serviceId:         300,
      notificationTitle: '${project.priority.emoji} FocusBell Active',
      notificationText:  _buildServiceText(project, settings),
      callback:          focusBellTaskCallback,
    );

    await _requestBatteryOptimizationIfNeeded();
  }


  Future<void> _requestBatteryOptimizationIfNeeded() async {
    const key = 'battery_optimization_prompted';
    final prefs = await SharedPreferences.getInstance();
    final alreadyPrompted = prefs.getBool(key) ?? false;
    if (alreadyPrompted) return;

    await prefs.setBool(key, true);

    // Opens Android battery optimization settings for this app.
    // No-op on iOS.
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  Future<void> updateData(Project project, AppSettings settings) async {
    await _saveData(project, settings);
    await FlutterForegroundTask.updateService(
      notificationTitle: '${project.priority.emoji} FocusBell Active',
      notificationText: _buildServiceText(project, settings),
    );
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  // ── Persistent service notification text (the always-on bar notification) ──

  /// Shows task progress in the persistent foreground service notification.
  /// e.g. "Every 15 min · Tasks: 2/5 done"
  String _buildServiceText(Project project, AppSettings settings) {
    final base = 'Reminding you every ${settings.interval.label}';
    if (project.tasks.isEmpty) return base;

    final total     = project.tasks.length;
    final completed = project.tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;
    return '$base · Tasks: $completed/$total done';
  }

  // ── Data persistence for the background isolate ───────────────

  Future<void> _saveData(Project project, AppSettings settings) async {
    await FlutterForegroundTask.saveData(
      key: 'projectName',
      value: project.name,
    );
    await FlutterForegroundTask.saveData(
      key: 'priorityLabel',
      value: project.priority.label,
    );
    await FlutterForegroundTask.saveData(
      key: 'priorityEmoji',
      value: project.priority.emoji,
    );
    await FlutterForegroundTask.saveData(
      key: 'soundModeIndex',
      value: settings.soundMode.index,
    );

    // Build a compact task summary string for the reminder notification.
    // Stored as a plain string so the background isolate doesn't need
    // access to the Project model or database.
    await FlutterForegroundTask.saveData(
      key: 'taskSummary',
      value: _buildTaskSummary(project),
    );
  }

  /// Produces a one-liner task breakdown, e.g.:
  /// "1/3 done · ⬜ Write intro  🔵 Review PR  ✅ Setup env"
  ///
  /// Truncates to first 3 tasks with " …+N more" suffix if there are more,
  /// so the notification body stays readable on-screen.
  String _buildTaskSummary(Project project) {
    if (project.tasks.isEmpty) return '';

    final total = project.tasks.length;
    final completed = project.tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;
    final ongoing = project.tasks
        .where((t) => t.status == TaskStatus.ongoing)
        .length;
    final todo = project.tasks.where((t) => t.status == TaskStatus.todo).length;
    final blocked = project.tasks
        .where((t) => t.status == TaskStatus.blocked)
        .length;

    final progress = 'Tasks: $completed/$total done';
    final breakdown =
        '⬜ To Do $todo  🔵 Ongoing $ongoing  ✅ Done $completed  🔴 Blocked $blocked';

    return '$progress · $breakdown';
  }
}
