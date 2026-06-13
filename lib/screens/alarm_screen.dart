// alarm_screen.dart
//
// Full-screen alarm overlay — matches the dark warm-glow style in the screenshot.
// Shown by AlarmService when one or more reminders fire simultaneously.
//
// Features:
//   • Animated warm radial glow (amber/orange, pulses)
//   • Large digital time + date
//   • Lists ALL reminders firing at this alarm time
//   • "Snooze for 10 Min" button  → reschedules all listed reminders +10 min
//   • "Swipe up to stop" gesture  → dismisses alarm and removes those reminders
//   • Works on lock screen via FLAG_KEEP_SCREEN_ON + showWhenLocked

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/reminder_model.dart';
import '../services/alarm_service.dart';

class AlarmScreen extends StatefulWidget {
  /// All reminders that fired together at this alarm time.
  final List<Reminder> reminders;

  const AlarmScreen({super.key, required this.reminders});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double>   _glowAnim;
  late Timer               _clockTicker;
  DateTime                 _now = DateTime.now();

  // Swipe-up gesture tracking
  double _swipeDelta = 0;
  static const _swipeThreshold = 120.0;

  @override
  void initState() {
    super.initState();

    // Keep screen on and show over lock screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _glowCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _clockTicker.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _snooze() async {
    await AlarmService.instance.snoozeAll(widget.reminders);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stop() async {
    await AlarmService.instance.stopAll(widget.reminders);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm').format(_now);
    final ampm    = DateFormat('a').format(_now);
    final dateStr = DateFormat('EEE, MMM d').format(_now);

    return PopScope(
      // Prevent back-button dismissal — user must swipe or tap
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onVerticalDragUpdate: (d) {
            setState(() => _swipeDelta += d.primaryDelta ?? 0);
          },
          onVerticalDragEnd: (_) {
            if (_swipeDelta < -_swipeThreshold) {
              _stop();
            } else {
              setState(() => _swipeDelta = 0);
            }
          },
          child: AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, __) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0500),
                ),
                child: Stack(
                  children: [
                    // ── Background glow layers ────────────────
                    _GlowLayer(
                      alignment: const Alignment(0.0, -0.15),
                      color:     const Color(0xFFD4640A),
                      radius:    0.65,
                      opacity:   _glowAnim.value * 0.38,
                    ),
                    _GlowLayer(
                      alignment: const Alignment(0.0, 0.55),
                      color:     const Color(0xFF8B3A00),
                      radius:    0.55,
                      opacity:   _glowAnim.value * 0.28,
                    ),

                    // ── Content ───────────────────────────────
                    SafeArea(
                      child: Column(
                        children: [
                          // Time block
                          const Spacer(flex: 2),
                          _TimeBlock(
                              timeStr: timeStr,
                              ampm:    ampm,
                              dateStr: dateStr),

                          // Glow spacer
                          const Spacer(flex: 3),

                          // Reminder titles
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40),
                            child: _ReminderList(
                                reminders: widget.reminders),
                          ),

                          const SizedBox(height: 28),

                          // Snooze button
                          _SnoozeButton(onTap: _snooze),

                          const Spacer(flex: 2),

                          // Swipe hint  (fades when dragging)
                          AnimatedOpacity(
                            opacity: _swipeDelta.abs() > 20 ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: const _SwipeHint(),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),

                    // Swipe-up progress indicator
                    if (_swipeDelta < -10)
                      Positioned(
                        bottom: 0,
                        left:   0,
                        right:  0,
                        child:  LinearProgressIndicator(
                          value: (_swipeDelta.abs() / _swipeThreshold)
                              .clamp(0.0, 1.0),
                          backgroundColor: Colors.white10,
                          color:           Colors.white38,
                          minHeight:       3,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────

class _GlowLayer extends StatelessWidget {
  final Alignment alignment;
  final Color     color;
  final double    radius;
  final double    opacity;

  const _GlowLayer({
    required this.alignment,
    required this.color,
    required this.radius,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Container(
          width:  MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.55,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withOpacity(opacity),
                Colors.transparent,
              ],
              radius: radius,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String timeStr;
  final String ampm;
  final String dateStr;

  const _TimeBlock({
    required this.timeStr,
    required this.ampm,
    required this.dateStr,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              timeStr,
              style: const TextStyle(
                color:         Colors.white,
                fontSize:      96,
                fontWeight:    FontWeight.w200,
                letterSpacing: -4,
                height:        1.0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 18, left: 6),
              child: Text(
                ampm,
                style: const TextStyle(
                  color:      Colors.white70,
                  fontSize:   22,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          dateStr,
          style: const TextStyle(
            color:    Colors.white54,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}

class _ReminderList extends StatelessWidget {
  final List<Reminder> reminders;
  const _ReminderList({required this.reminders});

  @override
  Widget build(BuildContext context) {
    if (reminders.length == 1) {
      return Text(
        reminders.first.title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color:      Colors.white,
          fontSize:   22,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
        ),
      );
    }

    return Column(
      children: reminders.map((r) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                r.title,
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   19,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SnoozeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SnoozeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:   260,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text(
            'Snooze for 10 Min',
            style: TextStyle(
              color:      Colors.white,
              fontSize:   17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.keyboard_arrow_up_rounded,
            color: Colors.white38, size: 28),
        const SizedBox(height: 2),
        const Text(
          'Swipe up to stop alarm',
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      ],
    );
  }
}