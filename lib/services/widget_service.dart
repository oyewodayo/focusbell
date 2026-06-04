// lib/services/widget_service.dart
//
// Bridges Flutter state → Android home-screen / lock-screen widget.
//
// ── How it works ─────────────────────────────────────────────────────────────
//   1.  home_widget.saveWidgetData() writes key-value pairs into a shared
//       SharedPreferences file that the native AppWidgetProvider can read.
//   2.  home_widget.updateWidget() sends ACTION_APPWIDGET_UPDATE to the
//       provider so it redraws immediately.
//   3.  We never throw from push() — a widget update failure must never
//       crash the app.
//
// ── Throttling ───────────────────────────────────────────────────────────────
//   AppController calls push() on every state mutation, which is fine for
//   project switches / priority changes.  The timer ticker (FocusTimerService)
//   also calls push() every tick but _timerPushThrottle gates it to at most
//   once every 30 seconds to protect battery.
//
// ── qualifiedAndroidName ─────────────────────────────────────────────────────
//   MUST match  android:name  in the <receiver> block of AndroidManifest.xml.
//   If you renamed the package, change _kQualifiedProvider below.
//   Mismatch = widget silently never updates (the #1 bug source).

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/project.dart';
import 'focus_timer_service.dart';

class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  // ── Android provider class name (must match AndroidManifest.xml) ──────────
  //
  // Replace the package prefix if yours differs.
  // Check:  android/app/src/main/AndroidManifest.xml  → package="..."
  //
  static const _kProviderName   = 'FocusWidgetProvider';
  static const _kQualifiedProvider =
      'com.example.focusbell.FocusWidgetProvider'; // ← update if needed

  // ── iOS app group (needed when you add the Swift WidgetKit extension) ──────
  static const _kAppGroupId = 'group.com.example.focusbell';

  // ── Throttle: timer ticks fire push() very often; gate widget I/O ─────────
  static const _kTimerThrottle = Duration(seconds: 30);
  DateTime? _lastTimerPush;

  // ── One-time setup called from main() before runApp ───────────────────────
  Future<void> init() async {
    try {
      // Registers the iOS app group so home_widget can find the shared container.
      await HomeWidget.setAppGroupId(_kAppGroupId);
    } catch (e) {
      debugPrint('[WidgetService] init() error: $e');
    }
  }

  // ── Primary entry-point ───────────────────────────────────────────────────
  //
  // [activeProject] — pass AppController.instance.activeProject.
  // [fromTimer]     — true when called from the FocusTimerService tick so
  //                   throttling is applied.
  Future<void> push({
    Project? activeProject,
    bool fromTimer = false,
  }) async {
    // Throttle timer-driven updates.
    if (fromTimer) {
      final now = DateTime.now();
      if (_lastTimerPush != null &&
          now.difference(_lastTimerPush!) < _kTimerThrottle) {
        return;
      }
      _lastTimerPush = now;
    }

    try {
      await _writeData(activeProject);
      await HomeWidget.updateWidget(
        androidName:          _kProviderName,
        qualifiedAndroidName: _kQualifiedProvider,
        iOSName:              'FocusBellWidget', // matches Swift struct name
      );
    } catch (e) {
      // Never propagate — a widget failure must not affect the app.
      debugPrint('[WidgetService] push() error: $e');
    }
  }

  // ── Write all keys the native provider reads ──────────────────────────────
  Future<void> _writeData(Project? p) async {
    final timer = FocusTimerService.instance;

    // Key: active_project_name
    await HomeWidget.saveWidgetData<String>(
      'active_project_name',
      p?.name ?? 'No active project',
    );

    // Key: active_priority_dot  (emoji used in the widget TextView)
    await HomeWidget.saveWidgetData<String>(
      'active_priority_dot',
      _priorityDot(p),
    );

    // Key: active_priority_label  (e.g. "CRITICAL")
    await HomeWidget.saveWidgetData<String>(
      'active_priority_label',
      p != null ? p.priority.label.toUpperCase() : '',
    );

    // Key: session_timer_text  (human-readable elapsed or idle state)
    await HomeWidget.saveWidgetData<String>(
      'session_timer_text',
      _timerText(timer, p),
    );

    // Key: session_running  (boolean as int, 1 = running)
    await HomeWidget.saveWidgetData<int>(
      'session_running',
      (p != null && timer.state.isRunning) ? 1 : 0,
    );

    // Key: task_summary  (e.g. "3 tasks · 1 overdue")
    await HomeWidget.saveWidgetData<String>(
      'task_summary',
      _taskSummary(p),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _priorityDot(Project? p) {
    if (p == null) return '⚪';
    switch (p.priority.label.toLowerCase()) {
      case 'critical': return '🔴';
      case 'high':     return '🟠';
      case 'medium':   return '🟡';
      case 'low':      return '🟢';
      default:         return '⚪';
    }
  }

  String _timerText(FocusTimerService t, Project? p) {
    final s = t.state;
    // Show remaining time when running or paused; idle/finished = no session.
    if (p == null || s.isIdle || s.isFinished) return '⏱ No active session';
    // FocusTimerState exposes remainingSeconds; derive mm:ss directly.
    final rem = s.remainingSeconds;
    final h   = rem ~/ 3600;
    final mm  = (rem % 3600 ~/ 60).toString().padLeft(2, '0');
    final ss  = (rem % 60).toString().padLeft(2, '0');
    final prefix = s.isRunning ? '⏱' : '⏸'; // ⏸ when paused
    return h > 0 ? '$prefix ${h}h $mm:$ss' : '$prefix $mm:$ss';
  }

  String _taskSummary(Project? p) {
    if (p == null || p.tasks.isEmpty) return '';
    final incomplete = p.tasks.where((t) => t.status != TaskStatus.completed).length;
    final overdue    = p.tasks.where((t) => t.isOverdue).length;
    final parts      = <String>[];
    if (incomplete > 0) parts.add('$incomplete task${incomplete == 1 ? '' : 's'}');
    if (overdue    > 0) parts.add('$overdue overdue');
    return parts.join(' · ');
  }

  // ── Called from FocusTimerService when a session ends ────────────────────
  //
  // Resets the throttle so the "No active session" state appears immediately.
  Future<void> pushSessionEnded({Project? activeProject}) async {
    _lastTimerPush = null;
    await push(activeProject: activeProject);
  }
}