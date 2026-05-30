import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;

import '../models/project.dart';
import '../models/settings.dart';
import 'notification_service.dart';

// ── Entry point — MUST be top-level, MUST have this pragma ───────
// Dart's build tool needs to find this at compile time for the
// background isolate. Any error in this file breaks main.dart too.

@pragma('vm:entry-point')
void focusBellTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_FocusBellTaskHandler());
}

// ── Task handler ─────────────────────────────────────────────────

class _FocusBellTaskHandler extends TaskHandler {
  int _notifId = 200;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await NotificationService.instance.initialize();
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    final projectName   = await FlutterForegroundTask.getData<String>(key: 'projectName');
    final priorityLabel = await FlutterForegroundTask.getData<String>(key: 'priorityLabel');
    final priorityEmoji = await FlutterForegroundTask.getData<String>(key: 'priorityEmoji');
    final soundModeIdx  = await FlutterForegroundTask.getData<int>(key: 'soundModeIndex');

    if (projectName == null) return;

    final soundMode = SoundMode.values[soundModeIdx ?? 0];
    final details   = NotificationService.instance.buildDetails(soundMode);

    _notifId = (_notifId >= 299) ? 200 : _notifId + 1;

    await NotificationService.instance.plugin.show(
      _notifId,
      '$priorityEmoji Focus: $projectName',
      'Priority: $priorityLabel — stay locked in.',
      details,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

// ── Manager — called from the main isolate only ───────────────────

class ForegroundServiceManager {
  ForegroundServiceManager._();
  static final ForegroundServiceManager instance = ForegroundServiceManager._();

  void configure(AppSettings settings) {
    final intervalMs = settings.interval.minutes * 60 * 1000;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'focusbell_fg_service',
        channelName:        'FocusBell Active',
        channelDescription: 'Keeps focus reminders running in the background.',
        onlyAlertOnce:      true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound:        false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction:                ForegroundTaskEventAction.repeat(intervalMs),
        autoRunOnBoot:              true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock:              true,
        allowWifiLock:              false,
      ),
    );
  }

  Future<void> startOrUpdate(Project project, AppSettings settings) async {
    configure(settings);
    await _saveData(project, settings);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId:         300,
        notificationTitle: '${project.priority.emoji} FocusBell Active',
        notificationText:  'Reminding you every ${settings.interval.label}',
        callback:          focusBellTaskCallback,
      );
    }
  }

  Future<void> updateData(Project project, AppSettings settings) async {
    await _saveData(project, settings);
    await FlutterForegroundTask.updateService(
      notificationTitle: '${project.priority.emoji} FocusBell Active',
      notificationText:  'Reminding you every ${settings.interval.label}',
    );
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<void> _saveData(Project project, AppSettings settings) async {
    await FlutterForegroundTask.saveData(key: 'projectName',    value: project.name);
    await FlutterForegroundTask.saveData(key: 'priorityLabel',  value: project.priority.label);
    await FlutterForegroundTask.saveData(key: 'priorityEmoji',  value: project.priority.emoji);
    await FlutterForegroundTask.saveData(key: 'soundModeIndex', value: settings.soundMode.index);
  }
}