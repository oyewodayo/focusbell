// widgets/focus_timer_sheet.dart — FULL REPLACEMENT v4
//
// • Three-dot settings menu: Autostart break, Autostart session, Strict mode, Tick sound
// • Strict mode: WillPopScope blocks back/swipe-down during work sessions
// • Finished dialog: informs user of next segment, lets them start manually
//   (or auto-starts if setting is on — service handles that)
// • Alarm stops when user dismisses dialog
// • Live mini-timer in finished dialog

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/focus_session.dart';
import '../models/focus_settings.dart';
import '../models/project.dart';
import '../services/focus_timer_service.dart';

// ── Entry point ───────────────────────────────────────────────────

void showFocusTimerSheet(BuildContext context, Project project) {
  final svc = FocusTimerService.instance;
  if (!svc.state.isActive ||
      (svc.state.projectId != null && svc.state.projectId != project.id)) {
    svc.configure(
      preset:      TimerPreset.pomodoro,
      projectId:   project.id,
      projectName: project.name,
    );
  }

  showModalBottomSheet(
    context:            context,
    backgroundColor:    Colors.transparent,
    isScrollControlled: true,
    // isDismissible controlled by WillPopScope inside
    isDismissible:      true,
    enableDrag:         true,
    builder: (_) => FocusTimerSheet(project: project),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────

class FocusTimerSheet extends StatefulWidget {
  final Project project;
  const FocusTimerSheet({super.key, required this.project});

  @override
  State<FocusTimerSheet> createState() => _FocusTimerSheetState();
}

class _FocusTimerSheetState extends State<FocusTimerSheet> {
  final _svc = FocusTimerService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onStateChange);
    // If a segment finished while we were away, show dialog immediately.
    if (_svc.pendingFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { _svc.clearPendingFinished(); _showFinishedDialog(); }
      });
    }
  }

  void _onStateChange() {
    if (!mounted) return;
    setState(() {});
    if (_svc.pendingFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { _svc.clearPendingFinished(); _showFinishedDialog(); }
      });
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onStateChange);
    super.dispose();
  }

  // ── Strict mode gate ─────────────────────────────────────────

  /// Returns true if the sheet should block closing right now.
  bool get _isLocked =>
      _svc.settings.strictMode &&
      _svc.state.isWork &&
      _svc.state.isRunning;

  Future<bool> _onWillPop() async {
    if (!_isLocked) return true;
    // Show a brief locked toast.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Text('🔒', style: TextStyle(fontSize: 16)),
              SizedBox(width: 10),
              Text('Strict mode: finish or pause to leave.',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          backgroundColor: const Color(0xFF2C1A00),
          behavior:        SnackBarBehavior.floating,
          margin:          const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
                color: Color(0xFFFF9F0A), width: 1),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return false;
  }

  // ── Finished dialog ───────────────────────────────────────────

  void _showFinishedDialog() {
    // Stop alarm when user interacts.
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (ctx) => _FinishedDialog(
        svc:      _svc,
        onStart: () {
          _svc.stopAlarmManually();
          Navigator.pop(ctx);
          _svc.start();
        },
        onStop: () {
          _svc.stopAlarmManually();
          Navigator.pop(ctx);
          _svc.stop();
        },
      ),
    );
  }

  // ── Settings menu ─────────────────────────────────────────────

  void _openSettings() {
    showModalBottomSheet(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SessionSettingsSheet(svc: _svc),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s     = _svc.state;
    final color = _phaseColor(s.sessionType);

    // WillPopScope blocks Android back button in strict mode.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: GestureDetector(
        // Block swipe-to-dismiss gesture in strict mode.
        onVerticalDragEnd: _isLocked
            ? (_) {
                HapticFeedback.heavyImpact();
                _onWillPop();
              }
            : null,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.93,
          decoration: const BoxDecoration(
            color:        Color(0xFF0E0E0E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Handle — greyed out in strict mode
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _isLocked
                      ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),

              // ── Top bar ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // Close / lock button
                    GestureDetector(
                      onTap: () async {
                        final canPop = await _onWillPop();
                        if (canPop && mounted) Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isLocked
                              ? const Color(0xFFFF9F0A).withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: _isLocked
                              ? Border.all(
                                  color: const Color(0xFFFF9F0A)
                                      .withValues(alpha: 0.4))
                              : null,
                        ),
                        child: Icon(
                          _isLocked
                              ? Icons.lock_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: _isLocked
                              ? const Color(0xFFFF9F0A)
                              : Colors.white54,
                          size: 20,
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Project pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.project.priority.bgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.project.priority.color
                              .withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.project.priority.emoji,
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 140),
                            child: Text(
                              widget.project.name,
                              style: TextStyle(
                                color:      widget.project.priority.color,
                                fontSize:   12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Session count
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color:        Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${s.completedWork} done',
                        style: const TextStyle(
                          color:      Colors.white38,
                          fontSize:   12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // ── Three-dot settings ─────────────────
                    GestureDetector(
                      onTap: _openSettings,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:        Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.more_vert_rounded,
                            color: Colors.white38, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Preset picker ─────────────────────────────
              _PresetPicker(
                preset:   s.preset,
                enabled:  !s.isActive,
                onSelect: (p) => _svc.configure(
                  preset:      p,
                  projectId:   widget.project.id,
                  projectName: widget.project.name,
                ),
              ),

              // ── Strict mode badge ─────────────────────────
              if (_svc.settings.strictMode)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F0A).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFF9F0A)
                                .withValues(alpha: 0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                color: Color(0xFFFF9F0A), size: 11),
                            SizedBox(width: 5),
                            Text('Strict mode — no escape during work',
                                style: TextStyle(
                                  color:      Color(0xFFFF9F0A),
                                  fontSize:   10,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // ── Ring ──────────────────────────────────────
              Expanded(
                child: Center(
                  child: _TimerRing(
                    progress:  s.progress,
                    remaining: s.remainingSeconds,
                    total:     s.totalSeconds,
                    color:     color,
                    phase:     s.sessionType,
                  ),
                ),
              ),

              // ── Phase label ───────────────────────────────
              Text(
                s.sessionType.label.toUpperCase(),
                style: TextStyle(
                  color:         color,
                  fontSize:      13,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle(s),
                style: const TextStyle(color: Colors.white30, fontSize: 12),
              ),

              const SizedBox(height: 28),

              // ── Controls ──────────────────────────────────
              _Controls(
                phase:   s.phase,
                color:   color,
                onStart: _svc.start,
                onPause: _svc.pause,
                onResume: _svc.resume,
                onSkip:  _svc.skip,
                onReset: _svc.reset,
              ),

              const SizedBox(height: 20),

              // ── Bottom row: tick + background note ────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Tick toggle
                  GestureDetector(
                    onTap: () => _svc.updateSettings(
                      _svc.settings.copyWith(
                        tickEnabled: !_svc.settings.tickEnabled),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _svc.settings.tickEnabled
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _svc.settings.tickEnabled
                              ? Colors.white24
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _svc.settings.tickEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: _svc.settings.tickEnabled
                                ? Colors.white54
                                : Colors.white24,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _svc.settings.tickEnabled
                                ? 'Tick on'
                                : 'Tick off',
                            style: TextStyle(
                              color: _svc.settings.tickEnabled
                                  ? Colors.white54
                                  : Colors.white24,
                              fontSize:   12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (s.isActive) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF32D74B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF32D74B)
                              .withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_tethering_rounded,
                              color: Color(0xFF32D74B), size: 13),
                          SizedBox(width: 6),
                          Text('Runs in background',
                              style: TextStyle(
                                color:      Color(0xFF32D74B),
                                fontSize:   11,
                                fontWeight: FontWeight.w500,
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Color _phaseColor(SessionType t) => switch (t) {
        SessionType.work       => const Color(0xFFFF453A),
        SessionType.shortBreak => const Color(0xFF32D74B),
        SessionType.longBreak  => const Color(0xFF0A84FF),
      };

  String _subtitle(FocusTimerState s) {
    if (s.phase == TimerPhase.idle) {
      final auto = s.isWork
          ? _svc.settings.autostartBreak
          : _svc.settings.autostartSession;
      return auto ? 'Tap Start · next phase auto-starts' : 'Ready when you are';
    }
    if (s.phase == TimerPhase.paused) return 'Paused · tap Resume to continue';
    if (!s.isWork) {
      final left = s.preset.sessionsUntilLongBreak -
          (s.completedWork % s.preset.sessionsUntilLongBreak);
      return '$left more session${left == 1 ? '' : 's'} until long break';
    }
    return _svc.settings.strictMode ? '🔒 Stay locked in' : 'Stay locked in';
  }
}

// ── Session settings bottom sheet ─────────────────────────────────

class _SessionSettingsSheet extends StatefulWidget {
  final FocusTimerService svc;
  const _SessionSettingsSheet({required this.svc});

  @override
  State<_SessionSettingsSheet> createState() => _SessionSettingsSheetState();
}

class _SessionSettingsSheetState extends State<_SessionSettingsSheet> {
  late FocusSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.svc.settings;
  }

  void _update(FocusSettings updated) {
    setState(() => _s = updated);
    widget.svc.updateSettings(updated);
  }

  @override
Widget build(BuildContext context) {
  return Container(
    decoration: const BoxDecoration(
      color: Color(0xFF141414),
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Session Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'These preferences persist across all sessions.',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  _SectionLabel('AUTOSTART'),
                  const SizedBox(height: 8),

                  _ToggleRow(
                    icon: Icons.coffee_rounded,
                    color: const Color(0xFF32D74B),
                    title: 'Autostart break from session',
                    subtitle:
                        'Break begins automatically when work ends',
                    value: _s.autostartBreak,
                    onChanged: (v) =>
                        _update(_s.copyWith(autostartBreak: v)),
                  ),

                  const SizedBox(height: 8),

                  _ToggleRow(
                    icon: Icons.flash_on_rounded,
                    color: const Color(0xFFFF453A),
                    title: 'Autostart session from break',
                    subtitle:
                        'Work session begins automatically when break ends',
                    value: _s.autostartSession,
                    onChanged: (v) =>
                        _update(_s.copyWith(autostartSession: v)),
                  ),

                  const SizedBox(height: 20),

                  _SectionLabel('FOCUS'),
                  const SizedBox(height: 8),

                  _ToggleRow(
                    icon: Icons.lock_rounded,
                    color: const Color(0xFFFF9F0A),
                    title: 'Strict mode',
                    subtitle:
                        'Locks the sheet open during work — no escape',
                    value: _s.strictMode,
                    onChanged: (v) =>
                        _update(_s.copyWith(strictMode: v)),
                  ),

                  const SizedBox(height: 8),

                  _ToggleRow(
                    icon: Icons.volume_up_rounded,
                    color: const Color(0xFF0A84FF),
                    title: 'Tick sound',
                    subtitle:
                        'Looping clock sound while the timer runs',
                    value: _s.tickEnabled,
                    onChanged: (v) =>
                        _update(_s.copyWith(tickEnabled: v)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color:         Colors.white24,
          fontSize:      10,
          fontWeight:    FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;
  final bool     value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: value
            ? color.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? color.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color:        color.withValues(alpha: value ? 0.15 : 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: value ? color : Colors.white30, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color:      value ? Colors.white : Colors.white60,
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white30, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value:           value,
            onChanged:       onChanged,
            activeColor:     color,
            inactiveThumbColor: Colors.white30,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}

// ── Finished dialog ───────────────────────────────────────────────

class _FinishedDialog extends StatelessWidget {
  final FocusTimerService svc;
  final VoidCallback      onStart;
  final VoidCallback      onStop;

  const _FinishedDialog({
    required this.svc,
    required this.onStart,
    required this.onStop,
  });

  Color _phaseColor(SessionType t) => switch (t) {
        SessionType.work       => const Color(0xFFFF453A),
        SessionType.shortBreak => const Color(0xFF32D74B),
        SessionType.longBreak  => const Color(0xFF0A84FF),
      };

  @override
  Widget build(BuildContext context) {
    // At this point _advanceToNextSegment has run, so state = next segment idle.
    return ListenableBuilder(
      listenable: svc,
      builder: (_, __) {
        final s       = svc.state;
        final color   = _phaseColor(s.sessionType);
        final mins    = s.totalSeconds ~/ 60;
        final isBreak = !s.isWork;
        final autoOn  = isBreak
            ? svc.settings.autostartBreak       // we just finished work
            : svc.settings.autostartSession;    // we just finished a break

        final (emoji, headline, readyLine) = isBreak
            ? (
                '🎉',
                'Session complete!',
                'Ready for a ${s.sessionType.label}?',
              )
            : (
                '⚡',
                'Break over!',
                'Ready to focus again?',
              );

        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
          title: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                headline,
                style: const TextStyle(
                  color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Completed work count (only after work segment)
              if (isBreak)
                Text(
                  '${s.completedWork} session${s.completedWork == 1 ? '' : 's'} done today.',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 6),

              // What's next
              Text(
                readyLine,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // Duration of next segment
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: color.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${s.sessionType.emoji}  ${s.sessionType.label}  ·  $mins min',
                  style: TextStyle(
                    color:      color,
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              if (autoOn) ...[
                const SizedBox(height: 10),
                Text(
                  'Auto-starting in a moment…',
                  style: TextStyle(
                    color:    color.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: onStop,
              child: const Text('Stop',
                  style: TextStyle(color: Colors.white30, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.18),
                foregroundColor: color,
                elevation:       0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
              ),
              onPressed: onStart,
              child: Text(
                autoOn ? 'Start now' : 'Start',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Preset picker ─────────────────────────────────────────────────

class _PresetPicker extends StatelessWidget {
  final TimerPreset preset;
  final bool        enabled;
  final ValueChanged<TimerPreset> onSelect;

  const _PresetPicker({
    required this.preset,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: TimerPreset.values.map((p) {
          final sel = p == preset;
          return GestureDetector(
            onTap: enabled ? () => onSelect(p) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin:  const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: sel
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? Colors.white38 : Colors.white12),
              ),
              child: Text(
                p.label,
                style: TextStyle(
                  color:      sel ? Colors.white : Colors.white38,
                  fontSize:   12,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Circular ring ─────────────────────────────────────────────────

class _TimerRing extends StatelessWidget {
  final double      progress;
  final int         remaining;
  final int         total;
  final Color       color;
  final SessionType phase;

  const _TimerRing({
    required this.progress,
    required this.remaining,
    required this.total,
    required this.color,
    required this.phase,
  });

  String _fmt(int s) {
    final m   = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    return SizedBox(
      width: size, height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(phase.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                _fmt(remaining),
                style: TextStyle(
                  color:         color,
                  fontSize:      52,
                  fontWeight:    FontWeight.w200,
                  letterSpacing: -2,
                  fontFeatures:  const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '/ ${_fmt(total)}',
                style: const TextStyle(
                    color: Colors.white24, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color  color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx   = size.width  / 2;
    final cy   = size.height / 2;
    final r    = size.width  / 2 - 12;
    const sw   = 8.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    canvas.drawArc(rect, 0, math.pi * 2, false,
      Paint()
        ..color       = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = sw
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round);

    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false,
        Paint()
          ..color       = color.withValues(alpha: 0.20)
          ..strokeWidth = sw + 10
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 10));

      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false,
        Paint()
          ..color       = color
          ..strokeWidth = sw
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color;
}

// ── Controls ──────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final TimerPhase phase;
  final Color      color;
  final VoidCallback onStart, onPause, onResume, onReset;
  final Future<void> Function() onSkip;

  const _Controls({
    required this.phase,
    required this.color,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onReset,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final showSide = phase == TimerPhase.running || phase == TimerPhase.paused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showSide) ...[
          _SideBtn(icon: Icons.refresh_rounded, color: Colors.white30,
              onTap: onReset),
          const SizedBox(width: 16),
        ],
        _MainBtn(phase: phase, color: color,
            onStart: onStart, onPause: onPause, onResume: onResume),
        if (showSide) ...[
          const SizedBox(width: 16),
          _SideBtn(icon: Icons.skip_next_rounded, color: Colors.white30,
              onTap: () => onSkip()),
        ],
      ],
    );
  }
}

class _MainBtn extends StatelessWidget {
  final TimerPhase phase;
  final Color      color;
  final VoidCallback onStart, onPause, onResume;

  const _MainBtn({required this.phase, required this.color,
      required this.onStart, required this.onPause, required this.onResume});

  @override
  Widget build(BuildContext context) {
    final (icon, label, action) = switch (phase) {
      TimerPhase.idle     => (Icons.play_arrow_rounded, 'Start',  onStart),
      TimerPhase.running  => (Icons.pause_rounded,      'Pause',  onPause),
      TimerPhase.paused   => (Icons.play_arrow_rounded, 'Resume', onResume),
      TimerPhase.finished => (Icons.play_arrow_rounded, 'Start',  onStart),
    };
    return GestureDetector(
      onTap: action,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80, height: 80,
        decoration: BoxDecoration(
          color:  color.withValues(alpha: 0.15),
          shape:  BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20),
              blurRadius: 20, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            Text(label, style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SideBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;
  const _SideBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color:  Colors.white.withValues(alpha: 0.05),
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );
}