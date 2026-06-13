// reminders_screen.dart — FULL REPLACEMENT
//
// Add-sheet now includes:
//   • Repeat selector (Once / Mon–Sun)
//   • Priority picker (Low / Normal / High)
//   • Optional notes field
//   • "In X minutes" quick-set
//   • Date & time picker

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:intl/intl.dart';

import '../models/reminder_model.dart';   // ← NO hide here
import '../services/reminder_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _svc = ReminderService.instance;
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  // ── Add sheet ─────────────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final titleCtrl   = TextEditingController();
    final minutesCtrl = TextEditingController();
    final notesCtrl   = TextEditingController();

    DateTime?         picked;
    bool              useMinutes = false;
    RepeatMode        repeat     = RepeatMode.once;
    ReminderPriority  priority   = ReminderPriority.normal;

    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                decoration: BoxDecoration(
                  color:        const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(28),
                  border:       Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:       MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color:        Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'New Reminder',
                        style: TextStyle(
                          color:         Colors.white,
                          fontSize:      20,
                          fontWeight:    FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Title ──────────────────────────────
                      _SheetField(
                        controller: titleCtrl,
                        hint:       'Reminder title',
                        icon:       CupertinoIcons.bell,
                      ),
                      const SizedBox(height: 12),

                      // ── Time mode toggle ───────────────────
                      _TogglePill(
                        useMinutes: useMinutes,
                        onToggle:   (v) => setSheet(() => useMinutes = v),
                      ),
                      const SizedBox(height: 12),

                      // ── Time input ─────────────────────────
                      if (useMinutes)
                        _SheetField(
                          controller:   minutesCtrl,
                          hint:         'In how many minutes?',
                          icon:         CupertinoIcons.timer,
                          keyboardType: TextInputType.number,
                        )
                      else
                        _DateTimePicker(
                          selected: picked,
                          onPick:   (dt) => setSheet(() => picked = dt),
                        ),
                      const SizedBox(height: 12),

                      // ── Repeat ─────────────────────────────
                      _SectionLabel('Repeat'),
                      const SizedBox(height: 8),
                      _RepeatSelector(
                        selected: repeat,
                        onSelect: (r) => setSheet(() => repeat = r),
                      ),
                      const SizedBox(height: 12),

                      // ── Priority ───────────────────────────
                      _SectionLabel('Priority'),
                      const SizedBox(height: 8),
                      _PrioritySelector(
                        selected: priority,
                        onSelect: (p) => setSheet(() => priority = p),
                      ),
                      const SizedBox(height: 12),

                      // ── Notes (optional) ───────────────────
                      _SheetField(
                        controller: notesCtrl,
                        hint:       'Notes (optional)',
                        icon:       CupertinoIcons.doc_text,
                        maxLines:   3,
                      ),
                      const SizedBox(height: 20),

                      // ── Add button ─────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () async {
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) return;

                            DateTime? dt;
                            if (useMinutes) {
                              final mins =
                                  int.tryParse(minutesCtrl.text.trim());
                              if (mins == null || mins <= 0) return;
                              dt = DateTime.now()
                                  .add(Duration(minutes: mins));
                            } else {
                              // For repeating reminders with no explicit
                              // date picked, compute next occurrence from now
                              if (repeat != RepeatMode.once &&
                                  picked == null) {
                                final dummy = Reminder(
                                  id:       '',
                                  title:    title,
                                  dateTime: DateTime.now(),
                                  repeat:   repeat,
                                );
                                dt = dummy.nextOccurrence();
                              } else {
                                if (picked == null) return;
                                dt = picked;
                              }
                            }

                            final reminder = Reminder(
                              id:       '${DateTime.now().millisecondsSinceEpoch}',
                              title:    title,
                              dateTime: dt!,
                              repeat:   repeat,
                              priority: priority,
                              notes: notesCtrl.text.trim().isEmpty
                                  ? null
                                  : notesCtrl.text.trim(),
                            );
                            await _svc.add(reminder);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color:        const Color(0xFF0A84FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Text(
                                'Add Reminder',
                                style: TextStyle(
                                  color:      Colors.white,
                                  fontSize:   16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.back,
                        color: Colors.black54, size: 26),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Reminders',
                    style: TextStyle(
                      color:         Colors.black,
                      fontSize:      28,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const Spacer(),
                  _TopIconBtn(
                      icon:  CupertinoIcons.plus,
                      onTap: _showAddDialog),
                  const SizedBox(width: 4),
                  _TopIconBtn(
                      icon:  CupertinoIcons.ellipsis_vertical,
                      onTap: () {}),
                ],
              ),
            ),

            Expanded(
              child: ValueListenableBuilder<List<Reminder>>(
                valueListenable: _svc.reminders,
                builder: (_, reminders, __) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        // Analog clock
                        const SizedBox(height: 24),
                        Center(
                          child: SizedBox(
                            width: 220, height: 220,
                            child: _AnalogClock(now: _now),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Digital readout
                        Text(
                          DateFormat('hh:mm:ss a').format(_now),
                          style: const TextStyle(
                            color:         Colors.black,
                            fontSize:      46,
                            fontWeight:    FontWeight.w300,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEE, MMM d').format(_now),
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 15),
                        ),
                        Text(
                          'West Africa Standard Time',
                          style: TextStyle(
                            color:    Colors.black.withOpacity(0.35),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Reminder list
                        if (reminders.isEmpty)
                          _EmptyReminders(onAdd: _showAddDialog)
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            itemCount:      reminders.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 68,
                              color:  Color(0xFFE5E5EA),
                            ),
                            itemBuilder: (_, i) => _ReminderTile(
                              reminder: reminders[i],
                              now:      _now,
                              onDelete: () =>
                                  _svc.remove(reminders[i].id),
                            ),
                          ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:       _showAddDialog,
        backgroundColor: const Color(0xFF0A84FF),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        child: const Icon(CupertinoIcons.plus,
            color: Colors.white, size: 26),
      ),
    );
  }
}

// ── Repeat selector ───────────────────────────────────────────────

class _RepeatSelector extends StatelessWidget {
  final RepeatMode              selected;
  final ValueChanged<RepeatMode> onSelect;

  const _RepeatSelector({
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RepeatMode.values.map((mode) {
        final isSelected = mode == selected;
        return GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0A84FF)
                  : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0A84FF)
                    : Colors.white12,
              ),
            ),
            child: Text(
              mode.shortLabel,
              style: TextStyle(
                color:      isSelected ? Colors.white : Colors.white54,
                fontSize:   13,
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Priority selector ─────────────────────────────────────────────

class _PrioritySelector extends StatelessWidget {
  final ReminderPriority              selected;
  final ValueChanged<ReminderPriority> onSelect;

  const _PrioritySelector({
    required this.selected,
    required this.onSelect,
  });

  static const _items = [
    (ReminderPriority.low,    '↓ Low',    Color(0xFF30D158)),
    (ReminderPriority.normal, '→ Normal', Color(0xFF0A84FF)),
    (ReminderPriority.high,   '↑ High',   Color(0xFFFF453A)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _items.map((item) {
        final (mode, label, color) = item;
        final isSelected = mode == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.18)
                    : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : Colors.white12,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color:      isSelected ? color : Colors.white38,
                    fontSize:   13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color:      Colors.white38,
        fontSize:   12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

// ── Analog clock ──────────────────────────────────────────────────

class _AnalogClock extends StatelessWidget {
  final DateTime now;
  const _AnalogClock({required this.now});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ClockPainter(now), child: const SizedBox.expand());
}

class _ClockPainter extends CustomPainter {
  final DateTime now;
  const _ClockPainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = math.min(cx, cy);

    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = const Color(0xFFF2F2F7));
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color       = const Color(0xFFDDDDDD)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    for (int i = 0; i < 12; i++) {
      final angle  = (i / 12) * 2 * math.pi - math.pi / 2;
      final isMain = i % 3 == 0;
      final len    = isMain ? r * 0.12 : r * 0.06;
      canvas.drawLine(
        Offset(cx + (r - 12) * math.cos(angle),
               cy + (r - 12) * math.sin(angle)),
        Offset(cx + (r - 12 - len) * math.cos(angle),
               cy + (r - 12 - len) * math.sin(angle)),
        Paint()
          ..color       = Colors.black54
          ..strokeWidth = isMain ? 2.0 : 1.0
          ..strokeCap   = StrokeCap.round,
      );
    }

    _hand(canvas, cx, cy,
        angle:  ((now.hour % 12 + now.minute / 60) / 12) *
                    2 *
                    math.pi -
                math.pi / 2,
        length: r * 0.50,
        width:  6.0,
        color:  Colors.black);
    _hand(canvas, cx, cy,
        angle:  ((now.minute + now.second / 60) / 60) *
                    2 *
                    math.pi -
                math.pi / 2,
        length: r * 0.70,
        width:  4.0,
        color:  Colors.black);
    _hand(canvas, cx, cy,
        angle:  (now.second / 60) * 2 * math.pi - math.pi / 2,
        length: r * 0.75,
        width:  2.0,
        color:  const Color(0xFFFF3B30),
        tail:   r * 0.18);

    canvas.drawCircle(Offset(cx, cy), 6, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(cx, cy), 3,
        Paint()..color = const Color(0xFFFF3B30));
  }

  void _hand(
    Canvas canvas,
    double cx,
    double cy, {
    required double angle,
    required double length,
    required double width,
    required Color  color,
    double          tail = 0,
  }) {
    canvas.drawLine(
      Offset(cx - tail * math.cos(angle), cy - tail * math.sin(angle)),
      Offset(
          cx + length * math.cos(angle), cy + length * math.sin(angle)),
      Paint()
        ..color       = color
        ..strokeWidth = width
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) => old.now != now;
}

// ── Reminder tile ─────────────────────────────────────────────────

class _ReminderTile extends StatelessWidget {
  final Reminder     reminder;
  final DateTime     now;
  final VoidCallback onDelete;

  const _ReminderTile({
    required this.reminder,
    required this.now,
    required this.onDelete,
  });

  Color get _priorityColor {
    switch (reminder.priority) {
      case ReminderPriority.high:   return const Color(0xFFFF453A);
      case ReminderPriority.normal: return const Color(0xFF0A84FF);
      case ReminderPriority.low:    return const Color(0xFF30D158);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff     = reminder.dateTime.difference(now);
    final isPast   = diff.isNegative;
    final hrs      = diff.inHours.abs();
    final mins     = diff.inMinutes.abs();

    final countdown = isPast
        ? 'Passed'
        : hrs < 1
            ? 'In $mins min${mins == 1 ? '' : 's'}'
            : hrs < 24
                ? 'In $hrs hr${hrs == 1 ? '' : 's'}'
                : 'In ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';

    final timeStr = DateFormat('hh:mm a').format(reminder.dateTime);
    final dateStr = DateFormat('EEE, MMM d').format(reminder.dateTime);

    return Dismissible(
      key:        Key(reminder.id),
      direction:  DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 20),
        color:     const Color(0xFFFF3B30),
        child:     const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            // Priority-coloured bell icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: isPast
                    ? const Color(0xFFEEEEEE)
                    : _priorityColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                CupertinoIcons.bell_fill,
                color: isPast ? Colors.black26 : _priorityColor,
                size:  22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    style: TextStyle(
                      color:      isPast ? Colors.black38 : Colors.black87,
                      fontSize:   16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '$dateStr · $timeStr',
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 13),
                      ),
                      if (reminder.isRepeating) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A84FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            reminder.repeat.shortLabel,
                            style: const TextStyle(
                              color:    Color(0xFF0A84FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (reminder.notes != null &&
                      reminder.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      reminder.notes!,
                      maxLines:  1,
                      overflow:  TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.black38, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color:         isPast ? Colors.black26 : Colors.black,
                    fontSize:      22,
                    fontWeight:    FontWeight.w300,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  countdown,
                  style: TextStyle(
                    color:    isPast
                        ? Colors.black26
                        : _priorityColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────

class _EmptyReminders extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyReminders({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(children: [
        const Divider(color: Color(0xFFE5E5EA)),
        const SizedBox(height: 32),
        Icon(CupertinoIcons.bell_slash,
            size: 48, color: Colors.black.withOpacity(0.15)),
        const SizedBox(height: 14),
        const Text('No reminders yet',
            style: TextStyle(
                color: Colors.black54,
                fontSize: 17,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text(
          'Tap + to add a reminder\nby specific time or in X minutes.',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: Colors.black38, fontSize: 14, height: 1.5),
        ),
      ]),
    );
  }
}

// ── Sheet sub-widgets ─────────────────────────────────────────────

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;
  final IconData              icon;
  final TextInputType         keyboardType;
  final int                   maxLines;

  const _SheetField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines     = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 14),
            child:   Icon(icon, color: Colors.white38, size: 18),
          ),
          Expanded(
            child: TextField(
              controller:   controller,
              keyboardType: keyboardType,
              maxLines:     maxLines,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText:       hint,
                hintStyle:      const TextStyle(color: Colors.white30),
                border:         InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final bool               useMinutes;
  final ValueChanged<bool> onToggle;

  const _TogglePill({required this.useMinutes, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        _Pill(
            label:    'Set time',
            selected: !useMinutes,
            onTap:    () => onToggle(false)),
        _Pill(
            label:    'In minutes',
            selected: useMinutes,
            onTap:    () => onToggle(true)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  const _Pill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:  const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0A84FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color:      selected ? Colors.white : Colors.white38,
                fontSize:   14,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  final DateTime?              selected;
  final ValueChanged<DateTime> onPick;

  const _DateTimePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context:     context,
          initialDate: selected ?? DateTime.now(),
          firstDate:
              DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context:     context,
          initialTime: TimeOfDay.fromDateTime(
              selected ?? DateTime.now()),
        );
        if (time == null) return;
        onPick(DateTime(
            date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          const Icon(CupertinoIcons.calendar,
              color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(
            selected == null
                ? 'Pick date & time'
                : DateFormat('EEE, MMM d · hh:mm a').format(selected!),
            style: TextStyle(
              color:    selected == null ? Colors.white30 : Colors.white,
              fontSize: 15,
            ),
          ),
        ]),
      ),
    );
  }
}

class _TopIconBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;

  const _TopIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child:   Icon(icon, color: Colors.black54, size: 22),
      ),
    );
  }
}