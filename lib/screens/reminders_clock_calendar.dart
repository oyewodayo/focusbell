part of 'reminders_screen.dart';

// Analog clock + calendar panel, dot animations, places panel.
// No imports — part of reminders_screen.dart which owns all imports.

// ════════════════════════════════════════════════════════════════
// _AnalogClock  (sweep-in + timezone resync animations)
// ════════════════════════════════════════════════════════════════

class _AnalogClock extends StatefulWidget {
  final DateTime now;
  final bool sweepIn;
  final bool resync;
  final VoidCallback? onSweepDone;

  const _AnalogClock({
    required this.now,
    this.sweepIn = false,
    this.resync = false,
    this.onSweepDone,
  });

  @override
  State<_AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<_AnalogClock>
    with TickerProviderStateMixin {
  late AnimationController _sweepCtrl;
  late Animation<double> _sweepAnim;
  late AnimationController _resyncCtrl;
  late Animation<double> _resyncAnim;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900));
    _sweepAnim = CurvedAnimation(
        parent: _sweepCtrl, curve: Curves.easeOutCubic);

    _resyncCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800));
    _resyncAnim = CurvedAnimation(
        parent: _resyncCtrl, curve: Curves.easeInOutCubic);

    if (widget.sweepIn) {
      _sweepCtrl
          .forward()
          .then((_) => widget.onSweepDone?.call());
    } else {
      _sweepCtrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AnalogClock old) {
    super.didUpdateWidget(old);
    if (widget.resync && !old.resync) {
      _resyncCtrl
          .forward(from: 0)
          .then((_) => widget.onSweepDone?.call());
    }
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _resyncCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge([_sweepAnim, _resyncAnim]),
      builder: (_, __) => CustomPaint(
        painter: _ClockPainter(
          now: widget.now,
          sweepT: _sweepAnim.value,
          resyncT: _resyncAnim.value,
          resyncDone: !_resyncCtrl.isAnimating,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _ClockPainter
// ════════════════════════════════════════════════════════════════

class _ClockPainter extends CustomPainter {
  final DateTime now;
  final double sweepT;
  final double resyncT;
  final bool resyncDone;

  const _ClockPainter({
    required this.now,
    required this.sweepT,
    required this.resyncT,
    required this.resyncDone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy);

    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = const Color(0xFF2C2C2C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi - math.pi / 2;
      final isMain = i % 3 == 0;
      final len = isMain ? r * 0.12 : r * 0.06;
      canvas.drawLine(
        Offset(cx + (r - 10) * math.cos(angle),
            cy + (r - 10) * math.sin(angle)),
        Offset(cx + (r - 10 - len) * math.cos(angle),
            cy + (r - 10 - len) * math.sin(angle)),
        Paint()
          ..color = isMain ? Colors.white54 : Colors.white24
          ..strokeWidth = isMain ? 2.0 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    final tHour =
        ((now.hour % 12 + now.minute / 60) / 12) *
                2 *
                math.pi -
            math.pi / 2;
    final tMin =
        ((now.minute + now.second / 60) / 60) * 2 * math.pi -
            math.pi / 2;
    final tSec =
        (now.second / 60) * 2 * math.pi - math.pi / 2;
    const start = -math.pi / 2;

    final hourAngle = _lerp(start, tHour, sweepT);
    final minAngle = _lerp(start, tMin, sweepT);
    double secAngle = _lerp(start, tSec, sweepT);
    if (!resyncDone) secAngle = tSec + resyncT * 2 * math.pi;

    _hand(canvas, cx, cy,
        angle: hourAngle,
        length: r * 0.50,
        width: 5.0,
        color: Colors.white);
    _hand(canvas, cx, cy,
        angle: minAngle,
        length: r * 0.68,
        width: 3.5,
        color: Colors.white70);
    _hand(canvas, cx, cy,
        angle: secAngle,
        length: r * 0.74,
        width: 1.8,
        color: const Color(0xFF0A84FF),
        tail: r * 0.18);

    canvas.drawCircle(Offset(cx, cy), 5.5,
        Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), 3.0,
        Paint()..color = const Color(0xFF0A84FF));
  }

  void _hand(Canvas canvas, double cx, double cy, {
    required double angle,
    required double length,
    required double width,
    required Color color,
    double tail = 0,
  }) {
    canvas.drawLine(
      Offset(cx - tail * math.cos(angle),
          cy - tail * math.sin(angle)),
      Offset(cx + length * math.cos(angle),
          cy + length * math.sin(angle)),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.now != now ||
      old.sweepT != sweepT ||
      old.resyncT != resyncT ||
      old.resyncDone != resyncDone;
}

// ════════════════════════════════════════════════════════════════
// _ClockCalendarPanel  (AnimatedCrossFade — no fixed heights)
// ════════════════════════════════════════════════════════════════

class _ClockCalendarPanel extends StatefulWidget {
  final DateTime now;
  final String timezoneLabel;
  final VoidCallback onTimezoneTap;
  final List<Reminder> reminders;
  final void Function(DateTime) onDateTap;
  final String? lastAddedReminderId;
  final VoidCallback onDotBloomDone;

  const _ClockCalendarPanel({
    required this.now,
    required this.timezoneLabel,
    required this.onTimezoneTap,
    required this.reminders,
    required this.onDateTap,
    required this.lastAddedReminderId,
    required this.onDotBloomDone,
  });

  @override
  State<_ClockCalendarPanel> createState() =>
      _ClockCalendarPanelState();
}

class _ClockCalendarPanelState extends State<_ClockCalendarPanel>
    with TickerProviderStateMixin {
  int _page = 0;
  DateTime _calMonth = DateTime.now();
  DateTime? _selectedDay;
  int _monthSlideDir = 1;

  bool _clockSweptIn = false;
  bool _triggerResync = false;
  String? _prevTzLabel;

  final Map<String, AnimationController> _bloomCtrls = {};

  @override
  void initState() {
    super.initState();
    _prevTzLabel = widget.timezoneLabel;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _clockSweptIn = true);
    });
  }

  @override
  void didUpdateWidget(_ClockCalendarPanel old) {
    super.didUpdateWidget(old);

    if (widget.timezoneLabel != _prevTzLabel) {
      setState(() {
        _triggerResync = true;
        _prevTzLabel = widget.timezoneLabel;
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _triggerResync = false);
      });
    }

    if (widget.lastAddedReminderId != null &&
        !_bloomCtrls.containsKey(widget.lastAddedReminderId)) {
      // Capture ID now — widget.lastAddedReminderId will be null
      // after onDotBloomDone() clears it via setState.
      final capturedId = widget.lastAddedReminderId!;
      final ctrl = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600));
      _bloomCtrls[capturedId] = ctrl;
      ctrl.forward().then((_) {
        widget.onDotBloomDone();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ctrl.dispose();
            _bloomCtrls.remove(capturedId);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in _bloomCtrls.values) c.dispose();
    super.dispose();
  }

  void _prevMonth() => setState(() {
        _monthSlideDir = -1;
        _calMonth =
            DateTime(_calMonth.year, _calMonth.month - 1);
      });

  void _nextMonth() => setState(() {
        _monthSlideDir = 1;
        _calMonth =
            DateTime(_calMonth.year, _calMonth.month + 1);
      });

  bool _hasReminder(DateTime day) => widget.reminders.any((r) =>
      r.dateTime.year == day.year &&
      r.dateTime.month == day.month &&
      r.dateTime.day == day.day);

  List<Color> _dotsForDay(DateTime day) {
    final rs = widget.reminders
        .where((r) =>
            r.dateTime.year == day.year &&
            r.dateTime.month == day.month &&
            r.dateTime.day == day.day)
        .toList();
    if (rs.isEmpty) return [];
    final colors = <Color>{};
    for (final r in rs) {
      final g =
          ReminderGroupService.instance.findById(r.groupId);
      colors.add(g?.color ?? const Color(0xFF0A84FF));
      if (colors.length >= 3) break;
    }
    return colors.toList();
  }

  Reminder? _lastAddedOnDay(DateTime day) {
    if (widget.lastAddedReminderId == null) return null;
    try {
      return widget.reminders.firstWhere((r) =>
          r.id == widget.lastAddedReminderId &&
          r.dateTime.year == day.year &&
          r.dateTime.month == day.month &&
          r.dateTime.day == day.day);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 320),
        sizeCurve: Curves.easeOutCubic,
        firstCurve: Curves.easeOutCubic,
        secondCurve: Curves.easeOutCubic,
        crossFadeState: _page == 0
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        firstChild: GestureDetector(
          onHorizontalDragEnd: (d) {
            if (d.primaryVelocity != null &&
                d.primaryVelocity! < -300) {
              setState(() => _page = 1);
            }
          },
          child: _buildClockPage(),
        ),
        secondChild: GestureDetector(
          onHorizontalDragEnd: (d) {
            if (d.primaryVelocity == null) return;
            if (d.primaryVelocity! > 600) {
              setState(() => _page = 0);
            } else if (d.primaryVelocity! > 300) {
              _prevMonth();
            } else if (d.primaryVelocity! < -300) {
              _nextMonth();
            }
          },
          child: _buildCalendarPage(),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => setState(() => _page = 0),
          child: _PageDot(active: _page == 0),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _page = 1),
          child: _PageDot(active: _page == 1),
        ),
      ]),
      AnimatedOpacity(
        opacity: _page == 1 ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              if (d.primaryVelocity != null &&
                  d.primaryVelocity!.abs() > 200) {
                setState(() => _page = 0);
              }
            },
            child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.arrow_left,
                      color: Colors.white12, size: 10),
                  SizedBox(width: 4),
                  Text('swipe to clock',
                      style: TextStyle(
                          color: Colors.white12,
                          fontSize: 10)),
                  SizedBox(width: 4),
                  Icon(CupertinoIcons.arrow_right,
                      color: Colors.white12, size: 10),
                ]),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }

  // ── Clock page ──────────────────────────────────────────────

  Widget _buildClockPage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        AnimatedScale(
          scale: _clockSweptIn ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          child: Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: _AnalogClock(
                now: widget.now,
                sweepIn: true,
                resync: _triggerResync,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedOpacity(
          opacity: _clockSweptIn ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration:
                      const Duration(milliseconds: 400),
                  child: Text(
                    DateFormat('hh:mm:ss a').format(widget.now),
                    key: ValueKey(widget.timezoneLabel),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w200,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEE, MMM d').format(widget.now),
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 15),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: widget.onTimezoneTap,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(
                              milliseconds: 300),
                          child: Text(
                            widget.timezoneLabel.isEmpty
                                ? ' '
                                : widget.timezoneLabel,
                            key: ValueKey(
                                widget.timezoneLabel),
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                            CupertinoIcons.chevron_down,
                            color: Colors.white24,
                            size: 11),
                      ]),
                ),
                const SizedBox(height: 16),
              ]),
        ),
      ],
    );
  }

  // ── Calendar page ───────────────────────────────────────────

  Widget _buildCalendarPage() {
    final firstDay =
        DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMon =
        DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final startWd = (firstDay.weekday - 1) % 7;
    final today = DateTime.now();

    final List<DateTime?> cells = [
      ...List.filled(startWd, null),
      ...List.generate(
          daysInMon,
          (i) => DateTime(
              _calMonth.year, _calMonth.month, i + 1)),
    ];
    while (cells.length % 7 != 0) cells.add(null);

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Month navigation
            SizedBox(
              height: 44,
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _prevMonth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.06),
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: const Icon(
                            CupertinoIcons.chevron_left,
                            color: Colors.white70,
                            size: 16),
                      ),
                    ),
                  ),
                ),
                Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(
                            milliseconds: 280),
                        transitionBuilder: (child, anim) {
                          final slide = Tween<Offset>(
                            begin: Offset(
                                _monthSlideDir * 0.3, 0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                              parent: anim,
                              curve:
                                  Curves.easeOutCubic));
                          return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                  position: slide,
                                  child: child));
                        },
                        child: Text(
                          DateFormat('MMMM yyyy')
                              .format(_calMonth),
                          key: ValueKey(_calMonth),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('hh:mm a')
                            .format(widget.now),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ]),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _nextMonth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.06),
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: const Icon(
                            CupertinoIcons.chevron_right,
                            color: Colors.white70,
                            size: 16),
                      ),
                    ),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 4),
            // Day-of-week headers
            Row(
              children: [
                'Mo',
                'Tu',
                'We',
                'Th',
                'Fr',
                'Sa',
                'Su'
              ]
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),

            // Calendar grid rows
            ...List.generate(cells.length ~/ 7, (row) {
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: List.generate(7, (col) {
                    final day = cells[row * 7 + col];
                    if (day == null) {
                      return const Expanded(
                          child: SizedBox());
                    }

                    final isToday = day.year == today.year &&
                        day.month == today.month &&
                        day.day == today.day;
                    final isSelected = _selectedDay !=
                            null &&
                        day.year == _selectedDay!.year &&
                        day.month == _selectedDay!.month &&
                        day.day == _selectedDay!.day;
                    final hasRem = _hasReminder(day);
                    final isPast = day.isBefore(DateTime(
                        today.year,
                        today.month,
                        today.day));
                    final bloomCtrl = _bloomCtrls[
                        widget.lastAddedReminderId];
                    final isBloomDay =
                        _lastAddedOnDay(day) != null &&
                            bloomCtrl != null;
                    final staggerMs =
                        (row * 7 + col) * 18;
                    final dotColors = _dotsForDay(day);

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(
                              () => _selectedDay = day);
                          widget.onDateTap(day);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(
                              milliseconds: 180),
                          margin: const EdgeInsets
                              .symmetric(
                              horizontal: 2,
                              vertical: 1),
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0A84FF)
                                : isToday
                                    ? const Color(
                                            0xFF0A84FF)
                                        .withOpacity(0.15)
                                    : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(10),
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: const Color(
                                            0xFF0A84FF)
                                        .withOpacity(0.5),
                                    width: 1)
                                : null,
                          ),
                          child: Stack(
                              alignment:
                                  Alignment.center,
                              children: [
                                Text('${day.day}',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : isPast
                                              ? Colors
                                                  .white24
                                              : isToday
                                                  ? const Color(
                                                      0xFF0A84FF)
                                                  : Colors
                                                      .white70,
                                      fontSize: 15,
                                      fontWeight: isToday ||
                                              isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    )),
                                if (hasRem)
                                  Positioned(
                                    bottom: 3,
                                    child: isBloomDay
                                        ? _BloomDot(
                                            controller:
                                                bloomCtrl!,
                                            isSelected:
                                                isSelected,
                                            color: dotColors
                                                    .isNotEmpty
                                                ? dotColors
                                                    .first
                                                : const Color(
                                                    0xFF0A84FF),
                                          )
                                        : _MultiDot(
                                            colors:
                                                dotColors,
                                            isSelected:
                                                isSelected,
                                            delay: Duration(
                                                milliseconds:
                                                    staggerMs),
                                          ),
                                  ),
                              ]),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _MultiDot — up to 3 colour-coded group dots
// ════════════════════════════════════════════════════════════════

class _MultiDot extends StatefulWidget {
  final List<Color> colors;
  final bool isSelected;
  final Duration delay;

  const _MultiDot({
    required this.colors,
    required this.isSelected,
    required this.delay,
  });

  @override
  State<_MultiDot> createState() => _MultiDotState();
}

class _MultiDotState extends State<_MultiDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350));
    _scale =
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(
        widget.delay, () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.colors.isEmpty) return const SizedBox.shrink();
    return ScaleTransition(
      scale: _scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: widget.colors.asMap().entries.map((e) {
          final idx = e.key;
          final color =
              widget.isSelected ? Colors.white70 : e.value;
          return Padding(
            padding:
                EdgeInsets.only(left: idx == 0 ? 0 : 2),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: widget.isSelected
                    ? null
                    : [
                        BoxShadow(
                          color: color.withOpacity(0.5),
                          blurRadius: 3,
                        ),
                      ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _StaggerDot — kept for legacy callers
// ════════════════════════════════════════════════════════════════

class _StaggerDot extends StatefulWidget {
  final Duration delay;
  final bool isSelected;
  const _StaggerDot(
      {required this.delay, required this.isSelected});

  @override
  State<_StaggerDot> createState() => _StaggerDotState();
}

class _StaggerDotState extends State<_StaggerDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350));
    _scale =
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(
        widget.delay, () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isSelected
              ? Colors.white70
              : const Color(0xFF0A84FF),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _BloomDot — animated dot when a reminder is added
// ════════════════════════════════════════════════════════════════

class _BloomDot extends StatelessWidget {
  final AnimationController controller;
  final bool isSelected;
  final Color color;

  const _BloomDot({
    required this.controller,
    required this.isSelected,
    this.color = const Color(0xFF0A84FF),
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isSelected ? Colors.white : color;
    final scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: controller,
          curve: const Interval(0.0, 0.5,
              curve: Curves.elasticOut)),
    );
    final glowOpacity =
        Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: controller,
          curve: const Interval(0.4, 1.0,
              curve: Curves.easeOut)),
    );
    final glowSize =
        Tween<double>(begin: 4.0, end: 20.0).animate(
      CurvedAnimation(
          parent: controller,
          curve: const Interval(0.4, 1.0,
              curve: Curves.easeOut)),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) =>
          Stack(alignment: Alignment.center, children: [
        Opacity(
          opacity: glowOpacity.value,
          child: Container(
            width: glowSize.value,
            height: glowSize.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.3),
            ),
          ),
        ),
        ScaleTransition(
          scale: scale,
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _PlacesAwarenessPanel
// ════════════════════════════════════════════════════════════════

class _PlacesAwarenessPanel extends StatefulWidget {
  final VoidCallback onManagePlaces;
  const _PlacesAwarenessPanel(
      {required this.onManagePlaces});

  @override
  State<_PlacesAwarenessPanel> createState() =>
      _PlacesAwarenessPanelState();
}

class _PlacesAwarenessPanelState
    extends State<_PlacesAwarenessPanel> {
  @override
  void initState() {
    super.initState();
    SavedPlacesService.instance.places
        .addListener(_rebuild);
  }

  @override
  void dispose() {
    SavedPlacesService.instance.places
        .removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _confirmDeletePlace(
      BuildContext context, SavedPlace place) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text('Remove ${place.name}?'),
        message: const Text(
            'This will stop watching this place for arrivals and departures.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              await SavedPlacesService.instance
                  .remove(place.id);
            },
            child: const Text('Remove Place'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watched =
        SavedPlacesService.instance.watchedPlaces;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Places',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                )),
            const SizedBox(width: 6),
            if (watched.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                    '${watched.length} watching',
                    style: const TextStyle(
                      color: Color(0xFF30D158),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            const Spacer(),
            GestureDetector(
              onTap: widget.onManagePlaces,
              child: const Text('Manage',
                  style: TextStyle(
                    color: Color(0xFF0A84FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  )),
            ),
          ]),
          const SizedBox(height: 10),

          if (watched.isEmpty)
            GestureDetector(
              onTap: widget.onManagePlaces,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius:
                      BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white
                          .withOpacity(0.06)),
                ),
                child: Row(children: [
                  const Icon(
                      CupertinoIcons.location_slash,
                      color: Colors.white24,
                      size: 18),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('No places watched',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 14)),
                  ),
                  const Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.white12,
                      size: 14),
                ]),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(watched.length,
                    (i) {
                  final place = watched[i];
                  final inside = GeofenceService.instance
                      .isInsidePlace(place.id);
                  return Padding(
                    padding: EdgeInsets.only(
                        right:
                            i < watched.length - 1 ? 10 : 0),
                    child: GestureDetector(
                      onTap: widget.onManagePlaces,
                      onLongPress: () =>
                          _confirmDeletePlace(
                              context, place),
                      child: AnimatedContainer(
                        duration: const Duration(
                            milliseconds: 300),
                        width: 96,
                        padding: const EdgeInsets
                            .fromLTRB(8, 12, 8, 10),
                        decoration: BoxDecoration(
                          color: inside
                              ? const Color(0xFF30D158)
                                  .withOpacity(0.12)
                              : const Color(0xFF141414),
                          borderRadius:
                              BorderRadius.circular(16),
                          border: Border.all(
                            color: inside
                                ? const Color(0xFF30D158)
                                    .withOpacity(0.4)
                                : Colors.white
                                    .withOpacity(0.06),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(place.emoji,
                                style: const TextStyle(
                                    fontSize: 24)),
                            const SizedBox(height: 5),
                            Text(
                              place.name,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                color: inside
                                    ? const Color(
                                        0xFF30D158)
                                    : Colors.white54,
                                fontSize: 11,
                                fontWeight: inside
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 5),
                            AnimatedContainer(
                              duration: const Duration(
                                  milliseconds: 300),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: inside
                                    ? const Color(
                                        0xFF30D158)
                                    : Colors.white12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _PageDot indicator — used by _ClockCalendarPanelState
// ════════════════════════════════════════════════════════════════

class _PageDot extends StatelessWidget {
  final bool active;
  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF0A84FF)
            : Colors.white12,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}