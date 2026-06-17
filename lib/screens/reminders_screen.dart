// reminders_screen.dart — FULL REPLACEMENT

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../data/timezone_data.dart';
import '../models/reminder_model.dart';
import '../services/reminder_service.dart';

// ── lerp helper (avoid dart:ui conflict) ─────────────────────────
double _lerp(double a, double b, double t) => a + (b - a) * t;

// ════════════════════════════════════════════════════════════════
// RemindersScreen
// ════════════════════════════════════════════════════════════════

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _svc = ReminderService.instance;
  late Timer _ticker;
  DateTime _now = DateTime.now();

  String _deviceTz      = '';
  String _selectedTz    = '';
  String _selectedCity  = '';
  String _selectedCountry = '';
  bool   _useDeviceTz   = true;

  String? _lastAddedReminderId;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _currentTime);
    });
    tz_data.initializeTimeZones();
    _resolveDeviceTimezone();
  }

  Future<void> _resolveDeviceTimezone() async {
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      final match = kAllCities.firstWhere(
        (c) => c.tzName == tzName,
        orElse: () => TzCity(
          city: tzName.split('/').last.replaceAll('_', ' '),
          country: '',
          tzName: tzName,
        ),
      );
      if (mounted) {
        setState(() {
          _deviceTz       = tzName;
          _selectedTz     = tzName;
          _selectedCity   = match.city;
          _selectedCountry = match.country;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _selectedCity = 'Local Time');
    }
  }

  DateTime get _currentTime {
    if (_useDeviceTz || _selectedTz.isEmpty) return DateTime.now();
    try {
      final loc = tz.getLocation(_selectedTz);
      final t   = tz.TZDateTime.now(loc);
      return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    } catch (_) {
      return DateTime.now();
    }
  }

  String _gmtOffset(String tzName) {
    try {
      final loc    = tz.getLocation(tzName);
      final offset = tz.TZDateTime.now(loc).timeZoneOffset;
      final h      = offset.inHours;
      final m      = offset.inMinutes.abs() % 60;
      final sign   = h >= 0 ? '+' : '-';
      return 'GMT $sign${h.abs().toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String get _timezoneLabel {
    if (_selectedCity.isEmpty) return '';
    return _useDeviceTz ? '$_selectedCity (Local)' : _selectedCity;
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  // ── Timezone picker ───────────────────────────────────────────

  Future<void> _showTimezoneMenu() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TzPickerSheet(
        selectedTz:  _selectedTz,
        useDeviceTz: _useDeviceTz,
        deviceTz:    _deviceTz,
        gmtOffset:   _gmtOffset,
        onPick: (city) {
          setState(() {
            _selectedTz      = city.tzName;
            _selectedCity    = city.city;
            _selectedCountry = city.country;
            _useDeviceTz     = false;
            _now             = _currentTime;
          });
        },
        onUseDevice: () {
          setState(() {
            _useDeviceTz = true;
            _selectedTz  = _deviceTz;
            final match = kAllCities.firstWhere(
              (c) => c.tzName == _deviceTz,
              orElse: () => TzCity(
                city: _deviceTz.split('/').last.replaceAll('_', ' '),
                country: '',
                tzName: _deviceTz,
              ),
            );
            _selectedCity    = match.city;
            _selectedCountry = match.country;
          });
        },
      ),
    );
  }

  // ── Options menu ──────────────────────────────────────────────

  void _showOptionsMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              _showTimezoneMenu();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.globe, size: 18, color: Color(0xFF0A84FF)),
                SizedBox(width: 10),
                Text('Change Clock City',
                    style: TextStyle(color: Color(0xFF0A84FF), fontSize: 16)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Shared bottom-sheet container ─────────────────────────────

  Widget _sheetWrap({required Widget child}) {
    return Container(
      margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(child: child),
    );
  }

  Widget _sheetHandle() => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: Colors.white24, borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _sheetSaveBtn(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A84FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
          )),
        ),
      ),
    ),
  );

  // ── Add reminder ──────────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final titleCtrl   = TextEditingController();
    final minutesCtrl = TextEditingController();
    final notesCtrl   = TextEditingController();
    DateTime?        picked;
    bool             useMinutes = false;
    RepeatDays       repeat     = RepeatDays.once();
    ReminderPriority priority   = ReminderPriority.normal;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                const Text('New Reminder', style: TextStyle(
                  color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w700, letterSpacing: -0.4,
                )),
                const SizedBox(height: 18),
                _SheetField(controller: titleCtrl, hint: 'Reminder title', icon: CupertinoIcons.bell),
                const SizedBox(height: 12),
                _TogglePill(useMinutes: useMinutes, onToggle: (v) => ss(() => useMinutes = v)),
                const SizedBox(height: 12),
                if (useMinutes)
                  _SheetField(
                    controller: minutesCtrl,
                    hint: 'In how many minutes?',
                    icon: CupertinoIcons.timer,
                    keyboardType: TextInputType.number,
                  )
                else
                  _DateTimePicker(selected: picked, onPick: (dt) => ss(() => picked = dt)),
                const SizedBox(height: 16),
                _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(repeat: repeat, onSelect: (r) => ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(repeat: repeat, onChanged: (r) => ss(() => repeat = r)),
                const SizedBox(height: 16),
                _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(selected: priority, onSelect: (p) => ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Add Reminder', () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  DateTime? dt;
                  if (useMinutes) {
                    final mins = int.tryParse(minutesCtrl.text.trim());
                    if (mins == null || mins <= 0) return;
                    dt = DateTime.now().add(Duration(minutes: mins));
                  } else {
                    if (repeat.isRepeating && picked == null) {
                      dt = repeat.nextOccurrence(DateTime.now());
                    } else {
                      if (picked == null) return;
                      dt = picked;
                    }
                  }
                  final id = '${DateTime.now().millisecondsSinceEpoch}';
                  final r = Reminder(
                    id: id, title: title, dateTime: dt!,
                    repeat: repeat, priority: priority,
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  await _svc.add(r);
                  if (mounted) setState(() => _lastAddedReminderId = id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add with pre-filled date ──────────────────────────────────

  Future<void> _showAddDialogForDate(DateTime date) async {
    final notesCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    DateTime?        picked   = DateTime(date.year, date.month, date.day, 9, 0);
    RepeatDays       repeat   = RepeatDays.once();
    ReminderPriority priority = ReminderPriority.normal;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                const Text('New Reminder', style: TextStyle(
                  color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w700, letterSpacing: -0.4,
                )),
                const SizedBox(height: 18),
                _SheetField(controller: titleCtrl, hint: 'Reminder title', icon: CupertinoIcons.bell),
                const SizedBox(height: 12),
                _DateTimePicker(selected: picked, onPick: (dt) => ss(() => picked = dt)),
                const SizedBox(height: 16),
                _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(repeat: repeat, onSelect: (r) => ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(repeat: repeat, onChanged: (r) => ss(() => repeat = r)),
                const SizedBox(height: 16),
                _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(selected: priority, onSelect: (p) => ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Add Reminder', () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty || picked == null) return;
                  final id = '${DateTime.now().millisecondsSinceEpoch}';
                  final r = Reminder(
                    id: id, title: title, dateTime: picked!,
                    repeat: repeat, priority: priority,
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  await _svc.add(r);
                  if (mounted) setState(() => _lastAddedReminderId = id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── View full reminder detail ─────────────────────────────────

  void _showDetailSheet(Reminder r) {
    final diff      = r.dateTime.difference(_now);
    final isPast    = diff.isNegative;
    final hrs       = diff.inHours.abs();
    final mins      = diff.inMinutes.abs();
    final countdown = isPast
        ? 'Passed'
        : hrs < 1
            ? 'In $mins min${mins == 1 ? '' : 's'}'
            : hrs < 24
                ? 'In $hrs hr${hrs == 1 ? '' : 's'}'
                : 'In ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';

    Color priorityColor;
    String priorityLabel;
    switch (r.priority) {
      case ReminderPriority.high:
        priorityColor = const Color(0xFFFF453A);
        priorityLabel = '↑ High';
        break;
      case ReminderPriority.normal:
        priorityColor = const Color(0xFF0A84FF);
        priorityLabel = '→ Normal';
        break;
      case ReminderPriority.low:
        priorityColor = const Color(0xFF30D158);
        priorityLabel = '↓ Low';
        break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 20),

            // Header row: bell icon + countdown badge
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: isPast
                      ? const Color(0xFF1E1E1E)
                      : priorityColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(CupertinoIcons.bell_fill,
                    color: isPast ? Colors.white24 : priorityColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPast
                            ? Colors.white10
                            : priorityColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isPast
                              ? Colors.white12
                              : priorityColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        countdown,
                        style: TextStyle(
                          color: isPast ? Colors.white38 : priorityColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('EEE, MMM d · hh:mm a').format(r.dateTime),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Full title — no line limit
            Text(
              r.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),

            // Full notes — no line limit
            if (r.notes != null && r.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  r.notes!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Metadata chips row
            Wrap(spacing: 8, runSpacing: 8, children: [
              // Priority
              _DetailChip(
                label: priorityLabel,
                color: priorityColor,
              ),
              // Repeat
              if (r.isRepeating)
                _DetailChip(
                  label: r.repeat.label,
                  color: const Color(0xFF0A84FF),
                ),
            ]),

            const SizedBox(height: 24),

            // Action buttons
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditDialog(r);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.pencil,
                            color: Colors.white70, size: 16),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(
                          color: Colors.white70, fontSize: 15,
                          fontWeight: FontWeight.w600,
                        )),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _svc.remove(r.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFFF3B30).withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.trash,
                            color: Color(0xFFFF3B30), size: 16),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(
                          color: Color(0xFFFF3B30), fontSize: 15,
                          fontWeight: FontWeight.w600,
                        )),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Edit reminder ─────────────────────────────────────────────

  Future<void> _showEditDialog(Reminder existing) async {
    final titleCtrl = TextEditingController(text: existing.title);
    final notesCtrl = TextEditingController(text: existing.notes ?? '');
    DateTime?        picked   = existing.dateTime;
    RepeatDays       repeat   = existing.repeat;
    ReminderPriority priority = existing.priority;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                // Title row with delete button
                Row(children: [
                  const Text('Edit Reminder', style: TextStyle(
                    color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.w700, letterSpacing: -0.4,
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await _svc.remove(existing.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.trash, color: Color(0xFFFF3B30), size: 13),
                        SizedBox(width: 5),
                        Text('Delete', style: TextStyle(
                          color: Color(0xFFFF3B30), fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _SheetField(controller: titleCtrl, hint: 'Reminder title', icon: CupertinoIcons.bell),
                const SizedBox(height: 12),
                _DateTimePicker(selected: picked, onPick: (dt) => ss(() => picked = dt)),
                const SizedBox(height: 16),
                _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(repeat: repeat, onSelect: (r) => ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(repeat: repeat, onChanged: (r) => ss(() => repeat = r)),
                const SizedBox(height: 16),
                _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(selected: priority, onSelect: (p) => ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Save Changes', () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty || picked == null) return;
                  final updated = existing.copyWith(
                    title:    title,
                    dateTime: picked,
                    repeat:   repeat,
                    priority: priority,
                    notes:    notesCtrl.text.trim().isEmpty
                                ? null
                                : notesCtrl.text.trim(),
                  );
                  await _svc.update(updated);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(CupertinoIcons.back, color: Colors.white54, size: 26),
              ),
              const SizedBox(width: 8),
              const Text('Reminders', style: TextStyle(
                color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w700, letterSpacing: -0.6,
              )),
              const Spacer(),
              _TopIconBtn(icon: CupertinoIcons.plus, onTap: _showAddDialog),
              const SizedBox(width: 4),
              _TopIconBtn(icon: CupertinoIcons.ellipsis_vertical, onTap: _showOptionsMenu),
            ]),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Reminder>>(
              valueListenable: _svc.reminders,
              builder: (_, reminders, __) => SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(children: [
                  const SizedBox(height: 16),
                  _ClockCalendarPanel(
                    now:                 _now,
                    timezoneLabel:       _timezoneLabel,
                    onTimezoneTap:       _showTimezoneMenu,
                    reminders:           reminders,
                    onDateTap:           _showAddDialogForDate,
                    lastAddedReminderId: _lastAddedReminderId,
                    onDotBloomDone:      () => setState(() => _lastAddedReminderId = null),
                  ),
                  const SizedBox(height: 20),
                  if (reminders.isEmpty)
                    _EmptyReminders(onAdd: _showAddDialog)
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: reminders.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1, indent: 68, color: Color(0xFF1E1E1E),
                      ),
                      itemBuilder: (_, i) => _ReminderTile(
                        key:          ValueKey(reminders[i].id),
                        reminder:     reminders[i],
                        now:          _now,
                        onDelete:     () => _svc.remove(reminders[i].id),
                        onEdit:       () => _showEditDialog(reminders[i]),
                        onViewDetail: () => _showDetailSheet(reminders[i]),
                      ),
                    ),
                  const SizedBox(height: 100),
                ]),
              ),
            ),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: const Color(0xFF0A84FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(CupertinoIcons.plus, color: Colors.white, size: 26),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Reminder tile — swipe RIGHT = edit  |  swipe LEFT = delete
// ════════════════════════════════════════════════════════════════

class _ReminderTile extends StatefulWidget {
  final Reminder     reminder;
  final DateTime     now;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onViewDetail;

  const _ReminderTile({
    super.key,
    required this.reminder,
    required this.now,
    required this.onDelete,
    required this.onEdit,
    required this.onViewDetail,
  });

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile>
    with SingleTickerProviderStateMixin {

  static const double _kActionW = 72.0;
  static const double _kThresh  = 44.0;
  static const double _kMax     = _kActionW + 12.0;

  double _offset       = 0.0;  // positive = right (edit), negative = left (delete)
  bool   _editOpen     = false;
  bool   _deleteOpen   = false;

  late AnimationController _snapCtrl;
  double _snapFrom   = 0.0;
  double _snapTarget = 0.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        setState(() => _offset = _lerp(_snapFrom, _snapTarget, _snapCtrl.value));
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _snapFrom   = _offset;
    _snapTarget = target;
    _snapCtrl.forward(from: 0);
  }

  void _closeActions() {
    _animateTo(0);
    _editOpen   = false;
    _deleteOpen = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_editOpen || _deleteOpen) {
      // Already snapped — small drag closes
      if ((_editOpen   && d.delta.dx < -6) ||
          (_deleteOpen && d.delta.dx >  6)) {
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
      setState(() { _editOpen = true; _deleteOpen = false; });
    } else if (_offset < -_kThresh) {
      _animateTo(-_kActionW);
      setState(() { _deleteOpen = true; _editOpen = false; });
    } else {
      _animateTo(0);
    }
  }

  Color get _priorityColor {
    switch (widget.reminder.priority) {
      case ReminderPriority.high:   return const Color(0xFFFF453A);
      case ReminderPriority.normal: return const Color(0xFF0A84FF);
      case ReminderPriority.low:    return const Color(0xFF30D158);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff        = widget.reminder.dateTime.difference(widget.now);
    final isPast      = diff.isNegative;
    final hrs         = diff.inHours.abs();
    final mins        = diff.inMinutes.abs();
    final shouldPulse = !isPast && diff.inMinutes < 10;
    final countdown   = isPast
        ? 'Passed'
        : hrs < 1
            ? 'In $mins min${mins == 1 ? '' : 's'}'
            : hrs < 24
                ? 'In $hrs hr${hrs == 1 ? '' : 's'}'
                : 'In ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    final timeStr = DateFormat('hh:mm a').format(widget.reminder.dateTime);
    final dateStr = DateFormat('EEE, MMM d').format(widget.reminder.dateTime);

    final editRatio   = (_offset / _kActionW).clamp(0.0, 1.0);
    final deleteRatio = (-_offset / _kActionW).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd:    _onDragEnd,
      onTap: (_editOpen || _deleteOpen) ? _closeActions : null,
      child: ClipRect(
        child: Stack(
          children: [

            // ── Edit button (behind, revealed on swipe right) ───
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Opacity(
                  opacity: editRatio.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * editRatio,
                    child: GestureDetector(
                      onTap: () { _closeActions(); widget.onEdit(); },
                      child: Container(
                        width: _kActionW,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A84FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CupertinoIcons.pencil,
                                color: Colors.white, size: 18),
                            SizedBox(height: 4),
                            Text('Edit', style: TextStyle(
                              color: Colors.white, fontSize: 11,
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

            // ── Delete button (behind, revealed on swipe left) ──
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
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(height: 4),
                            Text('Delete', style: TextStyle(
                              color: Colors.white, fontSize: 11,
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

            // ── Main content — natural height, slides on drag ───
            Transform.translate(
              offset: Offset(_offset, 0),
              child: Container(
                color: const Color(0xFF0A0A0A),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Bell icon — fixed square, never resizes
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: isPast
                            ? const Color(0xFF1E1E1E)
                            : _priorityColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(CupertinoIcons.bell_fill,
                          color: isPast ? Colors.white12 : _priorityColor,
                          size: 20),
                    ),
                    const SizedBox(width: 14),

                    // Title + subtitle — tap to view full detail
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: (_editOpen || _deleteOpen)
                            ? _closeActions
                            : widget.onViewDetail,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.reminder.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPast ? Colors.white24 : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(children: [
                            Flexible(
                              child: Text(
                                '$dateStr · $timeStr',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                            ),
                            if (widget.reminder.isRepeating) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A84FF)
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.reminder.repeat.shortLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF0A84FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          if (widget.reminder.notes != null &&
                              widget.reminder.notes!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.reminder.notes!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white24, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Time + countdown — FittedBox ensures text never wraps
                    SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                color: isPast ? Colors.white24 : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w200,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          _CountdownLabel(
                            text:  countdown,
                            color: isPast ? Colors.white24 : _priorityColor,
                            pulse: shouldPulse,
                          ),
                        ],
                      ),
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

// ════════════════════════════════════════════════════════════════
// Repeat presets
// ════════════════════════════════════════════════════════════════

class _RepeatPresets extends StatelessWidget {
  final RepeatDays repeat;
  final ValueChanged<RepeatDays> onSelect;
  const _RepeatPresets({required this.repeat, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final presets = [
      ('Once',     RepeatDays.once()),
      ('Daily',    RepeatDays.daily()),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF0A84FF) : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? const Color(0xFF0A84FF) : Colors.white12,
              ),
            ),
            child: Text(label, style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Day checkbox grid
// ════════════════════════════════════════════════════════════════

class _DayCheckboxGrid extends StatelessWidget {
  final RepeatDays repeat;
  final ValueChanged<RepeatDays> onChanged;
  const _DayCheckboxGrid({required this.repeat, required this.onChanged});

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
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: isOn ? const Color(0xFF0A84FF) : const Color(0xFF1C1C1E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOn ? const Color(0xFF0A84FF) : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isOn
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                    : Text(Weekday.shortName(day).substring(0, 1),
                        style: const TextStyle(
                          color: Colors.white38, fontSize: 12,
                          fontWeight: FontWeight.w500,
                        )),
              ),
            ),
            const SizedBox(height: 4),
            Text(Weekday.shortName(day), style: TextStyle(
              color: isOn ? const Color(0xFF0A84FF) : Colors.white38,
              fontSize: 9,
              fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
            )),
          ]),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Priority selector
// ════════════════════════════════════════════════════════════════

class _PrioritySelector extends StatelessWidget {
  final ReminderPriority selected;
  final ValueChanged<ReminderPriority> onSelect;
  const _PrioritySelector({required this.selected, required this.onSelect});

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
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.18) : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? color : Colors.white12),
              ),
              child: Center(child: Text(label, style: TextStyle(
                color: isSelected ? color : Colors.white38,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ))),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Reusable sheet widgets
// ════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    color: Colors.white38, fontSize: 12,
    fontWeight: FontWeight.w600, letterSpacing: 0.8,
  ));
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;

  const _SheetField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 14),
          child: Icon(icon, color: Colors.white38, size: 18),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final bool useMinutes;
  final ValueChanged<bool> onToggle;
  const _TogglePill({required this.useMinutes, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        _Pill(label: 'Set time',   selected: !useMinutes, onTap: () => onToggle(false)),
        _Pill(label: 'In minutes', selected: useMinutes,  onTap: () => onToggle(true)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0A84FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: Text(label, style: TextStyle(
            color: selected ? Colors.white : Colors.white38,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ))),
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  const _DateTimePicker({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: selected ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate:  DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(selected ?? DateTime.now()),
        );
        if (time == null) return;
        onPick(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          const Icon(CupertinoIcons.calendar, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Text(
            selected == null
                ? 'Pick date & time'
                : DateFormat('EEE, MMM d · hh:mm a').format(selected!),
            style: TextStyle(
              color: selected == null ? Colors.white24 : Colors.white,
              fontSize: 15,
            ),
          ),
        ]),
      ),
    );
  }
}

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

// ════════════════════════════════════════════════════════════════
// Empty state
// ════════════════════════════════════════════════════════════════

class _EmptyReminders extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyReminders({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Column(children: [
        const Divider(color: Color(0xFF1E1E1E)),
        const SizedBox(height: 40),
        const Icon(CupertinoIcons.bell_slash, size: 48, color: Color(0xFF2C2C2C)),
        const SizedBox(height: 14),
        const Text('No reminders yet', style: TextStyle(
            color: Colors.white38, fontSize: 17, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text(
          'Tap + to add a reminder\nby time, minutes, or recurring day.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 14, height: 1.5),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Countdown label (pulses when < 10 min away)
// ════════════════════════════════════════════════════════════════

class _CountdownLabel extends StatefulWidget {
  final String text;
  final Color  color;
  final bool   pulse;
  const _CountdownLabel({required this.text, required this.color, required this.pulse});

  @override
  State<_CountdownLabel> createState() => _CountdownLabelState();
}

class _CountdownLabelState extends State<_CountdownLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
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
          style: TextStyle(color: widget.color, fontSize: 12));
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Text(widget.text, style: TextStyle(
          color: widget.color, fontSize: 12, fontWeight: FontWeight.w700,
        )),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Analog clock  (sweep-in + timezone resync animations)
// ════════════════════════════════════════════════════════════════

class _AnalogClock extends StatefulWidget {
  final DateTime   now;
  final bool       sweepIn;
  final bool       resync;
  final VoidCallback? onSweepDone;

  const _AnalogClock({
    required this.now,
    this.sweepIn     = false,
    this.resync      = false,
    this.onSweepDone,
  });

  @override
  State<_AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<_AnalogClock>
    with TickerProviderStateMixin {
  late AnimationController _sweepCtrl;
  late Animation<double>   _sweepAnim;
  late AnimationController _resyncCtrl;
  late Animation<double>   _resyncAnim;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _sweepAnim = CurvedAnimation(
        parent: _sweepCtrl, curve: Curves.easeOutCubic);

    _resyncCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _resyncAnim = CurvedAnimation(
        parent: _resyncCtrl, curve: Curves.easeInOutCubic);

    if (widget.sweepIn) {
      _sweepCtrl.forward().then((_) => widget.onSweepDone?.call());
    } else {
      _sweepCtrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AnalogClock old) {
    super.didUpdateWidget(old);
    if (widget.resync && !old.resync) {
      _resyncCtrl.forward(from: 0).then((_) => widget.onSweepDone?.call());
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
      animation: Listenable.merge([_sweepAnim, _resyncAnim]),
      builder: (_, __) => CustomPaint(
        painter: _ClockPainter(
          now:        widget.now,
          sweepT:     _sweepAnim.value,
          resyncT:    _resyncAnim.value,
          resyncDone: !_resyncCtrl.isAnimating,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime now;
  final double   sweepT;
  final double   resyncT;
  final bool     resyncDone;

  const _ClockPainter({
    required this.now,
    required this.sweepT,
    required this.resyncT,
    required this.resyncDone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = math.min(cx, cy);

    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = const Color(0xFF2C2C2C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    for (int i = 0; i < 12; i++) {
      final angle  = (i / 12) * 2 * math.pi - math.pi / 2;
      final isMain = i % 3 == 0;
      final len    = isMain ? r * 0.12 : r * 0.06;
      canvas.drawLine(
        Offset(cx + (r - 10) * math.cos(angle),
               cy + (r - 10) * math.sin(angle)),
        Offset(cx + (r - 10 - len) * math.cos(angle),
               cy + (r - 10 - len) * math.sin(angle)),
        Paint()
          ..color      = isMain ? Colors.white54 : Colors.white24
          ..strokeWidth = isMain ? 2.0 : 1.2
          ..strokeCap  = StrokeCap.round,
      );
    }

    final tHour = ((now.hour % 12 + now.minute / 60) / 12) * 2 * math.pi - math.pi / 2;
    final tMin  = ((now.minute + now.second / 60) / 60) * 2 * math.pi - math.pi / 2;
    final tSec  = (now.second / 60) * 2 * math.pi - math.pi / 2;
    const start = -math.pi / 2;

    final hourAngle = _lerp(start, tHour, sweepT);
    final minAngle  = _lerp(start, tMin,  sweepT);
    double secAngle = _lerp(start, tSec,  sweepT);
    if (!resyncDone) secAngle = tSec + resyncT * 2 * math.pi;

    _hand(canvas, cx, cy, angle: hourAngle, length: r * 0.50, width: 5.0,
        color: Colors.white);
    _hand(canvas, cx, cy, angle: minAngle,  length: r * 0.68, width: 3.5,
        color: Colors.white70);
    _hand(canvas, cx, cy, angle: secAngle,  length: r * 0.74, width: 1.8,
        color: const Color(0xFF0A84FF), tail: r * 0.18);

    canvas.drawCircle(Offset(cx, cy), 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), 3.0,
        Paint()..color = const Color(0xFF0A84FF));
  }

  void _hand(Canvas canvas, double cx, double cy, {
    required double angle,
    required double length,
    required double width,
    required Color  color,
    double tail = 0,
  }) {
    canvas.drawLine(
      Offset(cx - tail * math.cos(angle), cy - tail * math.sin(angle)),
      Offset(cx + length * math.cos(angle), cy + length * math.sin(angle)),
      Paint()
        ..color      = color
        ..strokeWidth = width
        ..strokeCap  = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.now != now || old.sweepT != sweepT ||
      old.resyncT != resyncT || old.resyncDone != resyncDone;
}

// ════════════════════════════════════════════════════════════════
// Clock / Calendar panel  (AnimatedCrossFade — no fixed heights)
// ════════════════════════════════════════════════════════════════

class _ClockCalendarPanel extends StatefulWidget {
  final DateTime       now;
  final String         timezoneLabel;
  final VoidCallback   onTimezoneTap;
  final List<Reminder> reminders;
  final void Function(DateTime) onDateTap;
  final String?        lastAddedReminderId;
  final VoidCallback   onDotBloomDone;

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
  State<_ClockCalendarPanel> createState() => _ClockCalendarPanelState();
}

class _ClockCalendarPanelState extends State<_ClockCalendarPanel>
    with TickerProviderStateMixin {

  int      _page        = 0;
  DateTime _calMonth    = DateTime.now();
  DateTime? _selectedDay;
  int      _monthSlideDir = 1;

  bool    _clockSweptIn  = false;
  bool    _triggerResync = false;
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
      setState(() { _triggerResync = true; _prevTzLabel = widget.timezoneLabel; });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _triggerResync = false);
      });
    }

    if (widget.lastAddedReminderId != null &&
        !_bloomCtrls.containsKey(widget.lastAddedReminderId)) {
      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 600));
      _bloomCtrls[widget.lastAddedReminderId!] = ctrl;
      ctrl.forward().then((_) {
        widget.onDotBloomDone();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ctrl.dispose();
            _bloomCtrls.remove(widget.lastAddedReminderId);
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
    _calMonth = DateTime(_calMonth.year, _calMonth.month - 1);
  });

  void _nextMonth() => setState(() {
    _monthSlideDir = 1;
    _calMonth = DateTime(_calMonth.year, _calMonth.month + 1);
  });

  bool _hasReminder(DateTime day) => widget.reminders.any((r) =>
      r.dateTime.year  == day.year &&
      r.dateTime.month == day.month &&
      r.dateTime.day   == day.day);

  Reminder? _lastAddedOnDay(DateTime day) {
    if (widget.lastAddedReminderId == null) return null;
    try {
      return widget.reminders.firstWhere((r) =>
          r.id == widget.lastAddedReminderId &&
          r.dateTime.year  == day.year &&
          r.dateTime.month == day.month &&
          r.dateTime.day   == day.day);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // AnimatedCrossFade lets each child size itself naturally —
      // no fixed pixel heights, so 6-row months never overflow.
      AnimatedCrossFade(
        duration:       const Duration(milliseconds: 320),
        sizeCurve:      Curves.easeOutCubic,
        firstCurve:     Curves.easeOutCubic,
        secondCurve:    Curves.easeOutCubic,
        crossFadeState: _page == 0
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        firstChild: GestureDetector(
          onHorizontalDragEnd: (d) {
            if (d.primaryVelocity != null && d.primaryVelocity! < -300) {
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
      // Page dots — tappable
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
      // Swipe hint (only on calendar page)
      AnimatedOpacity(
        opacity:  _page == 1 ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity!.abs() > 200) {
                setState(() => _page = 0);
              }
            },
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.arrow_left,  color: Colors.white12, size: 10),
              SizedBox(width: 4),
              Text('swipe to clock',
                  style: TextStyle(color: Colors.white12, fontSize: 10)),
              SizedBox(width: 4),
              Icon(CupertinoIcons.arrow_right, color: Colors.white12, size: 10),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }

  // ── Clock page ────────────────────────────────────────────────

  Widget _buildClockPage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        AnimatedScale(
          scale:    _clockSweptIn ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 700),
          curve:    Curves.easeOutBack,
          child: Center(
            child: SizedBox(
              width: 190, height: 190,
              child: _AnalogClock(
                now:     widget.now,
                sweepIn: true,
                resync:  _triggerResync,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedOpacity(
          opacity:  _clockSweptIn ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                DateFormat('hh:mm:ss a').format(widget.now),
                key: ValueKey(widget.timezoneLabel),
                style: const TextStyle(
                  color: Colors.white, fontSize: 38,
                  fontWeight: FontWeight.w200, letterSpacing: -1.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(DateFormat('EEE, MMM d').format(widget.now),
                style: const TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: widget.onTimezoneTap,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    widget.timezoneLabel.isEmpty ? ' ' : widget.timezoneLabel,
                    key: ValueKey(widget.timezoneLabel),
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down,
                    color: Colors.white24, size: 11),
              ]),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ],
    );
  }

  // ── Calendar page ─────────────────────────────────────────────

  Widget _buildCalendarPage() {
    final firstDay  = DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMon = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final startWd   = (firstDay.weekday - 1) % 7;
    final today     = DateTime.now();

    final List<DateTime?> cells = [
      ...List.filled(startWd, null),
      ...List.generate(daysInMon,
          (i) => DateTime(_calMonth.year, _calMonth.month, i + 1)),
    ];
    while (cells.length % 7 != 0) cells.add(null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

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
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.chevron_left,
                        color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) {
                  final slide = Tween<Offset>(
                    begin: Offset(_monthSlideDir * 0.3, 0),
                    end:   Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic));
                  return FadeTransition(opacity: anim,
                      child: SlideTransition(position: slide, child: child));
                },
                child: Text(
                  DateFormat('MMMM yyyy').format(_calMonth),
                  key: ValueKey(_calMonth),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('hh:mm a').format(widget.now),
                style: const TextStyle(
                  color: Colors.white38, fontSize: 11,
                  fontWeight: FontWeight.w300, letterSpacing: 0.5,
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
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.chevron_right,
                        color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 4),
        // Day-of-week headers
        Row(
          children: ['Mo','Tu','We','Th','Fr','Sa','Su'].map((d) =>
            Expanded(child: Center(child: Text(d, style: const TextStyle(
              color: Colors.white24, fontSize: 12,
              fontWeight: FontWeight.w600,
            ))))).toList(),
        ),
        const SizedBox(height: 6),

        // Calendar grid rows
        ...List.generate(cells.length ~/ 7, (row) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: List.generate(7, (col) {
              final day = cells[row * 7 + col];
              if (day == null) return const Expanded(child: SizedBox());

              final isToday = day.year  == today.year &&
                              day.month == today.month &&
                              day.day   == today.day;
              final isSelected = _selectedDay != null &&
                                 day.year  == _selectedDay!.year &&
                                 day.month == _selectedDay!.month &&
                                 day.day   == _selectedDay!.day;
              final hasRem  = _hasReminder(day);
              final isPast  = day.isBefore(
                  DateTime(today.year, today.month, today.day));
              final bloomCtrl  = _bloomCtrls[widget.lastAddedReminderId];
              final isBloomDay = _lastAddedOnDay(day) != null &&
                                 bloomCtrl != null;
              final staggerMs  = (row * 7 + col) * 18;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = day);
                    widget.onDateTap(day);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 2, vertical: 1),
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0A84FF)
                          : isToday
                              ? const Color(0xFF0A84FF).withOpacity(0.15)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isToday && !isSelected
                          ? Border.all(
                              color: const Color(0xFF0A84FF).withOpacity(0.5),
                              width: 1)
                          : null,
                    ),
                    child: Stack(alignment: Alignment.center, children: [
                      Text('${day.day}', style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : isPast
                                ? Colors.white24
                                : isToday
                                    ? const Color(0xFF0A84FF)
                                    : Colors.white70,
                        fontSize: 15,
                        fontWeight: isToday || isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      )),
                      if (hasRem)
                        Positioned(
                          bottom: 3,
                          child: isBloomDay
                              ? _BloomDot(
                                  controller: bloomCtrl!,
                                  isSelected: isSelected)
                              : _StaggerDot(
                                  delay: Duration(milliseconds: staggerMs),
                                  isSelected: isSelected),
                        ),
                    ]),
                  ),
                ),
              );
            }),
          ),
        )),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Staggered dot pop-in (Effect #2)
// ════════════════════════════════════════════════════════════════

class _StaggerDot extends StatefulWidget {
  final Duration delay;
  final bool     isSelected;
  const _StaggerDot({required this.delay, required this.isSelected});

  @override
  State<_StaggerDot> createState() => _StaggerDotState();
}

class _StaggerDotState extends State<_StaggerDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(widget.delay, () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 4, height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isSelected ? Colors.white70 : const Color(0xFF0A84FF),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Bloom dot when reminder is added (Effect #4)
// ════════════════════════════════════════════════════════════════

class _BloomDot extends StatelessWidget {
  final AnimationController controller;
  final bool                isSelected;
  const _BloomDot({required this.controller, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: controller,
          curve: const Interval(0.0, 0.5, curve: Curves.elasticOut)));
    final glowOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: controller,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));
    final glowSize = Tween<double>(begin: 4.0, end: 20.0).animate(
      CurvedAnimation(parent: controller,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Stack(alignment: Alignment.center, children: [
        Opacity(
          opacity: glowOpacity.value,
          child: Container(
            width: glowSize.value, height: glowSize.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A84FF).withOpacity(0.3),
            ),
          ),
        ),
        ScaleTransition(
          scale: scale,
          child: Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Colors.white : const Color(0xFF0A84FF),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A84FF).withOpacity(0.6),
                  blurRadius: 6, spreadRadius: 1,
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
// Detail chip — used in the detail bottom sheet
// ════════════════════════════════════════════════════════════════

class _DetailChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _DetailChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Page dot indicator
// ════════════════════════════════════════════════════════════════

class _PageDot extends StatelessWidget {
  final bool active;
  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve:    Curves.easeOutCubic,
      width:    active ? 20 : 6,
      height:   6,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0A84FF) : Colors.white12,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Timezone picker sheet
// ════════════════════════════════════════════════════════════════

class _TzPickerSheet extends StatefulWidget {
  final String                   selectedTz;
  final bool                     useDeviceTz;
  final String                   deviceTz;
  final String Function(String)  gmtOffset;
  final void Function(TzCity)    onPick;
  final VoidCallback             onUseDevice;

  const _TzPickerSheet({
    required this.selectedTz,
    required this.useDeviceTz,
    required this.deviceTz,
    required this.gmtOffset,
    required this.onPick,
    required this.onUseDevice,
  });

  @override
  State<_TzPickerSheet> createState() => _TzPickerSheetState();
}

class _TzPickerSheetState extends State<_TzPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<TzCity> _filtered     = List.from(kAllCities);
  String       _activeLetter = '';
  bool         _isDragging   = false;
  String       _dragLetter   = '';
  bool         _isSearching  = false;

  late Map<String, int> _letterIndex;
  late List<String>     _letters;

  static const double _itemH   = 62.0;
  static const double _headerH = 32.0;

  @override
  void initState() {
    super.initState();
    _buildIndex(kAllCities);
    _scrollCtrl.addListener(_onScroll);
    if (_letters.isNotEmpty) _activeLetter = _letters.first;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _buildIndex(List<TzCity> cities) {
    _letterIndex = {};
    for (int i = 0; i < cities.length; i++) {
      final l = cities[i].city[0].toUpperCase();
      _letterIndex.putIfAbsent(l, () => i);
    }
    _letters = _letterIndex.keys.toList()..sort();
  }

  void _onScroll() {
    if (_isSearching || _letters.isEmpty) return;
    final offset  = _scrollCtrl.offset;
    String current = _letters.first;
    for (final letter in _letters) {
      if (_estimatedOffset(_letterIndex[letter]!) <= offset + 80) {
        current = letter;
      }
    }
    if (current != _activeLetter) setState(() => _activeLetter = current);
  }

  double _estimatedOffset(int idx) {
    int headers = 0;
    String? last;
    for (int i = 0; i < idx && i < kAllCities.length; i++) {
      final l = kAllCities[i].city[0].toUpperCase();
      if (l != last) { headers++; last = l; }
    }
    return idx * _itemH + headers * _headerH;
  }

  void _jumpToLetter(String letter) {
    final idx = _letterIndex[letter];
    if (idx == null) return;
    final target = _estimatedOffset(idx)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic);
    setState(() { _activeLetter = letter; _dragLetter = letter; });
  }

  String? _letterFromY(double y, double totalH) {
    if (_letters.isEmpty) return null;
    final i = (y / totalH * _letters.length)
        .floor()
        .clamp(0, _letters.length - 1);
    return _letters[i];
  }

  void _onSearch(String q) {
    setState(() {
      _isSearching = q.isNotEmpty;
      _filtered    = q.isEmpty
          ? List.from(kAllCities)
          : kAllCities.where((c) =>
              c.city.toLowerCase().contains(q.toLowerCase()) ||
              c.country.toLowerCase().contains(q.toLowerCase())).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: [
        const SizedBox(height: 12),
        Center(child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(2),
          ),
        )),
        const SizedBox(height: 16),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('Select City', style: TextStyle(
              color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w700, letterSpacing: -0.4,
            )),
            const Spacer(),
            GestureDetector(
              onTap: () { widget.onUseDevice(); Navigator.of(context).pop(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.useDeviceTz
                      ? const Color(0xFF0A84FF).withOpacity(0.18)
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.useDeviceTz
                        ? const Color(0xFF0A84FF)
                        : Colors.white12,
                  ),
                ),
                child: Text('Use device', style: TextStyle(
                  color: widget.useDeviceTz
                      ? const Color(0xFF0A84FF)
                      : Colors.white38,
                  fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Icon(CupertinoIcons.search, color: Colors.white38, size: 18),
              ),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Search cities or countries...',
                    hintStyle: TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              if (_isSearching)
                GestureDetector(
                  onTap: () { _searchCtrl.clear(); _onSearch(''); },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        color: Colors.white24, size: 18),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // City list + A–Z scrubber
        Expanded(
          child: Stack(children: [
            ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(left: 12, right: 44, bottom: 20),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final item       = _filtered[i];
                final isSelected = item.tzName == widget.selectedTz &&
                                   !widget.useDeviceTz;
                final offset     = widget.gmtOffset(item.tzName);
                final showHeader = !_isSearching &&
                    (i == 0 ||
                     _filtered[i].city[0].toUpperCase() !=
                     _filtered[i - 1].city[0].toUpperCase());
                final letter   = item.city[0].toUpperCase();
                final isActive = letter == _activeLetter && !_isSearching;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
                        child: Row(children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: TextStyle(
                              color: isActive
                                  ? const Color(0xFF0A84FF)
                                  : Colors.white24,
                              fontSize: isActive ? 14 : 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                            child: Text(letter),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 24, height: 1.5,
                              color: const Color(0xFF0A84FF).withOpacity(0.4),
                            ),
                          ],
                        ]),
                      ),
                    GestureDetector(
                      onTap: () {
                        widget.onPick(item);
                        Navigator.of(context).pop();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0A84FF).withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0A84FF).withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.city, style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF0A84FF)
                                      : Colors.white,
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                )),
                                Text('${item.country}, $offset',
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFF0A84FF)
                                              .withOpacity(0.7)
                                          : Colors.white38,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            opacity:  isSelected ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.check_rounded,
                                color: Color(0xFF0A84FF), size: 18),
                          ),
                        ]),
                      ),
                    ),
                  ],
                );
              },
            ),
            // A–Z scrubber
            if (!_isSearching)
              Positioned(
                right: 0, top: 0, bottom: 0, width: 28,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final totalH = constraints.maxHeight;
                    return GestureDetector(
                      onTapDown: (d) {
                        final l = _letterFromY(d.localPosition.dy, totalH);
                        if (l != null) _jumpToLetter(l);
                      },
                      onVerticalDragStart: (d) {
                        setState(() => _isDragging = true);
                        final l = _letterFromY(d.localPosition.dy, totalH);
                        if (l != null) { _dragLetter = l; _jumpToLetter(l); }
                      },
                      onVerticalDragUpdate: (d) {
                        final l = _letterFromY(d.localPosition.dy, totalH);
                        if (l != null && l != _dragLetter) {
                          setState(() => _dragLetter = l);
                          _jumpToLetter(l);
                        }
                      },
                      onVerticalDragEnd: (_) {
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (mounted) setState(() => _isDragging = false);
                        });
                      },
                      child: Stack(alignment: Alignment.center, children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _letters.map((letter) {
                            final isActive     = letter == _activeLetter;
                            final isDragTarget = _isDragging &&
                                                 letter == _dragLetter;
                            return GestureDetector(
                              onTap: () => _jumpToLetter(letter),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width:  isDragTarget ? 24 : 18,
                                height: isDragTarget ? 24 : 16,
                                margin: const EdgeInsets.symmetric(
                                    vertical: 0.5),
                                decoration: isDragTarget
                                    ? const BoxDecoration(
                                        color: Color(0xFF0A84FF),
                                        shape: BoxShape.circle,
                                      )
                                    : null,
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: TextStyle(
                                      color: isDragTarget
                                          ? Colors.white
                                          : isActive
                                              ? const Color(0xFF0A84FF)
                                              : Colors.white38,
                                      fontSize: isDragTarget || isActive
                                          ? 12 : 10,
                                      fontWeight: isActive || isDragTarget
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                    child: Text(letter),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_isDragging && _dragLetter.isNotEmpty &&
                            _letters.length > 1)
                          Positioned(
                            right: 32,
                            top: (_letters.indexOf(_dragLetter) /
                                    (_letters.length - 1) *
                                    (totalH - 48))
                                .clamp(0.0, totalH - 48),
                            child: Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A84FF),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0A84FF)
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(_dragLetter,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    )),
                              ),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}