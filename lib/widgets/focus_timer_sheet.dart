// widgets/focus_timer_sheet.dart  — FULL REPLACEMENT
//
// Dismissible: closing the sheet leaves the timer running in background.
// Re-opening always rejoins the live session.
// Includes tick-sound toggle button.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/focus_timer_service.dart';

// ── Entry point ───────────────────────────────────────────────────

void showFocusTimerSheet(BuildContext context, Project project) {
  final svc = FocusTimerService.instance;

  // Only configure (reset) if there is NO active session, or if the
  // active session belongs to a different project.
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
    isDismissible:      true,   // ← dismissible: timer keeps running
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

class _FocusTimerSheetState extends State<FocusTimerSheet>
    with TickerProviderStateMixin {

  final _svc = FocusTimerService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onStateChange);
    // Show dialog immediately if a segment just completed while sheet was away.
    if (_svc.pendingFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _svc.clearPendingFinished();
          _showFinishedDialog();
        }
      });
    }
  }

  void _onStateChange() {
    if (!mounted) return;
    setState(() {});
    if (_svc.state.phase == TimerPhase.finished && _svc.pendingFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _svc.clearPendingFinished();
          _showFinishedDialog();
        }
      });
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onStateChange);
    super.dispose();
  }

  // ── Dialogs ───────────────────────────────────────────────────

  void _showFinishedDialog() {
    // By the time this fires, _advanceToNextSegment + start() have already
    // run — so _svc.state now reflects the NEW segment (break or work) that
    // is already ticking. We just inform the user and offer a Stop option.
    final s = _svc.state;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _FinishedDialog(
        state: s,
        onStop: () {
          Navigator.pop(ctx);
          _svc.stop();
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s          = _svc.state;
    final phaseColor = _phaseColor(s.sessionType);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color:        Color(0xFF0E0E0E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── Top bar ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Dismiss (timer keeps running)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:        Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54, size: 20),
                  ),
                ),
                const Spacer(),
                // Project pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color:  widget.project.priority.bgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.project.priority.color.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.project.priority.emoji,
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
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
                // Session counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${s.completedWork} done',
                    style: const TextStyle(
                      color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Preset picker ─────────────────────────────────
           _PresetPicker(
            preset:   s.preset,
            enabled:  !s.isActive,
            onSelect: (p) => _svc.configure(
              preset:      p,
              projectId:   widget.project.id,
              projectName: widget.project.name,
            ),
          ),

          const SizedBox(height: 28),

          // ── Ring ──────────────────────────────────────────
          Expanded(
            child: Center(
              child: _TimerRing(
                progress:  s.progress,
                remaining: s.remainingSeconds,
                total:     s.totalSeconds,
                color:     phaseColor,
                phase:     s.sessionType,
              ),
            ),
          ),

          // ── Phase label ───────────────────────────────────
          Text(
            s.sessionType.label.toUpperCase(),
            style: TextStyle(
              color: phaseColor, fontSize: 13,
              fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
          const SizedBox(height: 4),
          Text(
            _phaseSubtitle(s),
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),

          const SizedBox(height: 28),

          // ── Controls ──────────────────────────────────────
          _Controls(
            phase:    s.phase,
            onStart:  _svc.start,
            onPause:  _svc.pause,
            onResume: _svc.resume,
            onSkip:   _svc.skip,
            onReset:  _svc.reset,
            color:    phaseColor,
          ),

          const SizedBox(height: 20),

          // ── Tick sound toggle + background note ───────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () =>
                    _svc.setTickEnabled(!_svc.tickSoundEnabled),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _svc.tickSoundEnabled
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _svc.tickSoundEnabled
                          ? Colors.white24
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _svc.tickSoundEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: _svc.tickSoundEnabled
                            ? Colors.white54
                            : Colors.white24,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _svc.tickSoundEnabled ? 'Tick on' : 'Tick off',
                        style: TextStyle(
                          color: _svc.tickSoundEnabled
                              ? Colors.white54
                              : Colors.white24,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // "Running in background" pill — only when active
              if (s.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color:        const Color(0xFF32D74B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF32D74B).withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_tethering_rounded,
                          color: Color(0xFF32D74B), size: 13),
                      SizedBox(width: 6),
                      Text(
                        'Runs in background',
                        style: TextStyle(
                          color:      Color(0xFF32D74B),
                          fontSize:   11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Color _phaseColor(SessionType t) => switch (t) {
        SessionType.work       => const Color(0xFFFF453A),
        SessionType.shortBreak => const Color(0xFF32D74B),
        SessionType.longBreak  => const Color(0xFF0A84FF),
      };

  String _phaseSubtitle(FocusTimerState s) {
    if (s.phase == TimerPhase.idle)   return 'Ready when you are';
    if (s.phase == TimerPhase.paused) return 'Paused — tap Resume to continue';
    if (!s.isWork) {
      final next = s.preset.sessionsUntilLongBreak -
          (s.completedWork % s.preset.sessionsUntilLongBreak);
      return '$next more session${next == 1 ? '' : 's'} until long break';
    }
    return 'Stay locked in';
  }
}

// ── Preset picker ─────────────────────────────────────────────────

class _PresetPicker extends StatelessWidget {
  final TimerPreset preset;
  final bool        enabled;
  final ValueChanged<TimerPreset> onSelect;

  const _PresetPicker(
      {required this.preset, required this.enabled, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                style: const TextStyle(color: Colors.white24, fontSize: 13),
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

    // Track
    canvas.drawArc(
      rect, 0, math.pi * 2, false,
      Paint()
        ..color       = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = sw
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round,
    );

    if (progress > 0) {
      // Glow
      canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * progress, false,
        Paint()
          ..color       = color.withValues(alpha: 0.20)
          ..strokeWidth = sw + 10
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      // Arc
      canvas.drawArc(
        rect, -math.pi / 2, math.pi * 2 * progress, false,
        Paint()
          ..color       = color
          ..strokeWidth = sw
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Controls ──────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final TimerPhase phase;
  final VoidCallback          onStart;
  final VoidCallback          onPause;
  final VoidCallback          onResume;
  final Future<void> Function() onSkip;
  final VoidCallback          onReset;
  final Color color;

  const _Controls({
    required this.phase,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onSkip,
    required this.onReset,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (phase == TimerPhase.running || phase == TimerPhase.paused) ...[
          _ControlBtn(icon: Icons.refresh_rounded, color: Colors.white30,
              size: 44, onTap: onReset),
          const SizedBox(width: 16),
        ],
        _MainBtn(phase: phase, color: color,
            onStart: onStart, onPause: onPause, onResume: onResume),
        if (phase == TimerPhase.running || phase == TimerPhase.paused) ...[
          const SizedBox(width: 16),
          _ControlBtn(icon: Icons.skip_next_rounded, color: Colors.white30,
              size: 44, onTap: () => onSkip()),
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
      TimerPhase.finished => (Icons.play_arrow_rounded, 'Next',   onStart),
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
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.20),
                blurRadius: 20, spreadRadius: 2),
          ],
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

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final double   size;
  final VoidCallback onTap;
  const _ControlBtn({required this.icon, required this.color,
      required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: color, size: size * 0.45),
        ),
      );
}

// ── Finished dialog ───────────────────────────────────────────────
// The next segment is ALREADY running when this dialog appears.
// We just inform the user — no "Start" button needed.

class _FinishedDialog extends StatelessWidget {
  final FocusTimerState state;       // the NEW segment now running
  final VoidCallback    onStop;
  final VoidCallback    onDismiss;

  const _FinishedDialog({
    required this.state,
    required this.onStop,
    required this.onDismiss,
  });

  Color get _phaseColor => switch (state.sessionType) {
        SessionType.work       => const Color(0xFFFF453A),
        SessionType.shortBreak => const Color(0xFF32D74B),
        SessionType.longBreak  => const Color(0xFF0A84FF),
      };

  @override
  Widget build(BuildContext context) {
    final isBreak  = !state.isWork;
    final color    = _phaseColor;
    final mins     = state.totalSeconds ~/ 60;

    final (emoji, headline, body) = isBreak
        ? (
            '🎉',
            'Session complete!',
            '${state.completedWork} session${state.completedWork == 1 ? '' : 's'} done.'
            '${state.sessionType.label} ($mins min) has started automatically.',
          )
        : (
            '⚡',
            'Break over!',
            'Back to focus — ${state.preset.workMinutes} min sessionhas started automatically.',
          );

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            headline,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            body,
            style: const TextStyle(
                color: Colors.white60, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          // Live mini-timer so the user can see it ticking inside the dialog
          ListenableBuilder(
            listenable: FocusTimerService.instance,
            builder: (_, __) {
              final s = FocusTimerService.instance.state;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.sessionType.emoji,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      s.mmss,
                      style: TextStyle(
                        color:         color,
                        fontSize:      22,
                        fontWeight:    FontWeight.w300,
                        letterSpacing: -0.5,
                        fontFeatures:  const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: onStop,
          child: const Text('Stop timer',
              style: TextStyle(color: Colors.white38)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.20),
            foregroundColor: color,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
          ),
          onPressed: onDismiss,
          child: const Text('Got it',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}