part of 'reminders_screen.dart';

// Reminder tile (swipe gestures), grouped list, empty state.
// No imports — part of reminders_screen.dart which owns all imports.

// ════════════════════════════════════════════════════════════════
// _ReminderTile — swipe RIGHT = edit  |  swipe LEFT = delete
// ════════════════════════════════════════════════════════════════

class _ReminderTile extends StatefulWidget {
  final Reminder reminder;
  final DateTime now;
  final Color? groupColor;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onViewDetail;
  final VoidCallback onMoveGroup;

  const _ReminderTile({
    super.key,
    required this.reminder,
    required this.now,
    this.groupColor,
    required this.onDelete,
    required this.onEdit,
    required this.onViewDetail,
    required this.onMoveGroup,
  });

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile>
    with SingleTickerProviderStateMixin {
  static const double _kActionW = 72.0;
  static const double _kThresh = 44.0;
  static const double _kMax = _kActionW + 12.0;

  double _offset = 0.0;
  bool _editOpen = false;
  bool _deleteOpen = false;

  late AnimationController _snapCtrl;
  double _snapFrom = 0.0;
  double _snapTarget = 0.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        setState(() =>
            _offset = _lerp(_snapFrom, _snapTarget, _snapCtrl.value));
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _snapFrom = _offset;
    _snapTarget = target;
    _snapCtrl.forward(from: 0);
  }

  void _closeActions() {
    _animateTo(0);
    _editOpen = false;
    _deleteOpen = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_editOpen || _deleteOpen) {
      if ((_editOpen && d.delta.dx < -6) ||
          (_deleteOpen && d.delta.dx > 6)) {
        _closeActions();
      }
      return;
    }
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_kMax, _kMax);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_editOpen || _deleteOpen) return;
    if (_offset > _kThresh) {
      _animateTo(_kActionW);
      setState(() {
        _editOpen = true;
        _deleteOpen = false;
      });
    } else if (_offset < -_kThresh) {
      _animateTo(-_kActionW);
      setState(() {
        _deleteOpen = true;
        _editOpen = false;
      });
    } else {
      _animateTo(0);
    }
  }

  Color get _priorityColor {
    switch (widget.reminder.priority) {
      case ReminderPriority.high:
        return const Color(0xFFFF453A);
      case ReminderPriority.normal:
        return const Color(0xFF0A84FF);
      case ReminderPriority.low:
        return const Color(0xFF30D158);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    final diff = widget.reminder.dateTime.difference(widget.now);
    final isPast = diff.isNegative;
    final hrs = diff.inHours.abs();
    final mins = diff.inMinutes.abs();
    final shouldPulse = !isPast && diff.inMinutes < 10;
    final countdown = isPast
        ? 'Passed'
        : hrs < 1
            ? 'In $mins min${mins == 1 ? '' : 's'}'
            : hrs < 24
                ? 'In $hrs hr${hrs == 1 ? '' : 's'}'
                : 'In ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    final timeStr =
        DateFormat('hh:mm a').format(widget.reminder.dateTime);
    final dateStr =
        DateFormat('EEE, MMM d').format(widget.reminder.dateTime);

    final editRatio = (_offset / _kActionW).clamp(0.0, 1.0);
    final deleteRatio = (-_offset / _kActionW).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onTap:
          (_editOpen || _deleteOpen) ? _closeActions : null,
      child: ClipRect(
        child: Stack(children: [
          // ── Edit button (swipe right) ─────────────────────
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Opacity(
                opacity: editRatio.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.7 + 0.3 * editRatio,
                  child: GestureDetector(
                    onTap: () {
                      _closeActions();
                      widget.onEdit();
                    },
                    child: Container(
                      width: _kActionW,
                      margin: const EdgeInsets.symmetric(
                          vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A84FF),
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.pencil,
                              color: Colors.white,
                              size: 18),
                          SizedBox(height: 4),
                          Text('Edit',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Delete button (swipe left) ────────────────────
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: deleteRatio.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.7 + 0.3 * deleteRatio,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      width: _kActionW,
                      margin: const EdgeInsets.symmetric(
                          vertical: 6),
                      decoration: BoxDecoration(
                        color: fb.danger,
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                              size: 20),
                          SizedBox(height: 4),
                          Text('Delete',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              onLongPress: widget.onMoveGroup,
              child: Container(
                color: fb.scaffoldBg,
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.center,
                  children: [
                    // Group colour stripe
                    if (widget.groupColor != null)
                      Container(
                        width: 3,
                        height: 46,
                        margin: const EdgeInsets.only(
                            right: 10),
                        decoration: BoxDecoration(
                          color: widget.groupColor!,
                          borderRadius:
                              BorderRadius.circular(2),
                        ),
                      ),
                    // Bell icon
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isPast
                            ? fb.surfaceVar
                            : _priorityColor.withValues(
                                alpha: fb.isDark ? 0.14 : 0.20),
                        borderRadius:
                            BorderRadius.circular(13),
                      ),
                      child: Icon(
                          CupertinoIcons.bell_fill,
                          color: isPast
                              ? fb.onSurface
                                  .withValues(alpha: fb.isDark ? 0.12 : 0.32)
                              : _priorityColor,
                          size: 20),
                    ),
                    const SizedBox(width: 14),

                    // Title + metadata
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: (_editOpen || _deleteOpen)
                            ? _closeActions
                            : widget.onViewDetail,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.reminder.title,
                              maxLines: 2,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isPast
                                    ? fb.onSurfaceFaint
                                    : fb.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(children: [
                              Flexible(
                                child: Text(
                                  '$dateStr · $timeStr',
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: fb.onSurface.withValues(alpha: 0.38),
                                      fontSize: 12),
                                ),
                              ),
                              if (widget.reminder
                                  .isRepeating) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                      horizontal: 6,
                                      vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                            0xFF0A84FF)
                                        .withOpacity(0.15),
                                    borderRadius:
                                        BorderRadius.circular(
                                            6),
                                  ),
                                  child: Text(
                                    widget.reminder.repeat
                                        .shortLabel,
                                    style: const TextStyle(
                                      color:
                                          Color(0xFF0A84FF),
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ]),
                            if (widget.reminder
                                .isLocationBased) ...[
                              const SizedBox(height: 3),
                              Row(children: [
                                const Icon(
                                    CupertinoIcons
                                        .location_fill,
                                    color:
                                        Color(0xFF30D158),
                                    size: 11),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    widget.reminder
                                        .geofence!.fullLabel,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color:
                                          Color(0xFF30D158),
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ]),
                            ],
                            if (widget.reminder.notes !=
                                    null &&
                                widget.reminder.notes!
                                    .isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.reminder.notes!,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: fb.onSurfaceFaint,
                                    fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Time + countdown
                    SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment:
                                Alignment.centerRight,
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                color: isPast
                                    ? fb.onSurfaceFaint
                                    : fb.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w200,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          _CountdownLabel(
                            text: countdown,
                            color: isPast
                                ? fb.onSurfaceFaint
                                : _priorityColor,
                            pulse: shouldPulse,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _GroupedReminderList
// ════════════════════════════════════════════════════════════════

class _GroupedReminderList extends StatefulWidget {
  final List<Reminder> reminders;
  final DateTime now;
  final void Function(Reminder) onDelete;
  final void Function(Reminder) onEdit;
  final void Function(Reminder) onViewDetail;
  final void Function(Reminder) onMoveGroup;

  const _GroupedReminderList({
    required this.reminders,
    required this.now,
    required this.onDelete,
    required this.onEdit,
    required this.onViewDetail,
    required this.onMoveGroup,
  });

  @override
  State<_GroupedReminderList> createState() =>
      _GroupedReminderListState();
}

class _GroupedReminderListState
    extends State<_GroupedReminderList> {
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    ReminderGroupService.instance.groups
        .addListener(_rebuild);
  }

  @override
  void dispose() {
    ReminderGroupService.instance.groups
        .removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    final groups =
        ReminderGroupService.instance.groups.value;
    final all = widget.reminders;

    final sections =
        <(ReminderGroup?, List<Reminder>)>[];
    for (final g in groups) {
      final rs =
          all.where((r) => r.groupId == g.id).toList();
      if (rs.isNotEmpty) sections.add((g, rs));
    }
    final ungrouped =
        all.where((r) => r.groupId == null).toList();
    if (ungrouped.isNotEmpty)
      sections.add((null, ungrouped));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        final (group, reminders) = section;
        final sectionId =
            group?.id ?? '__ungrouped__';
        final isCollapsed =
            _collapsed.contains(sectionId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // Section header
              GestureDetector(
                onTap: () => setState(() {
                  if (isCollapsed)
                    _collapsed.remove(sectionId);
                  else
                    _collapsed.add(sectionId);
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      16, 4, 16, 8),
                  child: Row(children: [
                    if (group != null) ...[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: group.color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: group.color
                                  .withOpacity(0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(group.emoji,
                          style: const TextStyle(
                              fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(group.name,
                          style: TextStyle(
                            color: group.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          )),
                    ] else ...[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: fb.onSurfaceFaint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Ungrouped',
                          style: TextStyle(
                            color: fb.onSurface.withValues(alpha: 0.38),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (group?.color ??
                                fb.onSurfaceFaint)
                            .withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                      child: Text(
                          '${reminders.length}',
                          style: TextStyle(
                            color: group?.color ??
                                fb.onSurface.withValues(alpha: 0.38),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0,
                      duration: const Duration(
                          milliseconds: 200),
                      child: Icon(
                          CupertinoIcons.chevron_down,
                          color: fb.onSurfaceFaint,
                          size: 13),
                    ),
                  ]),
                ),
              ),

              // Reminder tiles
              AnimatedCrossFade(
                duration:
                    const Duration(milliseconds: 250),
                sizeCurve: Curves.easeOutCubic,
                firstCurve: Curves.easeOutCubic,
                secondCurve: Curves.easeInCubic,
                crossFadeState: isCollapsed
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16),
                  decoration: BoxDecoration(
                    color: fb.surface,
                    borderRadius:
                        BorderRadius.circular(18),
                    border: Border.all(
                      color: group != null
                          ? group.color.withOpacity(0.15)
                          : fb.onSurface.withValues(alpha: 0.05),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(18),
                    child: Column(
                      children: List.generate(
                          reminders.length, (i) {
                        final r = reminders[i];
                        final isLast =
                            i == reminders.length - 1;
                        return Column(children: [
                          _ReminderTile(
                            key: ValueKey(r.id),
                            reminder: r,
                            now: widget.now,
                            groupColor: group?.color,
                            onDelete: () =>
                                widget.onDelete(r),
                            onEdit: () =>
                                widget.onEdit(r),
                            onViewDetail: () =>
                                widget.onViewDetail(r),
                            onMoveGroup: () =>
                                widget.onMoveGroup(r),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 68,
                              color: fb.border,
                            ),
                        ]);
                      }),
                    ),
                  ),
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _EmptyReminders — time-aware contextual message
// ════════════════════════════════════════════════════════════════

class _EmptyReminders extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyReminders({required this.onAdd});

  static (String emoji, String headline, String sub)
      _contextFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 9)
      return ('🌅', 'Good morning!',
          'Start your day with a reminder.');
    if (h >= 9 && h < 12)
      return ('☀️', 'Morning\'s rolling.',
          'Nothing on your plate yet.');
    if (h >= 12 && h < 14)
      return ('🌤️', 'Midday check-in.',
          'All clear — enjoy your lunch.');
    if (h >= 14 && h < 17)
      return ('🧠', 'Deep work hours.',
          'No interruptions scheduled.');
    if (h >= 17 && h < 20)
      return ('🌇', 'Evening is yours.',
          'Add something to look forward to.');
    if (h >= 20 && h < 23)
      return ('🌙', 'Winding down.',
          'Nothing tonight. Rest well.');
    return ('🌌', 'Late night.',
        'Everything is quiet. You should sleep.');
  }

  @override
  Widget build(BuildContext context) {
    final fb = Theme.of(context).fb;
    final (emoji, headline, sub) =
        _contextFor(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 40, vertical: 32),
      child: Column(children: [
        Divider(color: fb.border),
        const SizedBox(height: 36),
        Text(emoji,
            style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(headline,
            style: TextStyle(
              color: fb.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            )),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fb.onSurface.withValues(alpha: 0.38),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF0A84FF)
                      .withOpacity(0.3)),
            ),
            child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.plus,
                      color: Color(0xFF0A84FF),
                      size: 15),
                  SizedBox(width: 8),
                  Text('Add a reminder',
                      style: TextStyle(
                        color: Color(0xFF0A84FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      )),
                ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _CountdownLabel — pulses when < 10 min away
// Used by _ReminderTile
// ════════════════════════════════════════════════════════════════

class _CountdownLabel extends StatefulWidget {
  final String text;
  final Color color;
  final bool pulse;
  const _CountdownLabel(
      {required this.text,
      required this.color,
      required this.pulse});

  @override
  State<_CountdownLabel> createState() =>
      _CountdownLabelState();
}

class _CountdownLabelState
    extends State<_CountdownLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.4)
        .animate(CurvedAnimation(
            parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Text(widget.text,
          style: TextStyle(
              color: widget.color, fontSize: 12));
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Text(
          widget.text,
          style: TextStyle(
            color: widget.color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}