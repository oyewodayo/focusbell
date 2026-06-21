// widgets/continuity_card.dart — NEW FILE
//
// The Continuity Card — a dismissible briefing panel that surfaces
// at the top of the home screen when the user returns after being idle.
//
// Design:
//   • Slides down from above the content with spring physics
//   • Three urgency tiers: low (subtle), medium (blue), high (amber)
//   • Missed reminders shown as inline chips
//   • Upcoming reminder shown with countdown
//   • "Resume session" CTA if a focus session was interrupted
//   • Swipe up or tap × to dismiss
//   • Auto-dismisses after 30s if user is reading

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:focusbell/models/reminder_model.dart';
import 'package:intl/intl.dart';

import '../services/continuity_service.dart';
import '../services/focus_timer_service.dart';

class ContinuityCard extends StatefulWidget {
  final ContinuitySnapshot snapshot;
  final VoidCallback        onDismiss;
  final VoidCallback?       onResumeSession;

  const ContinuityCard({
    super.key,
    required this.snapshot,
    required this.onDismiss,
    this.onResumeSession,
  });

  @override
  State<ContinuityCard> createState() => _ContinuityCardState();
}

class _ContinuityCardState extends State<ContinuityCard>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<Offset>   _slide;
  late Animation<double>   _fade;
  late Animation<double>   _scale;

  Timer? _autoDismiss;
  double _dismissProgress = 1.0; // 1.0 = full, 0.0 = auto-dismissed

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();

    // Auto-dismiss countdown
    _autoDismiss = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _dismissProgress = 1 - (t.tick / 30);
      });
      if (t.tick >= 30) {
        t.cancel();
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _autoDismiss?.cancel();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _autoDismiss?.cancel();
    await _ctrl.reverse();
    widget.onDismiss();
  }

  Color get _accentColor {
    switch (widget.snapshot.urgency) {
      case ContinuityUrgency.high:   return const Color(0xFFFF9F0A);
      case ContinuityUrgency.medium: return const Color(0xFF0A84FF);
      case ContinuityUrgency.low:    return const Color(0xFF30D158);
    }
  }

  String get _urgencyEmoji {
    switch (widget.snapshot.urgency) {
      case ContinuityUrgency.high:   return '⚡';
      case ContinuityUrgency.medium: return '📋';
      case ContinuityUrgency.low:    return '✨';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! < -200) {
                _dismiss();
              }
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _accentColor.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color:      _accentColor.withOpacity(0.08),
                    blurRadius: 24,
                    offset:     const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header bar ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                    decoration: BoxDecoration(
                      color:        _accentColor.withOpacity(0.08),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(19)),
                    ),
                    child: Row(children: [
                      Text(_urgencyEmoji,
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      const Text('Quick Brief',
                          style: TextStyle(
                            color:      Colors.white,
                            fontSize:   13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          )),
                      const SizedBox(width: 8),
                      Text(_awayLabel,
                          style: TextStyle(
                            color:    _accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                      const Spacer(),
                      // Auto-dismiss progress arc
                      SizedBox(
                        width: 20, height: 20,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(
                            value:        _dismissProgress,
                            strokeWidth:  2,
                            color:        Colors.white12,
                            backgroundColor: Colors.transparent,
                          ),
                          GestureDetector(
                            onTap: _dismiss,
                            child: const Icon(CupertinoIcons.xmark,
                                color: Colors.white38, size: 11),
                          ),
                        ]),
                      ),
                    ]),
                  ),

                  // ── Briefing text ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      widget.snapshot.briefing,
                      style: const TextStyle(
                        color:      Colors.white70,
                        fontSize:   14,
                        height:     1.55,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),

                  // ── Missed reminders chips ───────────────────
                  if (widget.snapshot.missedReminders.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(spacing: 6, runSpacing: 6,
                        children: widget.snapshot.missedReminders
                            .take(4)
                            .map((r) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF453A).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFFFF453A).withOpacity(0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.bell_slash,
                                color: Color(0xFFFF453A), size: 11),
                            const SizedBox(width: 5),
                            Text(
                              r.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color:      Color(0xFFFF453A),
                                fontSize:   11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ]),
                        )).toList(),
                      ),
                    ),
                  ],

                  // ── Upcoming reminder chip ────────────────────
                  if (widget.snapshot.upcomingReminders.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _UpcomingChip(
                          reminder: widget.snapshot.upcomingReminders.first,
                          color:    _accentColor),
                    ),
                  ],

                  // ── Resume session CTA ────────────────────────
                  if (widget.snapshot.activeSessionProject != null &&
                      widget.onResumeSession != null) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () {
                          _dismiss();
                          widget.onResumeSession!();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A84FF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF0A84FF).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.play_circle_fill,
                                  color: Color(0xFF0A84FF), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Resume: ${widget.snapshot.activeSessionProject}',
                                style: const TextStyle(
                                  color:      Color(0xFF0A84FF),
                                  fontSize:   13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Swipe hint ────────────────────────────────
                  Center(
                    child: Column(children: [
                      Container(
                        width: 32, height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('swipe up to dismiss',
                          style: TextStyle(
                              color: Colors.white12, fontSize: 10)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _awayLabel {
    final away = widget.snapshot.awayFor;
    if (away.inMinutes < 60) return '${away.inMinutes}m ago';
    if (away.inHours  < 24) return '${away.inHours}h ago';
    return '${away.inDays}d ago';
  }
}

// ── Upcoming chip ─────────────────────────────────────────────────────────────

class _UpcomingChip extends StatefulWidget {
  final Reminder reminder;
  final Color    color;
  const _UpcomingChip({required this.reminder, required this.color});

  @override
  State<_UpcomingChip> createState() => _UpcomingChipState();
}

class _UpcomingChipState extends State<_UpcomingChip> {
  late Timer _tick;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.reminder.dateTime.difference(DateTime.now());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _remaining = widget.reminder.dateTime.difference(DateTime.now());
        });
      }
    });
  }

  @override
  void dispose() { _tick.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes;
    final label = mins < 1  ? 'Now!'
        : mins < 60         ? 'in ${mins}m'
        :                     'in ${_remaining.inHours}h';
    final isUrgent = mins < 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.bell_fill, color: widget.color, size: 12),
        const SizedBox(width: 7),
        Text(widget.reminder.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:      widget.color,
              fontSize:   12,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
          color:      isUrgent ? const Color(0xFFFF453A) : Colors.white38,
          fontSize:   11,
          fontWeight: isUrgent ? FontWeight.w700 : FontWeight.w400,
        )),
      ]),
    );
  }
}