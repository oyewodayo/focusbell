// widgets/focus_live_banner.dart
//
// Drop into lib/widgets/.
// A live banner widget that replaces "Start Focus Session" on the home screen
// when a timer is active. Shows real-time countdown, phase colour, tick toggle,
// and a tap-to-reopen affordance.

import 'package:flutter/material.dart';
import 'package:focusbell/models/focus_settings.dart';
import '../models/focus_session.dart';
import '../models/project.dart';
import '../services/focus_timer_service.dart';
import 'focus_timer_sheet.dart';

// ── Finished notification shown on home screen when sheet is closed ──────────

// NEW — add Project parameter
void showFinishedBannerIfNeeded(BuildContext context, Project project) {
  final svc = FocusTimerService.instance;
  if (!svc.pendingFinished) return;

  final s = svc.state;
  final isBreak = !s.isWork;
  final color = isBreak ? const Color(0xFF32D74B) : const Color(0xFFFF453A);
  final label = isBreak
      ? '${s.sessionType.emoji} ${s.sessionType.label} started · ${s.totalSeconds ~/ 60} min'
      : 'Focus session started · ${s.totalSeconds ~/ 60} min';

  // Capture the navigator BEFORE the snackbar is built
  final navigator = Navigator.of(context); // ← key fix

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Text(s.sessionType.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Open',
        textColor: color,
        onPressed: () {
          // Use the pre-captured navigator's context, not the snackbar's
          showFocusTimerSheet(navigator.context, project); // ← key fix
        },
      ),
    ),
  );
}

// ── Public widget ─────────────────────────────────────────────────

class FocusSessionButton extends StatelessWidget {
  final Project project;

  const FocusSessionButton({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FocusTimerService.instance,
      builder: (context, _) {
        final svc = FocusTimerService.instance;
        final state = svc.state;

        // If a segment just completed and the sheet isn't open, fire a snackbar.
        if (svc.pendingFinished) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) showFinishedBannerIfNeeded(context, project);
          });
        }

        // Active session for THIS project → live banner
        if (state.isActive && state.projectId == project.id) {
          return _LiveBanner(project: project, state: state, svc: svc);
        }

        // Active session for a DIFFERENT project → muted indicator
        if (state.isActive && state.projectId != project.id) {
          return _OtherProjectBanner(state: state);
        }

        // No active session → standard "Start" button
        return _StartButton(project: project);
      },
    );
  }
}

// ── Live banner ───────────────────────────────────────────────────

class _LiveBanner extends StatelessWidget {
  final Project project;
  final FocusTimerState state;
  final FocusTimerService svc;

  const _LiveBanner({
    required this.project,
    required this.state,
    required this.svc,
  });

  Color get _phaseColor => switch (state.sessionType) {
    SessionType.work => const Color(0xFFFF453A),
    SessionType.shortBreak => const Color(0xFF32D74B),
    SessionType.longBreak => const Color(0xFF0A84FF),
  };

  @override
  Widget build(BuildContext context) {
    final color = _phaseColor;
    final isPaused = state.phase == TimerPhase.paused;

    return GestureDetector(
      onTap: () => showFocusTimerSheet(context, project),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: isPaused ? 0.20 : 0.40),
            width: 1.5,
          ),
          boxShadow: isPaused
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top row: phase label + time + controls ────
            Row(
              children: [
                // Phase icon + label
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.sessionType.emoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.sessionType.label.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (isPaused) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PAUSED',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const Spacer(),

                // Live countdown
                Text(
                  state.mmss,
                  style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.w200,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                const SizedBox(width: 12),

                // Quick controls (pause / resume)
                _QuickControl(
                  icon: isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: color,
                  onTap: isPaused ? svc.resume : svc.pause,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Progress bar ──────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),

            const SizedBox(height: 10),

            // ── Bottom row: session count + tick + open hint
            Row(
              children: [
                // Sessions done
                Text(
                  '${state.completedWork} session${state.completedWork == 1 ? '' : 's'} done',
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),

                const Spacer(),

                // Tick toggle — uses new settings API
                GestureDetector(
                  onTap: () => svc.updateSettings(
                    svc.settings.copyWith(
                      tickEnabled: svc.settings.focusSound != FocusSound.silent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        svc.settings.focusSound != FocusSound.silent
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: svc.settings.focusSound != FocusSound.silent
                            ? Colors.white38
                            : Colors.white24,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        svc.settings.focusSound != FocusSound.silent ? 'Tick on' : 'Tick off',
                        style: TextStyle(
                          color: svc.settings.focusSound != FocusSound.silent
                              ? Colors.white38
                              : Colors.white24,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Tap-to-expand hint
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_full_rounded,
                      color: color.withValues(alpha: 0.5),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to open',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Other-project muted banner ────────────────────────────────────

class _OtherProjectBanner extends StatelessWidget {
  final FocusTimerState state;
  const _OtherProjectBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white24, size: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Focusing on "${state.projectName ?? 'another project'}" · ${state.mmss}',
              style: const TextStyle(color: Colors.white30, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Start button ──────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  final Project project;
  const _StartButton({required this.project});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showFocusTimerSheet(context, project),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: project.priority.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: project.priority.color.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_rounded, color: project.priority.color, size: 18),
            const SizedBox(width: 8),
            Text(
              'Start Focus Session',
              style: TextStyle(
                color: project.priority.color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick control pill ────────────────────────────────────────────

class _QuickControl extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickControl({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
