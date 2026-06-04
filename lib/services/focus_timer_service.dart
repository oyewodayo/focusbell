// services/focus_timer_service.dart  — FULL REPLACEMENT v5
//
// Changes from v4:
//   • import widget_service.dart + app_controller.dart
//   • DateTime? _lastWidgetPush field added
//   • _pushWidgetThrottled() private method added
//   • _tick() calls _pushWidgetThrottled() every tick (throttled to 30 s)
//   • start()  → _lastWidgetPush = null so first tick after (re)start pushes immediately
//   • stop()   → WidgetService.instance.pushSessionEnded() — clears timer text on widget
//   • reset()  → same as stop()
//   • skip()   → same as stop()
//   • _onSegmentComplete() → same as stop() at the moment the segment finishes
//   Everything else is byte-for-byte identical to v4.

import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Priority;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/focus_session.dart';
import '../models/focus_settings.dart';
import '../models/project.dart';
import 'app_controller.dart';   // ← NEW
import 'storage_service.dart';
import 'widget_service.dart';   // ← NEW

// ── Timer phase ───────────────────────────────────────────────────

enum TimerPhase { idle, running, paused, finished }

// ── Timer state ───────────────────────────────────────────────────

class FocusTimerState {
  final TimerPhase phase;
  final SessionType sessionType;
  final TimerPreset preset;
  final int totalSeconds;
  final int remainingSeconds;
  final int completedWork;
  final String? projectId;
  final String? projectName;

  const FocusTimerState({
    required this.phase,
    required this.sessionType,
    required this.preset,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.completedWork,
    this.projectId,
    this.projectName,
  });

  bool get isRunning  => phase == TimerPhase.running;
  bool get isActive   => phase == TimerPhase.running || phase == TimerPhase.paused;
  bool get isWork     => sessionType == SessionType.work;
  bool get isIdle     => phase == TimerPhase.idle;
  bool get isFinished => phase == TimerPhase.finished;

  double get progress =>
      totalSeconds == 0 ? 0 : 1 - (remainingSeconds / totalSeconds);

  String get mmss {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  FocusTimerState copyWith({
    TimerPhase?   phase,
    SessionType?  sessionType,
    TimerPreset?  preset,
    int?          totalSeconds,
    int?          remainingSeconds,
    int?          completedWork,
    String?       projectId,
    String?       projectName,
  }) => FocusTimerState(
    phase:            phase            ?? this.phase,
    sessionType:      sessionType      ?? this.sessionType,
    preset:           preset           ?? this.preset,
    totalSeconds:     totalSeconds     ?? this.totalSeconds,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    completedWork:    completedWork    ?? this.completedWork,
    projectId:        projectId        ?? this.projectId,
    projectName:      projectName      ?? this.projectName,
  );

  static FocusTimerState initial(TimerPreset preset) => FocusTimerState(
    phase:            TimerPhase.idle,
    sessionType:      SessionType.work,
    preset:           preset,
    totalSeconds:     preset.workMinutes * 60,
    remainingSeconds: preset.workMinutes * 60,
    completedWork:    0,
  );

  Map<String, dynamic> toJson() => {
    'phase':            phase.index,
    'sessionType':      sessionType.index,
    'preset':           preset.index,
    'totalSeconds':     totalSeconds,
    'remainingSeconds': remainingSeconds,
    'completedWork':    completedWork,
    'projectId':        projectId,
    'projectName':      projectName,
  };

  factory FocusTimerState.fromJson(Map<String, dynamic> j) => FocusTimerState(
    phase:            TimerPhase.values[j['phase'] as int],
    sessionType:      SessionType.values[j['sessionType'] as int],
    preset:           TimerPreset.values[j['preset'] as int],
    totalSeconds:     j['totalSeconds']     as int,
    remainingSeconds: j['remainingSeconds'] as int,
    completedWork:    j['completedWork']    as int,
    projectId:        j['projectId']        as String?,
    projectName:      j['projectName']      as String?,
  );
}

// ── Service ───────────────────────────────────────────────────────

class FocusTimerService extends ChangeNotifier {
  FocusTimerService._();
  static final FocusTimerService instance = FocusTimerService._();

  // ── Prefs keys ────────────────────────────────────────────────

  static const _kStateKey  = 'focus_timer_state';
  static const _kStartedAt = 'focus_timer_started_at';
  static const _kSettings  = 'focus_settings';

  // ── State ─────────────────────────────────────────────────────

  FocusTimerState _state    = FocusTimerState.initial(TimerPreset.pomodoro);
  FocusSettings   _settings = const FocusSettings();

  FocusTimerState get state    => _state;
  FocusSettings   get settings => _settings;

  /// True when the segment just finished — UI reads this to show the dialog.
  bool _pendingFinished = false;
  bool get pendingFinished => _pendingFinished;
  void clearPendingFinished() {
    _pendingFinished = false;
  }

  Timer?    _ticker;
  Timer?    _alarmStopTimer; // stops alarm after ~5 s if not manually dismissed
  DateTime? _segmentStart;

  // ── Widget throttle ───────────────────────────────────────────  ← NEW

  /// Guards against pushing the widget on every single 1-second tick.
  /// We allow one push per [_kWidgetThrottle] while the timer is running.
  static const _kWidgetThrottle = Duration(seconds: 30);
  DateTime? _lastWidgetPush;                                        // ← NEW

  // ── Audio ─────────────────────────────────────────────────────

  final _tickPlayer  = AudioPlayer();
  final _alarmPlayer = AudioPlayer();

  // ── Notifications ─────────────────────────────────────────────

  final _notif    = FlutterLocalNotificationsPlugin();
  bool  _notifReady = false;

  // ── Storage ───────────────────────────────────────────────────

  SharedPreferences? _prefs;
  StorageService?    _storage;
  Future<StorageService> get _store async =>
      _storage ??= await StorageService.getInstance();

  // ─────────────────────────────────────────────────────────────
  // BOOT
  // ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    _prefs    = await SharedPreferences.getInstance();
    _settings = FocusSettings.fromPrefs(_prefs!.getString(_kSettings));

    // ── Audio setup ──────────────────────────────────────────

    await _tickPlayer.setVolume(0.5);
    await _tickPlayer.setReleaseMode(ReleaseMode.loop);
    await _tickPlayer.setSource(AssetSource('sounds/tick.mp3'));

    await _alarmPlayer.setVolume(1.0);
    await _alarmPlayer.setReleaseMode(ReleaseMode.stop);
    await _alarmPlayer.setSource(AssetSource('sounds/complete.wav'));

    // ── Notifications setup ──────────────────────────────────

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notif.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _notifReady = true;

    // ── Restore persisted state ──────────────────────────────

    final raw = _prefs!.getString(_kStateKey);
    if (raw != null) {
      try {
        final saved = FocusTimerState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );

        if (saved.phase == TimerPhase.running) {
          final startRaw = _prefs!.getString(_kStartedAt);
          if (startRaw != null) {
            _segmentStart = DateTime.parse(startRaw);
            final elapsed   = DateTime.now().difference(_segmentStart!).inSeconds;
            final remaining = (saved.remainingSeconds - elapsed)
                .clamp(0, saved.totalSeconds);

            if (remaining <= 0) {
              // Completed while backgrounded — advance, wait for user tap.
              _state = saved.copyWith(remainingSeconds: 0);
              await _endSegment(completed: true, stateOverride: _state);
              _advanceToNextSegment();
              _pendingFinished = true;
              _saveState();
              // Push widget so it shows "No active session" after bg completion.
              _pushWidgetThrottled(force: true);                    // ← NEW
            } else {
              _state = saved.copyWith(remainingSeconds: remaining);
              _resumeTicker();
              if (_settings.tickEnabled) _startTick();
            }
          } else {
            _state = saved.copyWith(phase: TimerPhase.paused);
          }
        } else {
          _state = saved;
        }
        notifyListeners();
      } catch (e) {
        debugPrint('[FocusTimerService] Restore failed: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────

  void configure({
    required TimerPreset preset,
    required String      projectId,
    required String      projectName,
  }) {
    if (_state.isActive && _state.projectId != null) return;
    _cancelTicker();
    _stopTick();
    _state = FocusTimerState.initial(preset)
        .copyWith(projectId: projectId, projectName: projectName);
    _saveState();
    notifyListeners();
  }

  void start() {
    if (_state.phase == TimerPhase.running) return;
    _segmentStart ??= DateTime.now();
    _prefs?.setString(_kStartedAt, _segmentStart!.toIso8601String());
    _state = _state.copyWith(phase: TimerPhase.running);
    _saveState();

    // Reset throttle so the widget updates immediately on the first tick
    // after any (re)start rather than waiting up to 30 s.             ← NEW
    _lastWidgetPush = null;                                            // ← NEW

    _resumeTicker();
    if (_settings.tickEnabled) _startTick();
    notifyListeners();

    _fireNotif(
      id:      1,
      title:   _state.isWork
          ? '🔴 Focus session started'
          : '${_state.sessionType.emoji} ${_state.sessionType.label} started',
      body:    '${_state.totalSeconds ~/ 60} min · ${_state.projectName ?? ''}',
      ongoing: _state.isWork && _settings.strictMode,
    );
  }

  void pause() {
    if (_state.phase != TimerPhase.running) return;
    _cancelTicker();
    _stopTick();
    _state = _state.copyWith(phase: TimerPhase.paused);
    _saveState();
    notifyListeners();
    _cancelNotif(1);
    // Paused — push widget so timer text freezes at current value.    ← NEW
    _pushWidgetThrottled(force: true);                                 // ← NEW
  }

  void resume() => start();

  void reset() {
    _cancelTicker();
    _stopTick();
    _stopAlarm();
    _state = FocusTimerState.initial(_state.preset)
        .copyWith(projectId: _state.projectId, projectName: _state.projectName);
    _pendingFinished = false;
    _segmentStart    = null;
    _prefs?.remove(_kStartedAt);
    _saveState();
    _cancelNotif(1);
    notifyListeners();
    // Session ended — push "No active session" to widget immediately. ← NEW
    WidgetService.instance.pushSessionEnded(                           // ← NEW
      activeProject: AppController.instance.activeProject,            // ← NEW
    );                                                                 // ← NEW
  }

  Future<void> skip() async {
    _cancelTicker();
    _stopTick();
    await _endSegment(completed: false);
    _advanceToNextSegment();
    _cancelNotif(1);
    // Skipped segment — widget shows idle state of the next segment.  ← NEW
    WidgetService.instance.pushSessionEnded(                           // ← NEW
      activeProject: AppController.instance.activeProject,            // ← NEW
    );                                                                 // ← NEW
  }

  void stop() {
    _cancelTicker();
    _stopTick();
    _stopAlarm();
    _state = FocusTimerState.initial(_state.preset)
        .copyWith(projectId: _state.projectId, projectName: _state.projectName);
    _pendingFinished = false;
    _segmentStart    = null;
    _prefs?.remove(_kStartedAt);
    _saveState();
    _cancelNotif(1);
    notifyListeners();
    // Session stopped — push "No active session" to widget immediately. ← NEW
    WidgetService.instance.pushSessionEnded(                            // ← NEW
      activeProject: AppController.instance.activeProject,             // ← NEW
    );                                                                  // ← NEW
  }

  void stopAlarmManually() => _stopAlarm();

  // ── Settings API ──────────────────────────────────────────────

  void updateSettings(FocusSettings updated) {
    _settings = updated;
    _prefs?.setString(_kSettings, updated.toPrefs());
    if (_state.isRunning) {
      if (updated.tickEnabled) {
        _startTick();
      } else {
        _stopTick();
      }
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // AUDIO
  // ─────────────────────────────────────────────────────────────

  void _startTick() => _tickPlayer.resume();
  void _stopTick()  => _tickPlayer.stop();

  Future<void> _ringAlarm() async {
    await _alarmPlayer.seek(Duration.zero);
    await _alarmPlayer.resume();
    _alarmStopTimer?.cancel();
    _alarmStopTimer = Timer(const Duration(seconds: 5), _stopAlarm);
  }

  void _stopAlarm() {
    _alarmStopTimer?.cancel();
    _alarmPlayer.stop();
  }

  // ─────────────────────────────────────────────────────────────
  // TICKER
  // ─────────────────────────────────────────────────────────────

  void _resumeTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer _) {
    final next = _state.remainingSeconds - 1;
    _state = _state.copyWith(remainingSeconds: next);
    notifyListeners();

    // Push the running timer text to the widget (throttled).          ← NEW
    _pushWidgetThrottled();                                            // ← NEW

    if (next <= 0) {
      _cancelTicker();
      _stopTick();
      Future.microtask(_onSegmentComplete);
      return;
    }
    if (next % 5 == 0) _saveState();
  }

  // ─────────────────────────────────────────────────────────────
  // WIDGET PUSH  (NEW)
  // ─────────────────────────────────────────────────────────────

  /// Pushes current timer + project state to the Android home-screen widget.
  ///
  /// [force] = true bypasses the 30-second throttle — use at start/stop/pause
  /// moments where the state change is significant and must appear immediately.
  ///
  /// Errors are swallowed inside [WidgetService.push]; they must never
  /// propagate into the timer loop.
  void _pushWidgetThrottled({bool force = false}) {
    if (!force) {
      final now = DateTime.now();
      if (_lastWidgetPush != null &&
          now.difference(_lastWidgetPush!) < _kWidgetThrottle) {
        return; // too soon — skip this tick
      }
      _lastWidgetPush = now;
    } else {
      // Force push — also resets the clock so the next normal push
      // waits a full throttle interval from this moment.
      _lastWidgetPush = DateTime.now();
    }

    // fire-and-forget — must not await inside a 1-second ticker
    WidgetService.instance.push(
      activeProject: AppController.instance.activeProject,
      fromTimer:     true,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SEGMENT LIFECYCLE
  // ─────────────────────────────────────────────────────────────

  Future<void> _onSegmentComplete() async {
    // 1. Snap to 00:00.
    _state = _state.copyWith(remainingSeconds: 0);
    notifyListeners();

    // 2. Push widget immediately — "00:00" should appear before alarm rings.
    _pushWidgetThrottled(force: true);                                 // ← NEW

    // 3. Save record.
    final wasWork = _state.isWork;
    await _endSegment(completed: true);

    // 4. Ring alarm LOUDLY — always, regardless of autostart.
    await _ringAlarm();

    // 5. Brief delay so the alarm plays before any state transition.
    await Future.delayed(const Duration(milliseconds: 800));

    // 6. Advance to next segment (phase = idle, timer loaded, NOT started).
    _advanceToNextSegment();

    // 7. Fire the "segment complete" notification.
    _fireNotif(
      id:    2,
      title: wasWork ? '✅ Focus session complete!' : '⚡ Break time is over!',
      body:  wasWork
          ? 'Great work on "${_state.projectName ?? 'your project'}"! Time for a break.'
          : 'Ready to lock in again? Tap to start your next session.',
      ongoing: false,
    );

    // 8. Mark pending so UI shows the transition dialog.
    _pendingFinished = true;
    _saveState();
    notifyListeners();

    // 9. Push widget — segment ended, show idle state of next segment. ← NEW
    WidgetService.instance.pushSessionEnded(                           // ← NEW
      activeProject: AppController.instance.activeProject,            // ← NEW
    );                                                                 // ← NEW

    // 10. Autostart? Apply only if the relevant setting is on.
    //     Add a 2-second grace delay so the alarm finishes audibly.
    final shouldAuto = wasWork
        ? _settings.autostartBreak
        : _settings.autostartSession;

    if (shouldAuto) {
      await Future.delayed(const Duration(seconds: 2));
      start(); // start() resets _lastWidgetPush, so widget updates immediately
    }
  }

  Future<void> _endSegment({
    required bool completed,
    FocusTimerState? stateOverride,
  }) async {
    final s         = stateOverride ?? _state;
    final projectId = s.projectId;
    final start     = _segmentStart;
    if (projectId == null || start == null) return;

    final wallElapsed = DateTime.now().difference(start).inSeconds;
    final actual      = completed
        ? s.totalSeconds
        : wallElapsed.clamp(0, s.totalSeconds);

    if (actual < 30) return;

    final session = FocusSession(
      id:             const Uuid().v4(),
      projectId:      projectId,
      type:           s.sessionType,
      preset:         s.preset,
      startedAt:      start,
      endedAt:        DateTime.now(),
      plannedSeconds: s.totalSeconds,
      actualSeconds:  actual,
      completed:      completed,
    );

    try {
      final store = await _store;
      await store.saveFocusSession(session);
    } catch (e) {
      debugPrint('[FocusTimerService] Save session failed: $e');
    }

    _segmentStart = null;
    _prefs?.remove(_kStartedAt);
  }

  void _advanceToNextSegment() {
    final preset  = _state.preset;
    final wasWork = _state.isWork;
    final newWork = _state.completedWork + (wasWork ? 1 : 0);

    final SessionType nextType;
    final int         nextSeconds;

    if (wasWork) {
      final longDue = newWork % preset.sessionsUntilLongBreak == 0;
      nextType    = longDue ? SessionType.longBreak : SessionType.shortBreak;
      nextSeconds = longDue
          ? preset.longBreakMinutes * 60
          : preset.shortBreakMinutes * 60;
    } else {
      nextType    = SessionType.work;
      nextSeconds = preset.workMinutes * 60;
    }

    _segmentStart = null;
    _state = _state.copyWith(
      phase:            TimerPhase.idle,
      sessionType:      nextType,
      totalSeconds:     nextSeconds,
      remainingSeconds: nextSeconds,
      completedWork:    newWork,
    );
    _saveState();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────

  Future<void> _fireNotif({
    required int    id,
    required String title,
    required String body,
    bool            ongoing = false,
  }) async {
    if (!_notifReady) return;
    try {
      await _notif.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'focusbell_timer',
            'FocusBell Timer',
            channelDescription: 'Focus session progress and alerts',
            importance:         Importance.high,
            ongoing:            ongoing,
            autoCancel:         !ongoing,
            sound:              null,
            enableVibration:    true,
            styleInformation:   const DefaultStyleInformation(true, true),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FocusTimerService] Notification failed: $e');
    }
  }

  Future<void> _cancelNotif(int id) async {
    if (!_notifReady) return;
    await _notif.cancel(id);
  }

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  void _saveState() =>
      _prefs?.setString(_kStateKey, jsonEncode(_state.toJson()));

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ─────────────────────────────────────────────────────────────
  // ANALYTICS  (unchanged from v4)
  // ─────────────────────────────────────────────────────────────

  Future<ProjectFocusSummary> summaryForProject(
    Project project, {
    int days = 30,
  }) async {
    final store = await _store;
    final to    = _todayMidnight().add(const Duration(days: 1));
    final from  = to.subtract(Duration(days: days));
    final sessions = await store.fetchSessionsInRange(
      from,
      to,
      projectId: project.id,
    );
    return _buildSummary(project, sessions, from, to);
  }

  Future<List<ProjectFocusSummary>> summariesForAllProjects(
    List<Project> projects, {
    int days = 7,
  }) async {
    final store = await _store;
    final to    = _todayMidnight().add(const Duration(days: 1));
    final from  = to.subtract(Duration(days: days));
    final all   = await store.fetchSessionsInRange(from, to);

    final byProject = <String, List<FocusSession>>{};
    for (final s in all) {
      byProject.putIfAbsent(s.projectId, () => []).add(s);
    }

    final result = <ProjectFocusSummary>[];
    for (final p in projects) {
      result.add(_buildSummary(p, byProject[p.id] ?? [], from, to));
    }
    result.sort((a, b) => b.totalFocusSeconds.compareTo(a.totalFocusSeconds));
    return result;
  }

  ProjectFocusSummary _buildSummary(
    Project              project,
    List<FocusSession>   sessions,
    DateTime             from,
    DateTime             to,
  ) {
    final work         = sessions.where((s) => s.type == SessionType.work).toList();
    final totalSeconds = work.fold(0, (s, e) => s + e.actualSeconds);
    final completedCount = work.where((s) => s.completed).length;

    final Map<String, DailyFocusStat> dayMap = {};
    for (final s in work) {
      final key = _dayKey(s.startedAt);
      final ex  = dayMap[key];
      dayMap[key] = ex == null
          ? DailyFocusStat(
              date:               _dayMidnight(s.startedAt),
              projectId:          project.id,
              totalSeconds:       s.actualSeconds,
              completedSessions:  s.completed ? 1 : 0,
              totalSessions:      1,
            )
          : DailyFocusStat(
              date:               ex.date,
              projectId:          project.id,
              totalSeconds:       ex.totalSeconds + s.actualSeconds,
              completedSessions:  ex.completedSessions + (s.completed ? 1 : 0),
              totalSessions:      ex.totalSessions + 1,
            );
    }

    final allDays = <DailyFocusStat>[];
    var cursor = from;
    while (cursor.isBefore(to)) {
      final key = _dayKey(cursor);
      allDays.add(
        dayMap[key] ??
            DailyFocusStat(
              date:              cursor,
              projectId:         project.id,
              totalSeconds:      0,
              completedSessions: 0,
              totalSessions:     0,
            ),
      );
      cursor = cursor.add(const Duration(days: 1));
    }

    int current = 0, longest = 0, run = 0;
    for (final d in allDays.reversed) {
      if (d.completedSessions > 0) {
        run++;
        if (run > longest) longest = run;
        if (current == 0) current = run;
      } else {
        if (current == 0) break;
        run = 0;
      }
    }

    return ProjectFocusSummary(
      projectId:         project.id,
      projectName:       project.name,
      totalFocusSeconds: totalSeconds,
      completedSessions: completedCount,
      totalSessions:     work.length,
      currentStreak:     current,
      longestStreak:     longest,
      dailyStats:        allDays,
    );
  }

  static DateTime _todayMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _dayMidnight(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _cancelTicker();
    _alarmStopTimer?.cancel();
    _tickPlayer.dispose();
    _alarmPlayer.dispose();
    super.dispose();
  }
}