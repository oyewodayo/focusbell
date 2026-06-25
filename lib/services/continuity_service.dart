// services/continuity_service.dart — NEW FILE
//
// The Cognitive Continuity System.
//
// Tracks every meaningful user action with a timestamp and context.
// When the user returns after being idle for >= _kIdleThreshold, builds
// a synthesised ContinuitySnapshot — a structured briefing of what they
// were doing, what changed while they were away, and what's coming up.
//
// Design principles:
//   • Zero UI impact while active — tracking is purely background writes
//   • Snapshot is built lazily on return, never while user is active
//   • Text is synthesised (one paragraph), not a raw log dump
//   • Scales with time-away: 5 min = subtle, 1 day = full briefing
//   • Persisted across cold starts via SharedPreferences

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder_model.dart';
import '../services/focus_timer_service.dart';
import '../services/reminder_service.dart';
import '../services/reminder_group_service.dart';

// ── Action types ──────────────────────────────────────────────────────────────

enum ContinuityActionType {
  openedApp,
  startedFocusSession,
  pausedFocusSession,
  completedFocusSession,
  stoppedFocusSession, 
  skippedFocusSession,
  addedReminder,
  editedReminder,
  deletedReminder,
  completedReminder,
  openedScreen,
  addedNote,
  editedNote,
  deletedNote, 
  changedTimezone,
  addedPlace,
  addedProject,        // ← ADD
  editedProject,       // ← ADD
  deletedProject,      // ← ADD
  archivedProject,     // ← ADD
  switchedProject,     // ← ADD
  addedTask,           // ← ADD
  completedTask,       // ← ADD
  deletedTask,         // ← ADD
}

class ContinuityAction {
  final ContinuityActionType type;
  final DateTime             at;
  final String?              detail;   // human-readable context

  const ContinuityAction({
    required this.type,
    required this.at,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'type':   type.name,
    'at':     at.toIso8601String(),
    'detail': detail,
  };

  factory ContinuityAction.fromJson(Map<String, dynamic> j) =>
      ContinuityAction(
        type:   ContinuityActionType.values.firstWhere(
            (e) => e.name == j['type'],
            orElse: () => ContinuityActionType.openedApp),
        at:     DateTime.parse(j['at'] as String),
        detail: j['detail'] as String?,
      );
}

// ── Snapshot ──────────────────────────────────────────────────────────────────

class ContinuitySnapshot {
  /// How long the user was away
  final Duration awayFor;

  /// Last action before leaving
  final ContinuityAction? lastAction;

  /// Was there an active focus session when they left?
  final String? activeSessionProject;

  /// Reminders that fired/passed while they were away
  final List<Reminder> missedReminders;

  /// Reminders coming up in the next 2 hours
  final List<Reminder> upcomingReminders;

  /// Synthesised briefing paragraph
  final String briefing;

  /// Urgency level — controls visual treatment
  final ContinuityUrgency urgency;

  const ContinuitySnapshot({
    required this.awayFor,
    required this.lastAction,
    required this.activeSessionProject,
    required this.missedReminders,
    required this.upcomingReminders,
    required this.briefing,
    required this.urgency,
  });
}

enum ContinuityUrgency { low, medium, high }

// ── Service ───────────────────────────────────────────────────────────────────

class ContinuityService {
  ContinuityService._();
  static final ContinuityService instance = ContinuityService._();

  static const _kPrefsKey       = 'continuity_actions_v1';
  static const _kLastActiveKey  = 'continuity_last_active';
  static const _kSessionKey     = 'continuity_active_session';
  static const _kMaxActions     = 50;  // rolling window

  // Idle threshold — show briefing if away longer than this
  static const _kIdleThreshold  = Duration(minutes: 3);

  final List<ContinuityAction> _actions = [];
  DateTime?                    _lastActiveAt;
  String?                      _lastSessionProject;

  // Current snapshot (set when user returns, cleared on dismiss)
  ContinuitySnapshot?          _pendingSnapshot;
  ContinuitySnapshot? get      pendingSnapshot => _pendingSnapshot;

  final _listeners = <VoidCallback>[];
  void addListener(VoidCallback fn)    => _listeners.add(fn);
  void removeListener(VoidCallback fn) => _listeners.remove(fn);
  void _notify()                       { for (final f in _listeners) f(); }

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    await _load();
    _lastActiveAt = await _loadLastActive();
    _lastSessionProject = await _loadLastSession();
    debugPrint('[ContinuityService] init  lastActive=$_lastActiveAt');
  }

  // ── Track ──────────────────────────────────────────────────────

  /// Record a user action. Call this from anywhere in the app.
  Future<void> track(
    ContinuityActionType type, {
    String? detail,
  }) async {
    final action = ContinuityAction(
      type:   type,
      at:     DateTime.now(),
      detail: detail,
    );
    _actions.add(action);
    if (_actions.length > _kMaxActions) {
      _actions.removeAt(0);
    }
    await _persist();
    debugPrint('[ContinuityService] tracked ${type.name}: $detail');
  }

  // ── App lifecycle ──────────────────────────────────────────────

  /// Call when app enters foreground.
  Future<void> onAppResumed() async {
    final now    = DateTime.now();
    final last   = _lastActiveAt;

    if (last != null) {
      final away = now.difference(last);
      if (away >= _kIdleThreshold) {
        // User was away long enough — build snapshot
        _pendingSnapshot = await _buildSnapshot(away, last);
        _notify();
      }
    }

    _lastActiveAt = now;
    await _persistLastActive(now);
    await track(ContinuityActionType.openedApp);
  }

  /// Call when app enters background.
  Future<void> onAppPaused() async {
    _lastActiveAt = DateTime.now();
    await _persistLastActive(_lastActiveAt!);

    // Capture focus session state
    final focusState = FocusTimerService.instance.state;
    if (focusState.isActive && focusState.isWork) {
      _lastSessionProject = focusState.projectName;
      await _persistLastSession(_lastSessionProject);
    } else {
      _lastSessionProject = null;
      await _persistLastSession(null);
    }
  }

  /// Dismiss the pending snapshot (user read it).
  void dismissSnapshot() {
    _pendingSnapshot = null;
    _notify();
  }

  // ── Build snapshot ─────────────────────────────────────────────

  Future<ContinuitySnapshot> _buildSnapshot(
      Duration away, DateTime leftAt) async {
    final now      = DateTime.now();
    final reminders = ReminderService.instance.reminders.value;

    // What fired/passed while they were gone
    final missed = reminders.where((r) =>
        r.dateTime.isAfter(leftAt) &&
        r.dateTime.isBefore(now) &&
        !r.isRepeating).toList();

    // What's coming in the next 2 hours
    final upcoming = reminders
        .where((r) => r.dateTime.isAfter(now) &&
            r.dateTime.isBefore(now.add(const Duration(hours: 2))))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // Last meaningful action
    final lastAction = _actions.isNotEmpty ? _actions.last : null;

    // Urgency
    ContinuityUrgency urgency;
    if (missed.isNotEmpty || upcoming.isNotEmpty) {
      urgency = upcoming.any((r) =>
              r.dateTime.difference(now).inMinutes < 15)
          ? ContinuityUrgency.high
          : ContinuityUrgency.medium;
    } else if (away.inHours >= 4) {
      urgency = ContinuityUrgency.medium;
    } else {
      urgency = ContinuityUrgency.low;
    }

    final briefing = _synthesise(
      away:           away,
      lastAction:     lastAction,
      sessionProject: _lastSessionProject,
      missed:         missed,
      upcoming:       upcoming,
    );

    return ContinuitySnapshot(
      awayFor:              away,
      lastAction:           lastAction,
      activeSessionProject: _lastSessionProject,
      missedReminders:      missed,
      upcomingReminders:    upcoming,
      briefing:             briefing,
      urgency:              urgency,
    );
  }

  // ── Synthesise briefing text ───────────────────────────────────

  String _synthesise({
    required Duration        away,
    required ContinuityAction? lastAction,
    required String?         sessionProject,
    required List<Reminder>  missed,
    required List<Reminder>  upcoming,
  }) {
    final parts = <String>[];

    // 1. Greeting based on time of day
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning'
        : hour < 17            ? 'Welcome back'
        : hour < 21            ? 'Good evening'
        :                        'Hey, night owl';

    parts.add('$greeting.');

    // 2. How long away
    parts.add(_awayPhrase(away));

    // 3. Last action context
    if (sessionProject != null) {
      parts.add('You had a focus session running on "$sessionProject" when you left.');
    } else if (lastAction != null) {
      final ctx = _actionPhrase(lastAction);
      if (ctx != null) parts.add(ctx);
    }

    // 4. Missed reminders
    if (missed.isNotEmpty) {
      if (missed.length == 1) {
        parts.add('"${missed.first.title}" fired while you were away.');
      } else {
        parts.add('${missed.length} reminders fired while you were away.');
      }
    }

    // 5. Upcoming
    if (upcoming.isNotEmpty) {
      final next  = upcoming.first;
      final mins  = next.dateTime.difference(DateTime.now()).inMinutes;
      final when  = mins < 2  ? 'right now'
          : mins < 60         ? 'in $mins minutes'
          :                     'in ${(mins / 60).round()} hour${(mins / 60).round() == 1 ? '' : 's'}';
      parts.add('"${next.title}" is up $when.');
    }

    // 6. Nothing urgent
    if (missed.isEmpty && upcoming.isEmpty && sessionProject == null) {
      parts.add('Everything looks clear. Pick up where you left off.');
    }

    return parts.join(' ');
  }

  String _awayPhrase(Duration away) {
    if (away.inMinutes < 10) return 'You stepped away briefly.';
    if (away.inMinutes < 60) return 'You\'ve been away for ${away.inMinutes} minutes.';
    if (away.inHours < 24)   return 'You\'ve been away for ${away.inHours} hour${away.inHours == 1 ? '' : 's'}.';
    if (away.inDays == 1)    return 'It\'s been a day since you were last here.';
    return 'You\'ve been away for ${away.inDays} days.';
  }

 String? _actionPhrase(ContinuityAction action) {
  switch (action.type) {
    // ── Focus sessions ──────────────────────────────────────
    case ContinuityActionType.startedFocusSession:
      return 'You started a focus session${action.detail != null ? ' on "${action.detail}"' : ''}.';
    case ContinuityActionType.pausedFocusSession:
      return 'You paused a focus session${action.detail != null ? ' on "${action.detail}"' : ''}.';
    case ContinuityActionType.completedFocusSession:
      return 'You completed a focus session${action.detail != null ? ' on "${action.detail}"' : ''}.';
    case ContinuityActionType.stoppedFocusSession:
      return 'You stopped a focus session${action.detail != null ? ' on "${action.detail}"' : ''} early.';
    case ContinuityActionType.skippedFocusSession:
      return 'You skipped a segment${action.detail != null ? ' on "${action.detail}"' : ''}.';

    // ── Reminders ────────────────────────────────────────────
    case ContinuityActionType.addedReminder:
      return 'Last thing you did: added a reminder${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.editedReminder:
      return 'You were editing a reminder${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.deletedReminder:
      return 'You deleted a reminder${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.completedReminder:
      return 'You completed a reminder${action.detail != null ? ' — "${action.detail}"' : ''}.';

    // ── Notes ────────────────────────────────────────────────
    case ContinuityActionType.addedNote:
      return 'You were working on a note${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.editedNote:
      return 'You were editing a note${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.deletedNote:
      return 'You deleted a note${action.detail != null ? ' — "${action.detail}"' : ''}.';

    // ── Projects ─────────────────────────────────────────────
    case ContinuityActionType.addedProject:
      return 'You added a project${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.editedProject:
      return 'You were editing a project${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.deletedProject:
      return 'You deleted a project${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.archivedProject:
      return 'You archived a project${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.switchedProject:
      return action.detail != null ? 'You switched to "${action.detail}".' : null;

    // ── Tasks ────────────────────────────────────────────────
    case ContinuityActionType.addedTask:
      return 'You added a task${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.completedTask:
      return 'You completed a task${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.deletedTask:
      return 'You deleted a task${action.detail != null ? ' — "${action.detail}"' : ''}.';

    // ── Misc ─────────────────────────────────────────────────
    case ContinuityActionType.openedScreen:
      return action.detail != null
          ? 'You were on the ${action.detail} screen.'
          : null;
    case ContinuityActionType.addedPlace:
      return 'You added a saved place${action.detail != null ? ' — "${action.detail}"' : ''}.';
    case ContinuityActionType.changedTimezone:
      return 'Your timezone changed${action.detail != null ? ' to ${action.detail}' : ''}.';

    case ContinuityActionType.openedApp:
      // Opening the app is the action that *triggers* the briefing —
      // never meaningful as "the last thing you did."
      return null;
  }
}

  // ── Persistence ────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = _actions.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_kPrefsKey, raw);
    } catch (e) { debugPrint('[ContinuityService] persist failed: $e'); }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getStringList(_kPrefsKey) ?? [];
      _actions.clear();
      for (final s in raw) {
        try {
          _actions.add(ContinuityAction.fromJson(
              jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
    } catch (e) { debugPrint('[ContinuityService] load failed: $e'); }
  }

  Future<void> _persistLastActive(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastActiveKey, dt.toIso8601String());
  }

  Future<DateTime?> _loadLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    final s     = prefs.getString(_kLastActiveKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<void> _persistLastSession(String? project) async {
    final prefs = await SharedPreferences.getInstance();
    if (project != null) {
      await prefs.setString(_kSessionKey, project);
    } else {
      await prefs.remove(_kSessionKey);
    }
  }

  Future<String?> _loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSessionKey);
  }
}