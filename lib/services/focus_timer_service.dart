// services/focus_timer_service.dart  — FULL REPLACEMENT
//
// Background-safe, wall-clock anchored timer with:
//   • Persists state to SharedPreferences — survives app kills / restarts
//   • Timer continues running when the sheet is dismissed (singleton Dart isolate)
//   • Audio: looping tick sound while running, chime on completion
//   • tickSoundEnabled toggle — persisted across sessions
//   • All existing analytics methods preserved

import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/focus_session.dart';
import '../models/project.dart';
import 'storage_service.dart';

// ── Timer state ───────────────────────────────────────────────────

enum TimerPhase { idle, running, paused, finished }

class FocusTimerState {
  final TimerPhase phase;
  final SessionType sessionType;
  final TimerPreset preset;
  final int totalSeconds;
  final int remainingSeconds;
  final int completedWork;
  final String? projectId;
  final String? projectName; // carried so home screen needs no lookup

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

  bool get isRunning => phase == TimerPhase.running;
  bool get isActive =>
      phase == TimerPhase.running || phase == TimerPhase.paused;
  bool get isWork => sessionType == SessionType.work;
  double get progress =>
      totalSeconds == 0 ? 0 : 1 - (remainingSeconds / totalSeconds);

  String get mmss {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  FocusTimerState copyWith({
    TimerPhase? phase,
    SessionType? sessionType,
    TimerPreset? preset,
    int? totalSeconds,
    int? remainingSeconds,
    int? completedWork,
    String? projectId,
    String? projectName,
  }) => FocusTimerState(
    phase: phase ?? this.phase,
    sessionType: sessionType ?? this.sessionType,
    preset: preset ?? this.preset,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    completedWork: completedWork ?? this.completedWork,
    projectId: projectId ?? this.projectId,
    projectName: projectName ?? this.projectName,
  );

  static FocusTimerState initial(TimerPreset preset) => FocusTimerState(
    phase: TimerPhase.idle,
    sessionType: SessionType.work,
    preset: preset,
    totalSeconds: preset.workMinutes * 60,
    remainingSeconds: preset.workMinutes * 60,
    completedWork: 0,
  );

  // ── Persistence ────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'phase': phase.index,
    'sessionType': sessionType.index,
    'preset': preset.index,
    'totalSeconds': totalSeconds,
    'remainingSeconds': remainingSeconds,
    'completedWork': completedWork,
    'projectId': projectId,
    'projectName': projectName,
  };

  factory FocusTimerState.fromJson(Map<String, dynamic> j) => FocusTimerState(
    phase: TimerPhase.values[j['phase'] as int],
    sessionType: SessionType.values[j['sessionType'] as int],
    preset: TimerPreset.values[j['preset'] as int],
    totalSeconds: j['totalSeconds'] as int,
    remainingSeconds: j['remainingSeconds'] as int,
    completedWork: j['completedWork'] as int,
    projectId: j['projectId'] as String?,
    projectName: j['projectName'] as String?,
  );
}

// ── Service ───────────────────────────────────────────────────────

class FocusTimerService extends ChangeNotifier {
  FocusTimerService._();
  static final FocusTimerService instance = FocusTimerService._();

  static const _kStateKey = 'focus_timer_state';
  static const _kStartedAtKey = 'focus_timer_started_at';
  static const _kTickEnabledKey = 'focus_tick_enabled';

  // ── State ─────────────────────────────────────────────────────

  FocusTimerState _state = FocusTimerState.initial(TimerPreset.pomodoro);
  FocusTimerState get state => _state;

  /// Whether the segment finished while the app was backgrounded.
  /// The timer sheet and home screen check this to show the dialog.
  bool _pendingFinished = false;
  bool get pendingFinished => _pendingFinished;
  void clearPendingFinished() => _pendingFinished = false;

  Timer? _ticker;
  DateTime? _segmentStart; // wall-clock when this segment started

  // ── Audio ─────────────────────────────────────────────────────

  final _tickPlayer = AudioPlayer();
  final _completePlayer = AudioPlayer();
  bool _tickEnabled = true;
  bool get tickSoundEnabled => _tickEnabled;

  // ── Storage ───────────────────────────────────────────────────

  SharedPreferences? _prefs;
  StorageService? _storage;
  Future<StorageService> get _store async =>
      _storage ??= await StorageService.getInstance();

  // ── Boot ──────────────────────────────────────────────────────

  /// Call once from main() or AppController.boot() — BEFORE runApp.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _tickEnabled = _prefs!.getBool(_kTickEnabledKey) ?? true;

    // Pre-load the tick source so loop + volume are configured on the right player.
    await _tickPlayer.setVolume(0.55);
    await _tickPlayer.setReleaseMode(ReleaseMode.loop);
    await _tickPlayer.setSource(AssetSource('sounds/tick.mp3'));

    await _completePlayer.setVolume(1.0);
    await _completePlayer.setReleaseMode(ReleaseMode.stop);
    await _completePlayer.setSource(AssetSource('sounds/complete.wav'));

    // Restore persisted state.
    final raw = _prefs!.getString(_kStateKey);
    if (raw != null) {
      try {
        final saved = FocusTimerState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );

        if (saved.phase == TimerPhase.running) {
          // Re-anchor: how many seconds elapsed while we were away?
          final startedAtRaw = _prefs!.getString(_kStartedAtKey);
          if (startedAtRaw != null) {
            _segmentStart = DateTime.parse(startedAtRaw);
            final elapsed = DateTime.now().difference(_segmentStart!).inSeconds;
            final remaining = (saved.remainingSeconds - elapsed).clamp(
              0,
              saved.totalSeconds,
            );

            if (remaining <= 0) {
              // Segment completed while backgrounded.
              _state = saved.copyWith(
                remainingSeconds: 0,
                phase: TimerPhase.finished,
              );
              _pendingFinished = true;
              await _endSegment(completed: true, stateOverride: _state);
              _saveState();
            } else {
              _state = saved.copyWith(remainingSeconds: remaining);
              _resumeTicker();
              if (_tickEnabled) _startTick();
            }
          } else {
            _state = saved.copyWith(phase: TimerPhase.paused);
          }
        } else {
          _state = saved;
        }
        notifyListeners();
      } catch (e) {
        debugPrint('[FocusTimerService] Failed to restore state: $e');
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────

  /// Called when opening the sheet for a NEW project or preset.
  /// Safe to call if a session is already running — it won't reset it.
  void configure({
    required TimerPreset preset,
    required String projectId,
    required String projectName,
  }) {
    // Don't stomp an active session for a different project.
    if (_state.isActive && _state.projectId != null) return;

    _cancelTicker();
    _stopTick();
    _state = FocusTimerState.initial(
      preset,
    ).copyWith(projectId: projectId, projectName: projectName);
    _saveState();
    notifyListeners();
  }

  void start() {
    if (_state.phase == TimerPhase.running) return;
    _segmentStart ??= DateTime.now();
    _prefs?.setString(_kStartedAtKey, _segmentStart!.toIso8601String());
    _state = _state.copyWith(phase: TimerPhase.running);
    _saveState();
    _resumeTicker();
    if (_tickEnabled) _startTick();
    notifyListeners();
  }

  void pause() {
    if (_state.phase != TimerPhase.running) return;
    _cancelTicker();
    _stopTick();
    _state = _state.copyWith(phase: TimerPhase.paused);
    _saveState();
    notifyListeners();
  }

  void resume() => start();

  void reset() {
    _cancelTicker();
    _stopTick();
    _state = FocusTimerState.initial(
      _state.preset,
    ).copyWith(projectId: _state.projectId, projectName: _state.projectName);
    _segmentStart = null;
    _prefs?.remove(_kStartedAtKey);
    _saveState();
    notifyListeners();
  }

  Future<void> skip() async {
    _cancelTicker();
    _stopTick();
    await _endSegment(completed: false);
    _advanceToNextSegment();
  }

  /// Fully stops and clears the timer (called from "Stop" in completion dialog).
  void stop() {
    _cancelTicker();
    _stopTick();
    _state = FocusTimerState.initial(
      _state.preset,
    ).copyWith(projectId: _state.projectId, projectName: _state.projectName);
    _pendingFinished = false;
    _segmentStart = null;
    _prefs?.remove(_kStartedAtKey);
    _saveState();
    notifyListeners();
  }

  // ── Audio controls ────────────────────────────────────────────

  void setTickEnabled(bool enabled) {
    _tickEnabled = enabled;
    _prefs?.setBool(_kTickEnabledKey, enabled);
    if (enabled && _state.phase == TimerPhase.running) {
      _startTick();
    } else {
      _stopTick();
    }
    notifyListeners();
  }

  void _startTick() {
    // Source is pre-loaded in init(); resume() is instant with no async gap.
    _tickPlayer.resume();
  }

  void _stopTick() {
    _tickPlayer.stop();
  }

  Future<void> _playComplete() async {
    // Seek to start then resume so it always plays from the beginning.
    await _completePlayer.seek(Duration.zero);
    await _completePlayer.resume();
  }

  // ── Ticker ────────────────────────────────────────────────────

  void _resumeTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer _) {
    // Always decrement first so the display reaches 00:00.
    final next = _state.remainingSeconds - 1;
    _state = _state.copyWith(remainingSeconds: next);
    notifyListeners();

    if (next <= 0) {
      // Segment finished — stop the mechanical ticker and sound,
      // then hand off to the async completion handler.
      _cancelTicker();
      _stopTick();
      // Schedule on the next microtask so the 00:00 frame is painted
      // before we do async DB work and state transitions.
      Future.microtask(_onSegmentComplete);
      return;
    }

    // Persist every 5 s to avoid excessive writes.
    if (next % 5 == 0) _saveState();
  }

  Future<void> _onSegmentComplete() async {
    // 1. Snap display to 00:00 so the UI shows completion immediately.
    _state = _state.copyWith(remainingSeconds: 0);
    notifyListeners();

    // 2. Save the completed session record.
    await _endSegment(completed: true);

    // 3. Play the completion chime.
    await _playComplete();

    // 4. Advance internal state to the next segment (work → break or break → work).
    //    This sets phase = idle with the correct next duration loaded.
    _advanceToNextSegment();

    // 5. Mark pendingFinished so the UI (sheet or home screen banner) can show
    //    the "X complete, now starting break" dialog — but we start the next
    //    timer automatically regardless of whether the sheet is open.
    _pendingFinished = true;

    // 6. Auto-start the next segment immediately.
    //    The user sees the break timer ticking without needing to tap anything.
    start();
  }

  // ── Persistence helpers ───────────────────────────────────────

  void _saveState() {
    _prefs?.setString(_kStateKey, jsonEncode(_state.toJson()));
  }

  // ── Session record ────────────────────────────────────────────

  Future<void> _endSegment({
    required bool completed,
    FocusTimerState? stateOverride,
  }) async {
    final s = stateOverride ?? _state;
    final projectId = s.projectId;
    final start = _segmentStart;
    if (projectId == null || start == null) return;

    // Use wall-clock elapsed time as the source of truth.
    // Avoids the off-by-one from remainingSeconds still being 1
    // when called, and correctly accounts for background time.
    final wallElapsed = DateTime.now().difference(start).inSeconds;
    final actual = completed
        ? s
              .totalSeconds // full session: credit planned time
        : wallElapsed.clamp(0, s.totalSeconds); // partial: clamp to planned max

    if (actual < 30) return; // discard true micro-fragments

    final session = FocusSession(
      id: const Uuid().v4(),
      projectId: projectId,
      type: s.sessionType,
      preset: s.preset,
      startedAt: start,
      endedAt: DateTime.now(),
      plannedSeconds: s.totalSeconds,
      actualSeconds: actual,
      completed: completed,
    );

    try {
      final store = await _store;
      await store.saveFocusSession(session);
    } catch (e) {
      debugPrint('[FocusTimerService] Save session failed: $e');
    }

    _segmentStart = null;
    _prefs?.remove(_kStartedAtKey);
  }

  // ── Segment sequencing ────────────────────────────────────────

  void _advanceToNextSegment() {
    final preset = _state.preset;
    final wasWork = _state.isWork;
    final newWork = _state.completedWork + (wasWork ? 1 : 0);

    final SessionType nextType;
    final int nextSeconds;

    if (wasWork) {
      final longBreakDue = newWork % preset.sessionsUntilLongBreak == 0;
      nextType = longBreakDue ? SessionType.longBreak : SessionType.shortBreak;
      nextSeconds = longBreakDue
          ? preset.longBreakMinutes * 60
          : preset.shortBreakMinutes * 60;
    } else {
      nextType = SessionType.work;
      nextSeconds = preset.workMinutes * 60;
    }

    _segmentStart = null;
    _state = _state.copyWith(
      phase: TimerPhase.idle,
      sessionType: nextType,
      totalSeconds: nextSeconds,
      remainingSeconds: nextSeconds,
      completedWork: newWork,
    );
    _saveState();
    notifyListeners();
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ── Analytics ─────────────────────────────────────────────────

  Future<ProjectFocusSummary> summaryForProject(
    Project project, {
    int days = 30,
  }) async {
    final store = await _store;
    final to = _todayMidnight().add(const Duration(days: 1));
    final from = to.subtract(Duration(days: days));
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
    final to = _todayMidnight().add(const Duration(days: 1));
    final from = to.subtract(Duration(days: days));
    final all = await store.fetchSessionsInRange(from, to);

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
    Project project,
    List<FocusSession> sessions,
    DateTime from,
    DateTime to,
  ) {
    final workSessions = sessions
        .where((s) => s.type == SessionType.work)
        .toList();
    final totalSeconds = workSessions.fold(0, (s, e) => s + e.actualSeconds);
    final completedCount = workSessions.where((s) => s.completed).length;

    final Map<String, DailyFocusStat> dayMap = {};
    for (final s in workSessions) {
      final key = _dayKey(s.startedAt);
      final ex = dayMap[key];
      dayMap[key] = ex == null
          ? DailyFocusStat(
              date: _dayMidnight(s.startedAt),
              projectId: project.id,
              totalSeconds: s.actualSeconds,
              completedSessions: s.completed ? 1 : 0,
              totalSessions: 1,
            )
          : DailyFocusStat(
              date: ex.date,
              projectId: project.id,
              totalSeconds: ex.totalSeconds + s.actualSeconds,
              completedSessions: ex.completedSessions + (s.completed ? 1 : 0),
              totalSessions: ex.totalSessions + 1,
            );
    }

    final allDays = <DailyFocusStat>[];
    var cursor = from;
    while (cursor.isBefore(to)) {
      final key = _dayKey(cursor);
      allDays.add(
        dayMap[key] ??
            DailyFocusStat(
              date: cursor,
              projectId: project.id,
              totalSeconds: 0,
              completedSessions: 0,
              totalSessions: 0,
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
      projectId: project.id,
      projectName: project.name,
      totalFocusSeconds: totalSeconds,
      completedSessions: completedCount,
      totalSessions: workSessions.length,
      currentStreak: current,
      longestStreak: longest,
      dailyStats: allDays,
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
    _tickPlayer.dispose();
    _completePlayer.dispose();
    super.dispose();
  }
}
