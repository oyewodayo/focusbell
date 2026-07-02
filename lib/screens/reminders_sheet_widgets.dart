part of 'reminders_screen.dart';

// Reusable sub-widgets used across Add / Edit / Detail bottom sheets.
// No imports — part of reminders_screen.dart which owns all imports.

// ════════════════════════════════════════════════════════════════
// _SectionLabel
// ════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

// ════════════════════════════════════════════════════════════════
// _RepeatPresets
// ════════════════════════════════════════════════════════════════

class _RepeatPresets extends StatelessWidget {
  final RepeatDays repeat;
  final ValueChanged<RepeatDays> onSelect;
  const _RepeatPresets({required this.repeat, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final presets = [
      ('Once', RepeatDays.once()),
      ('Daily', RepeatDays.daily()),
      ('Weekdays', RepeatDays.weekdays()),
      ('Weekends', RepeatDays.weekends()),
    ];
    return Wrap(
      spacing: 8,
      children: presets.map((item) {
        final (label, days) = item;
        final isSelected = repeat == days;
        return GestureDetector(
          onTap: () => onSelect(days),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 13,
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

// ════════════════════════════════════════════════════════════════
// _DayCheckboxGrid
// ════════════════════════════════════════════════════════════════

class _DayCheckboxGrid extends StatelessWidget {
  final RepeatDays repeat;
  final ValueChanged<RepeatDays> onChanged;
  const _DayCheckboxGrid(
      {required this.repeat, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: Weekday.ordered.map((day) {
        final isOn = repeat.contains(day);
        return GestureDetector(
          onTap: () => onChanged(repeat.toggle(day)),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isOn
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFF1C1C1E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOn
                      ? const Color(0xFF0A84FF)
                      : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isOn
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16)
                    : Text(
                        Weekday.shortName(day).substring(0, 1),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              Weekday.shortName(day),
              style: TextStyle(
                color: isOn
                    ? const Color(0xFF0A84FF)
                    : Colors.white38,
                fontSize: 9,
                fontWeight:
                    isOn ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _PrioritySelector
// ════════════════════════════════════════════════════════════════

class _PrioritySelector extends StatelessWidget {
  final ReminderPriority selected;
  final ValueChanged<ReminderPriority> onSelect;
  const _PrioritySelector(
      {required this.selected, required this.onSelect});

  static const _items = [
    (ReminderPriority.low, '↓ Low', Color(0xFF30D158)),
    (ReminderPriority.normal, '→ Normal', Color(0xFF0A84FF)),
    (ReminderPriority.high, '↑ High', Color(0xFFFF453A)),
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
              duration: const Duration(milliseconds: 150),
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
                    color: isSelected ? color : Colors.white38,
                    fontSize: 13,
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

// ════════════════════════════════════════════════════════════════
// _TimeOnlyPicker — for repeating reminders
// ════════════════════════════════════════════════════════════════

class _TimeOnlyPicker extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  const _TimeOnlyPicker(
      {required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: selected != null
              ? TimeOfDay.fromDateTime(selected!)
              : TimeOfDay.now(),
        );
        if (time == null || !context.mounted) return;
        final now = DateTime.now();
        onPick(DateTime(
            now.year, now.month, now.day, time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          const Icon(CupertinoIcons.clock,
              color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(
            selected == null
                ? 'Pick time'
                : DateFormat('hh:mm a').format(selected!),
            style: TextStyle(
              color:
                  selected == null ? Colors.white24 : Colors.white,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          if (selected != null)
            const Text(
              'repeats on selected days',
              style:
                  TextStyle(color: Colors.white24, fontSize: 11),
            ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _MultiDateTimePicker — Once reminders; supports extra dates
// ════════════════════════════════════════════════════════════════

class _MultiDateTimePicker extends StatelessWidget {
  final DateTime? selected;
  final List<DateTime> extraDates;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<List<DateTime>> onExtraDatesChanged;

  const _MultiDateTimePicker({
    required this.selected,
    required this.extraDates,
    required this.onPick,
    required this.onExtraDatesChanged,
  });

  Future<void> _pickPrimary(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: selected ?? DateTime.now(),
      firstDate:
          DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: selected != null
          ? TimeOfDay.fromDateTime(selected!)
          : TimeOfDay.now(),
    );
    if (time == null) return;
    onPick(DateTime(
        date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _addExtraDate(BuildContext context) async {
    final time = selected != null
        ? TimeOfDay.fromDateTime(selected!)
        : TimeOfDay.now();

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final dt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    final alreadyPrimary = selected != null &&
        date.year == selected!.year &&
        date.month == selected!.month &&
        date.day == selected!.day;
    final alreadyExtra = extraDates.any((d) =>
        d.year == date.year &&
        d.month == date.month &&
        d.day == date.day);
    if (alreadyPrimary || alreadyExtra) return;

    onExtraDatesChanged([...extraDates, dt]);
  }

  void _removeExtra(int index) {
    final updated = List<DateTime>.from(extraDates)
      ..removeAt(index);
    onExtraDatesChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickPrimary(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              const Icon(CupertinoIcons.calendar,
                  color: Colors.white38, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selected == null
                      ? 'Pick date & time'
                      : DateFormat('EEE, MMM d · hh:mm a')
                          .format(selected!),
                  style: TextStyle(
                    color: selected == null
                        ? Colors.white24
                        : Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected != null)
                GestureDetector(
                  onTap: () => _addExtraDate(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF0A84FF)
                              .withOpacity(0.3)),
                    ),
                    child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.plus,
                              color: Color(0xFF0A84FF), size: 11),
                          SizedBox(width: 4),
                          Text('Add date',
                              style: TextStyle(
                                color: Color(0xFF0A84FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              )),
                        ]),
                  ),
                ),
            ]),
          ),
        ),
        if (extraDates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(extraDates.length, (i) {
              return Container(
                padding:
                    const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A84FF).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF0A84FF)
                          .withOpacity(0.3)),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('MMM d').format(extraDates[i]),
                        style: const TextStyle(
                          color: Color(0xFF0A84FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removeExtra(i),
                        child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Color(0xFF0A84FF),
                            size: 14),
                      ),
                    ]),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '${extraDates.length + 1} reminder${extraDates.length + 1 == 1 ? '' : 's'} will be created',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _DateTimePicker — used only in Edit sheet (no multi-date)
// ════════════════════════════════════════════════════════════════

class _DateTimePicker extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  const _DateTimePicker(
      {required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now(),
          firstDate:
              DateTime.now().subtract(const Duration(days: 1)),
          lastDate:
              DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(
              selected ?? DateTime.now()),
        );
        if (time == null) return;
        onPick(DateTime(date.year, date.month, date.day,
            time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          const Icon(CupertinoIcons.calendar,
              color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(
            selected == null
                ? 'Pick date & time'
                : DateFormat('EEE, MMM d · hh:mm a')
                    .format(selected!),
            style: TextStyle(
              color:
                  selected == null ? Colors.white24 : Colors.white,
              fontSize: 15,
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _GroupPicker — horizontal pill row in Add/Edit sheets
// ════════════════════════════════════════════════════════════════

class _GroupPicker extends StatelessWidget {
  final String? selectedGroupId;
  final ValueChanged<String?> onSelect;

  const _GroupPicker({
    required this.selectedGroupId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ReminderGroup>>(
      valueListenable: ReminderGroupService.instance.groups,
      builder: (_, groups, __) {
        if (groups.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('GROUP'),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _GroupPill(
                    label: 'None',
                    emoji: '—',
                    color: Colors.white24,
                    isSelected: selectedGroupId == null,
                    onTap: () => onSelect(null),
                  ),
                  const SizedBox(width: 8),
                  ...groups.map((g) => Padding(
                        padding:
                            const EdgeInsets.only(right: 8),
                        child: _GroupPill(
                          label: g.name,
                          emoji: g.emoji,
                          color: g.color,
                          isSelected: selectedGroupId == g.id,
                          onTap: () => onSelect(g.id),
                        ),
                      )),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupPill extends StatelessWidget {
  final String label;
  final String emoji;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _GroupPill({
    required this.label,
    required this.emoji,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.18)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (emoji != '—') ...[
            Text(emoji,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: isSelected ? color : Colors.white54,
              fontSize: 12,
              fontWeight: isSelected
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _LocationToggle — tappable row in Add/Edit sheets
// ════════════════════════════════════════════════════════════════

class _LocationToggle extends StatelessWidget {
  final ReminderGeofence? geofence;
  final VoidCallback onTap;
  const _LocationToggle(
      {required this.geofence, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasGeo = geofence != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: hasGeo
              ? const Color(0xFF30D158).withOpacity(0.10)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGeo
                ? const Color(0xFF30D158).withOpacity(0.4)
                : Colors.white10,
          ),
        ),
        child: Row(children: [
          Icon(
            hasGeo
                ? CupertinoIcons.location_fill
                : CupertinoIcons.location,
            color: hasGeo
                ? const Color(0xFF30D158)
                : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasGeo
                      ? 'Location reminder set'
                      : 'Add location trigger',
                  style: TextStyle(
                    color: hasGeo
                        ? const Color(0xFF30D158)
                        : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  hasGeo
                      ? geofence!.fullLabel
                      : 'Fire when you arrive or leave a place',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            hasGeo
                ? CupertinoIcons.xmark_circle
                : CupertinoIcons.chevron_right,
            color: Colors.white24,
            size: 16,
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _DetailChip — used in the detail bottom sheet
// ════════════════════════════════════════════════════════════════

class _DetailChip extends StatelessWidget {
  final String label;
  final Color color;
  const _DetailChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _TopIconBtn
// ════════════════════════════════════════════════════════════════

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white38, size: 22),
      ),
    );
  }
}

// _PageDot → moved to reminders_clock_calendar.dart (only used there)
// _CountdownLabel → moved to reminders_tiles.dart (only used there)