// screens/alarm_screen.dart — FULL REPLACEMENT
//
// Features:
//   • Smart Snooze (Feature #1): 5 min, 15 min, 1 hour, Tonight 9pm,
//     Tomorrow 9am — with animated pill selector
//   • Focus Guard (Feature #6): if a focus session is active when alarm
//     fires, shows a special "Held for focus" screen instead of ringing.
//     Reminders are queued and shown as a summary when session ends.
//   • Polished alarm UI with priority colour, countdown, stagger animations

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/reminder_model.dart';
import '../services/alarm_service.dart';
import '../services/focus_timer_service.dart';
import '../services/reminder_service.dart';

// ─────────────────────────────────────────────────────────────────
// Snooze option model
// ─────────────────────────────────────────────────────────────────

class _SnoozeOption {
  final String label;
  final String sublabel;
  final Duration? duration;      // null = absolute time
  final DateTime? Function()? absoluteTime;

  const _SnoozeOption({
    required this.label,
    required this.sublabel,
    this.duration,
    this.absoluteTime,
  });

  Duration resolve() {
    if (duration != null) return duration!;
    final target = absoluteTime!();
    if (target == null) return const Duration(minutes: 15);
    final diff = target.difference(DateTime.now());
    return diff.isNegative ? const Duration(hours: 12) : diff;
  }
}

final _kSnoozeOptions = <_SnoozeOption>[
  _SnoozeOption(
    label: '5 min',
    sublabel: 'Quick snooze',
    duration: const Duration(minutes: 5),
  ),
  _SnoozeOption(
    label: '15 min',
    sublabel: 'Short break',
    duration: const Duration(minutes: 15),
  ),
  _SnoozeOption(
    label: '1 hour',
    sublabel: 'Come back later',
    duration: const Duration(hours: 1),
  ),
  _SnoozeOption(
    label: 'Tonight',
    sublabel: '9:00 PM',
    absoluteTime: () {
      final now = DateTime.now();
      final t = DateTime(now.year, now.month, now.day, 21, 0);
      return t.isAfter(now) ? t : t.add(const Duration(days: 1));
    },
  ),
  _SnoozeOption(
    label: 'Tomorrow',
    sublabel: '9:00 AM',
    absoluteTime: () {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 1, 9, 0);
    },
  ),
];

// ─────────────────────────────────────────────────────────────────
// AlarmScreen
// ─────────────────────────────────────────────────────────────────

class AlarmScreen extends StatefulWidget {
  final List<Reminder> reminders;

  const AlarmScreen({super.key, required this.reminders});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {

  // Focus guard
  bool get _focusActive =>
      FocusTimerService.instance.state.isActive;

  // Snooze selection
  int _selectedSnooze = 1; // default = 15 min

  // Entry animations
  late final List<AnimationController> _itemCtrls;
  late final List<Animation<double>>   _itemAnims;

  // Bell pulse
  late final AnimationController _bellCtrl;
  late final Animation<double>   _bellAnim;

  // Dismiss animation
  late final AnimationController _dismissCtrl;
  late final Animation<Offset>   _slideAnim;

  // Focus-guard listener
  late final VoidCallback _focusListener;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();

    _wasActive = _focusActive;

    // If focus session is active, queue reminders silently — don't ring
    if (_focusActive) {
      FocusGuardQueue.instance.hold(widget.reminders);
      // Stop the alarm sound immediately
      AlarmService.instance.silenceAlarm(widget.reminders);
    }

    // Watch for focus session ending while screen is up
    _focusListener = () {
      final nowActive = FocusTimerService.instance.state.isActive;
      if (_wasActive && !nowActive) {
        // Session just ended — rebuild to show held reminders
        if (mounted) setState(() => _wasActive = false);
      }
      _wasActive = nowActive;
    };
    FocusTimerService.instance.addListener(_focusListener);

    // Bell pulse
    _bellCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _bellAnim = Tween<double>(begin: -0.06, end: 0.06).animate(
      CurvedAnimation(parent: _bellCtrl, curve: Curves.easeInOut),
    );

    // Dismiss slide
    _dismissCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: Offset.zero, end: const Offset(0, 1),
    ).animate(CurvedAnimation(parent: _dismissCtrl, curve: Curves.easeInCubic));

    // Stagger item animations
    final count = widget.reminders.length + 1; // +1 for snooze row
    _itemCtrls = List.generate(count, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400),
    ));
    _itemAnims = _itemCtrls.map((c) =>
      CurvedAnimation(parent: c, curve: Curves.easeOutCubic)).toList();

    // Staggered entry
    for (int i = 0; i < _itemCtrls.length; i++) {
      Future.delayed(Duration(milliseconds: 120 + i * 80), () {
        if (mounted) _itemCtrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _itemCtrls) c.dispose();
    _bellCtrl.dispose();
    _dismissCtrl.dispose();
    FocusTimerService.instance.removeListener(_focusListener);
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> _snooze() async {
    final option = _kSnoozeOptions[_selectedSnooze];
    final by = option.resolve();
    await _dismiss();
    await ReminderService.instance.snoozeAll(widget.reminders, by);
    await AlarmService.instance.stopAlarm(widget.reminders);
  }

  Future<void> _dismiss() async {
    await _dismissCtrl.forward();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _done() async {
    await _dismiss();
    await AlarmService.instance.stopAll(widget.reminders);
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show held-for-focus screen when session is active
    if (_focusActive) return _buildFocusGuardScreen();

    // Show post-focus summary if reminders were held
    final held = FocusGuardQueue.instance.heldReminders;
    final allReminders = {
      ...widget.reminders,
      ...held,
    }.toList();
    FocusGuardQueue.instance.clear();

    return SlideTransition(
      position: _slideAnim,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D0D0D), Color(0xFF0A0A0A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(allReminders),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: allReminders.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final idx = math.min(i, _itemAnims.length - 2);
                        return FadeTransition(
                          opacity: _itemAnims[idx],
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(_itemAnims[idx]),
                            child: _ReminderCard(
                              reminder: allReminders[i],
                              wasHeld: held.contains(allReminders[i]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Snooze pill selector
                  FadeTransition(
                    opacity: _itemAnims.last,
                    child: _SnoozeSelector(
                      selected: _selectedSnooze,
                      onSelect: (i) => setState(() => _selectedSnooze = i),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(children: [
                    Expanded(
                      child: _ActionBtn(
                        label: 'Snooze  ${_kSnoozeOptions[_selectedSnooze].label}',
                        icon: CupertinoIcons.moon_zzz_fill,
                        color: const Color(0xFF2C2C2E),
                        textColor: Colors.white70,
                        onTap: _snooze,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionBtn(
                        label: 'Done',
                        icon: CupertinoIcons.checkmark_circle_fill,
                        color: const Color(0xFF0A84FF),
                        textColor: Colors.white,
                        onTap: _done,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header with animated bell ─────────────────────────────────

  Widget _buildHeader(List<Reminder> all) {
    final held = all.where((r) =>
        FocusGuardQueue.instance.heldReminders.contains(r)).length;

    return Row(children: [
      AnimatedBuilder(
        animation: _bellAnim,
        builder: (_, child) => Transform.rotate(
          angle: _bellAnim.value,
          child: child,
        ),
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF0A84FF).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.bell_fill,
            color: Color(0xFF0A84FF),
            size: 24,
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            all.length == 1 ? 'Reminder' : '${all.length} Reminders',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          if (held > 0)
            Text(
              '$held held during focus session',
              style: const TextStyle(
                color: Color(0xFF0A84FF),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              _timeLabel(),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
        ]),
      ),
      GestureDetector(
        onTap: _done,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(CupertinoIcons.xmark, color: Colors.white24, size: 20),
        ),
      ),
    ]);
  }

  String _timeLabel() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ap = now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  // ── Focus guard screen ────────────────────────────────────────

  Widget _buildFocusGuardScreen() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D10), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Focus shield icon
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0A84FF).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.lock_shield_fill,
                    color: Color(0xFF0A84FF),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Held for Focus',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.reminders.length == 1
                      ? '1 reminder arrived while you were\nin a focus session.'
                      : '${widget.reminders.length} reminders arrived while\nyou were in a focus session.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Preview cards
                ...widget.reminders.take(3).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HeldReminderChip(reminder: r),
                )),
                if (widget.reminders.length > 3)
                  Text(
                    '+ ${widget.reminders.length - 3} more',
                    style: const TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                const SizedBox(height: 40),
                const Text(
                  "You'll see these when your session ends.",
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 24),
                // Allow dismissing if urgent
                GestureDetector(
                  onTap: () {
                    FocusGuardQueue.instance.clear();
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Dismiss anyway',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FocusGuardQueue — singleton that holds reminders during focus
// ─────────────────────────────────────────────────────────────────

class FocusGuardQueue {
  FocusGuardQueue._();
  static final FocusGuardQueue instance = FocusGuardQueue._();

  final List<Reminder> _held = [];
  List<Reminder> get heldReminders => List.unmodifiable(_held);
  bool get hasHeld => _held.isNotEmpty;

  void hold(List<Reminder> reminders) {
    for (final r in reminders) {
      if (!_held.any((h) => h.id == r.id)) _held.add(r);
    }
  }

  void clear() => _held.clear();
}

// ─────────────────────────────────────────────────────────────────
// _ReminderCard
// ─────────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final bool wasHeld;

  const _ReminderCard({required this.reminder, this.wasHeld = false});

  Color get _priorityColor {
    switch (reminder.priority) {
      case ReminderPriority.high:   return const Color(0xFFFF453A);
      case ReminderPriority.normal: return const Color(0xFF0A84FF);
      case ReminderPriority.low:    return const Color(0xFF30D158);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: wasHeld
              ? const Color(0xFF0A84FF).withOpacity(0.25)
              : _priorityColor.withOpacity(0.2),
        ),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _priorityColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            wasHeld
                ? CupertinoIcons.lock_shield
                : CupertinoIcons.bell_fill,
            color: wasHeld ? const Color(0xFF0A84FF) : _priorityColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              reminder.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (reminder.notes != null && reminder.notes!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                reminder.notes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ]),
        ),
        if (wasHeld)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Held',
              style: TextStyle(
                color: Color(0xFF0A84FF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// _HeldReminderChip — compact version for focus guard screen
// ─────────────────────────────────────────────────────────────────

class _HeldReminderChip extends StatelessWidget {
  final Reminder reminder;
  const _HeldReminderChip({required this.reminder});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        const Icon(CupertinoIcons.bell, color: Colors.white38, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            reminder.title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// _SnoozeSelector — horizontal pill picker
// ─────────────────────────────────────────────────────────────────

class _SnoozeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _SnoozeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 2, bottom: 10),
        child: Text(
          'SNOOZE FOR',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _kSnoozeOptions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final opt = _kSnoozeOptions[i];
            final isSelected = i == selected;
            return GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0A84FF)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0A84FF)
                        : Colors.white10,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(
                          color: const Color(0xFF0A84FF).withOpacity(0.3),
                          blurRadius: 12, offset: const Offset(0, 4),
                        )]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      opt.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opt.sublabel,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white70
                            : Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// _ActionBtn
// ─────────────────────────────────────────────────────────────────

class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 100),
      lowerBound: 0.95, upperBound: 1.0, value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => _ctrl.reverse(),
      onTapUp:    (_) { _ctrl.forward(); widget.onTap(); },
      onTapCancel: ()  => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: widget.textColor, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}