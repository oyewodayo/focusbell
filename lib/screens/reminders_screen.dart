// reminders_screen.dart — MAIN FILE
// Split architecture:
//   reminders_screen.dart          ← you are here (state, dialogs, build)
//   reminders_sheet_widgets.dart   ← reusable sheet sub-widgets
//   reminders_clock_calendar.dart  ← analog clock, calendar panel, dots, places
//   reminders_tiles.dart           ← ReminderTile, GroupedList, EmptyState
//   reminders_tz_picker.dart       ← timezone city picker sheet

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:url_launcher/url_launcher.dart';

import '../data/timezone_data.dart';
import '../models/reminder_model.dart';
import '../models/reminder_group.dart';
import '../models/saved_place.dart';
import '../services/geofence_service.dart';
import '../services/continuity_service.dart';
import '../services/reminder_service.dart';
import '../services/reminder_group_service.dart';
import '../services/saved_places_service.dart';
import 'location_picker_sheet.dart';

part 'reminders_clock_calendar.dart';
part 'reminders_tiles.dart';
part 'reminders_tz_picker.dart';
part 'reminders_sheet_widgets.dart';

// ── lerp helper (avoids dart:ui conflict) ────────────────────
double _lerp(double a, double b, double t) =>
    a + (b - a) * t;

// ════════════════════════════════════════════════════════════════
// RemindersScreen
// ════════════════════════════════════════════════════════════════
class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _SheetField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 14),
            child: Icon(icon, color: Colors.white38, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
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
      child: Row(
        children: [
          _Pill(
            label: 'Set time',
            selected: !useMinutes,
            onTap: () => onToggle(false),
          ),
          _Pill(
            label: 'In minutes',
            selected: useMinutes,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() =>
      _RemindersScreenState();
}

class _RemindersScreenState
    extends State<RemindersScreen> {
  final _svc = ReminderService.instance;
  late Timer _ticker;
  DateTime _now = DateTime.now();

  String _deviceTz = '';
  String _selectedTz = '';
  String _selectedCity = '';
  String _selectedCountry = '';
  bool _useDeviceTz = true;

  String? _lastAddedReminderId;

  @override
  void initState() {
    super.initState();
    ContinuityService.instance.track(
        ContinuityActionType.openedScreen,
        detail: 'Reminders');
    _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
      if (mounted) setState(() => _now = _currentTime);
    });
    tz_data.initializeTimeZones();
    _resolveDeviceTimezone();
  }

  Future<void> _resolveDeviceTimezone() async {
    try {
      final tzName =
          await FlutterTimezone.getLocalTimezone();
      final match = kAllCities.firstWhere(
        (c) => c.tzName == tzName,
        orElse: () => TzCity(
          city: tzName
              .split('/')
              .last
              .replaceAll('_', ' '),
          country: '',
          tzName: tzName,
        ),
      );
      if (mounted) {
        setState(() {
          _deviceTz = tzName;
          _selectedTz = tzName;
          _selectedCity = match.city;
          _selectedCountry = match.country;
        });
      }
    } catch (_) {
      if (mounted)
        setState(() => _selectedCity = 'Local Time');
    }
  }

  DateTime get _currentTime {
    if (_useDeviceTz || _selectedTz.isEmpty) {
      return DateTime.now();
    }
    try {
      final loc = tz.getLocation(_selectedTz);
      final t = tz.TZDateTime.now(loc);
      return DateTime(
          t.year, t.month, t.day, t.hour, t.minute, t.second);
    } catch (_) {
      return DateTime.now();
    }
  }

  String _gmtOffset(String tzName) {
    try {
      final loc = tz.getLocation(tzName);
      final offset = tz.TZDateTime.now(loc).timeZoneOffset;
      final h = offset.inHours;
      final m = offset.inMinutes.abs() % 60;
      final sign = h >= 0 ? '+' : '-';
      return 'GMT $sign${h.abs().toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String get _timezoneLabel {
    if (_selectedCity.isEmpty) return '';
    return _useDeviceTz
        ? '$_selectedCity (Local)'
        : _selectedCity;
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  // ── Timezone picker ────────────────────────────────────────

  Future<void> _showTimezoneMenu() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TzPickerSheet(
        selectedTz: _selectedTz,
        useDeviceTz: _useDeviceTz,
        deviceTz: _deviceTz,
        gmtOffset: _gmtOffset,
        onPick: (city) {
          setState(() {
            _selectedTz = city.tzName;
            _selectedCity = city.city;
            _selectedCountry = city.country;
            _useDeviceTz = false;
            _now = _currentTime;
          });
        },
        onUseDevice: () {
          setState(() {
            _useDeviceTz = true;
            _selectedTz = _deviceTz;
            final match = kAllCities.firstWhere(
              (c) => c.tzName == _deviceTz,
              orElse: () => TzCity(
                city: _deviceTz
                    .split('/')
                    .last
                    .replaceAll('_', ' '),
                country: '',
                tzName: _deviceTz,
              ),
            );
            _selectedCity = match.city;
            _selectedCountry = match.country;
          });
        },
      ),
    );
  }

  // ── Options menu ───────────────────────────────────────────

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
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.globe,
                    size: 18,
                    color: Color(0xFF0A84FF)),
                SizedBox(width: 10),
                Text('Change Clock City',
                    style: TextStyle(
                        color: Color(0xFF0A84FF),
                        fontSize: 16)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Sheet helpers ──────────────────────────────────────────

  Widget _sheetWrap({required Widget child}) {
    return Container(
      margin:
          const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding:
          const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _sheetSaveBtn(
      String label, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ),
        ),
      );

  // ── Smart time suggestions ─────────────────────────────────

  static const _kSuggestions =
      <String, (int hour, int minute, String label)>{
    'medication': (8, 0, 'Suggest 8:00 AM for medication?'),
    'medicine': (8, 0, 'Suggest 8:00 AM for medicine?'),
    'pill': (8, 0, 'Suggest 8:00 AM for pills?'),
    'vitamins': (8, 0, 'Suggest 8:00 AM for vitamins?'),
    'gym': (6, 0, 'Suggest 6:00 AM for gym?'),
    'workout': (6, 30, 'Suggest 6:30 AM for workout?'),
    'exercise': (7, 0, 'Suggest 7:00 AM for exercise?'),
    'run': (6, 0, 'Suggest 6:00 AM for your run?'),
    'jog': (6, 0, 'Suggest 6:00 AM for jogging?'),
    'breakfast': (7, 30, 'Suggest 7:30 AM for breakfast?'),
    'lunch': (13, 0, 'Suggest 1:00 PM for lunch?'),
    'dinner': (19, 0, 'Suggest 7:00 PM for dinner?'),
    'meeting': (9, 0, 'Suggest 9:00 AM for meeting?'),
    'standup': (9, 0, 'Suggest 9:00 AM for standup?'),
    'call': (10, 0, 'Suggest 10:00 AM for call?'),
    'sleep': (22, 30, 'Suggest 10:30 PM for sleep?'),
    'bed': (22, 0, 'Suggest 10:00 PM for bedtime?'),
    'pray': (5, 0, 'Suggest 5:00 AM for prayer?'),
    'prayer': (5, 0, 'Suggest 5:00 AM for prayer?'),
    'morning': (7, 0, 'Suggest 7:00 AM?'),
    'evening': (18, 0, 'Suggest 6:00 PM?'),
    'night': (21, 0, 'Suggest 9:00 PM?'),
    'water': (8, 0, 'Suggest 8:00 AM for hydration?'),
    'journal': (21, 0, 'Suggest 9:00 PM for journaling?'),
    'read': (21, 30, 'Suggest 9:30 PM for reading?'),
    'reading': (21, 30, 'Suggest 9:30 PM for reading?'),
    'school': (7, 0, 'Suggest 7:00 AM for school?'),
    'class': (8, 0, 'Suggest 8:00 AM for class?'),
  };

  String? _smartTimeSuggestion(String title) {
    if (title.length < 3) return null;
    final lower = title.toLowerCase();
    for (final key in _kSuggestions.keys) {
      if (lower.contains(key)) {
        return _kSuggestions[key]!.$3;
      }
    }
    return null;
  }

  DateTime _smartTimeForSuggestion(String suggestion) {
    for (final entry in _kSuggestions.values) {
      if (entry.$3 == suggestion) {
        final now = DateTime.now();
        var dt = DateTime(
            now.year, now.month, now.day, entry.$1, entry.$2);
        if (dt.isBefore(now)) {
          dt = dt.add(const Duration(days: 1));
        }
        return dt;
      }
    }
    return DateTime.now().add(const Duration(hours: 1));
  }

  // ── Add reminder ───────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final titleCtrl = TextEditingController();
    final minutesCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? picked;
    List<DateTime> extraDates = [];
    bool useMinutes = false;
    RepeatDays repeat = RepeatDays.once();
    ReminderPriority priority = ReminderPriority.normal;
    ReminderGeofence? geofence;
    String? groupId;
    String? smartSuggestion;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                const Text('New Reminder',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    )),
                const SizedBox(height: 18),
                _SheetField(
                  controller: titleCtrl,
                  hint: 'Reminder title',
                  icon: CupertinoIcons.bell,
                  onChanged: (v) {
                    final suggestion =
                        _smartTimeSuggestion(v);
                    if (suggestion != smartSuggestion) {
                      ss(() =>
                          smartSuggestion = suggestion);
                    }
                  },
                ),
                // Smart suggestion chip
                if (smartSuggestion != null &&
                    picked == null &&
                    !useMinutes)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () {
                        final t = _smartTimeForSuggestion(
                            smartSuggestion!);
                        ss(() {
                          picked = t;
                          smartSuggestion = null;
                        });
                      },
                      child: Row(children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9F0A)
                                .withOpacity(0.12),
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(
                                        0xFFFF9F0A)
                                    .withOpacity(0.4)),
                          ),
                          child: Row(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                const Text('💡',
                                    style: TextStyle(
                                        fontSize: 12)),
                                const SizedBox(width: 6),
                                Text(smartSuggestion!,
                                    style:
                                        const TextStyle(
                                      color: Color(
                                          0xFFFF9F0A),
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w600,
                                    )),
                                const SizedBox(width: 6),
                                const Text('Tap to use',
                                    style: TextStyle(
                                        color: Color(
                                            0xFFFF9F0A),
                                        fontSize: 11)),
                              ]),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                _TogglePill(
                    useMinutes: useMinutes,
                    onToggle: (v) =>
                        ss(() => useMinutes = v)),
                const SizedBox(height: 12),
                if (useMinutes)
                  _SheetField(
                    controller: minutesCtrl,
                    hint: 'In how many minutes?',
                    icon: CupertinoIcons.timer,
                    keyboardType: TextInputType.number,
                  )
                else if (repeat.isOnce)
                  _MultiDateTimePicker(
                    selected: picked,
                    extraDates: extraDates,
                    onPick: (dt) =>
                        ss(() => picked = dt),
                    onExtraDatesChanged: (dates) =>
                        ss(() => extraDates = dates),
                  )
                else
                  _TimeOnlyPicker(
                    selected: picked,
                    onPick: (dt) =>
                        ss(() => picked = dt),
                  ),
                const SizedBox(height: 16),
                const _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(
                    repeat: repeat,
                    onSelect: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(
                    repeat: repeat,
                    onChanged: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 16),
                const _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(
                    selected: priority,
                    onSelect: (p) =>
                        ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional, Markdown supported)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _GroupPicker(
                  selectedGroupId: groupId,
                  onSelect: (id) =>
                      ss(() => groupId = id),
                ),
                const SizedBox(height: 10),
                _LocationToggle(
                  geofence: geofence,
                  onTap: () async {
                    await showModalBottomSheet(
                      context: ctx,
                      isScrollControlled: true,
                      backgroundColor:
                          Colors.transparent,
                      builder: (_) =>
                          LocationPickerSheet(
                        initial: geofence,
                        onConfirm: (g) =>
                            ss(() => geofence = g),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Add Reminder',
                    () async {
                  final title =
                      titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  DateTime? dt;
                  if (useMinutes) {
                    final mins = int.tryParse(
                        minutesCtrl.text.trim());
                    if (mins == null || mins <= 0)
                      return;
                    dt = DateTime.now()
                        .add(Duration(minutes: mins));
                  } else if (repeat.isRepeating) {
                    if (picked == null) return;
                    dt = repeat.nextOccurrence(picked!);
                  } else {
                    if (picked == null &&
                        geofence == null) return;
                    dt = picked ??
                        DateTime.now().add(
                            const Duration(hours: 1));
                  }
                  final baseId =
                      '${DateTime.now().millisecondsSinceEpoch}';
                  final r = Reminder(
                    id: baseId,
                    title: title,
                    dateTime: dt!,
                    repeat: repeat,
                    priority: priority,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    geofence: geofence,
                    groupId: groupId,
                  );
                  await _svc.add(r);
                  ContinuityService.instance.track(
                      ContinuityActionType.addedReminder,
                      detail: title);
                  if (mounted) {
                    setState(() =>
                        _lastAddedReminderId = baseId);
                  }
                  for (int i = 0;
                      i < extraDates.length;
                      i++) {
                    final extraId =
                        '${DateTime.now().millisecondsSinceEpoch}_$i';
                    final extra = Reminder(
                      id: extraId,
                      title: title,
                      dateTime: extraDates[i],
                      repeat: RepeatDays.once(),
                      priority: priority,
                      notes: notesCtrl.text
                              .trim()
                              .isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                    );
                    await _svc.add(extra);
                  }
                  if (ctx.mounted)
                    Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add with pre-filled date ───────────────────────────────

  Future<void> _showAddDialogForDate(
      DateTime date) async {
    final notesCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    DateTime? picked = DateTime(
        date.year, date.month, date.day, 9, 0);
    RepeatDays repeat = RepeatDays.once();
    ReminderPriority priority = ReminderPriority.normal;
    ReminderGeofence? geofence;
    String? groupId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                const Text('New Reminder',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    )),
                const SizedBox(height: 18),
                _SheetField(
                    controller: titleCtrl,
                    hint: 'Reminder title',
                    icon: CupertinoIcons.bell),
                const SizedBox(height: 12),
                _DateTimePicker(
                    selected: picked,
                    onPick: (dt) =>
                        ss(() => picked = dt)),
                const SizedBox(height: 16),
                const _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(
                    repeat: repeat,
                    onSelect: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(
                    repeat: repeat,
                    onChanged: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 16),
                const _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(
                    selected: priority,
                    onSelect: (p) =>
                        ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional, Markdown supported)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _GroupPicker(
                  selectedGroupId: groupId,
                  onSelect: (id) =>
                      ss(() => groupId = id),
                ),
                const SizedBox(height: 10),
                _LocationToggle(
                  geofence: geofence,
                  onTap: () async {
                    await showModalBottomSheet(
                      context: ctx,
                      isScrollControlled: true,
                      backgroundColor:
                          Colors.transparent,
                      builder: (_) =>
                          LocationPickerSheet(
                        initial: geofence,
                        onConfirm: (g) =>
                            ss(() => geofence = g),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Add Reminder',
                    () async {
                  final title =
                      titleCtrl.text.trim();
                  if (title.isEmpty ||
                      picked == null) return;
                  final id =
                      '${DateTime.now().millisecondsSinceEpoch}';
                  final r = Reminder(
                    id: id,
                    title: title,
                    dateTime: picked!,
                    repeat: repeat,
                    priority: priority,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    geofence: geofence,
                  );
                  await _svc.add(r);
                  if (mounted) {
                    setState(() =>
                        _lastAddedReminderId = id);
                  }
                  if (ctx.mounted)
                    Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── View reminder detail ───────────────────────────────────

  void _showDetailSheet(Reminder r) {
    final diff = r.dateTime.difference(_now);
    final isPast = diff.isNegative;
    final hrs = diff.inHours.abs();
    final mins = diff.inMinutes.abs();
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
        margin:
            const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: SingleChildScrollView(
        padding:
            const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isPast
                          ? const Color(0xFF1E1E1E)
                          : priorityColor
                              .withOpacity(0.14),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: Icon(
                        CupertinoIcons.bell_fill,
                        color: isPast
                            ? Colors.white24
                            : priorityColor,
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4),
                          decoration: BoxDecoration(
                            color: isPast
                                ? Colors.white10
                                : priorityColor
                                    .withOpacity(0.12),
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                              color: isPast
                                  ? Colors.white12
                                  : priorityColor
                                      .withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            countdown,
                            style: TextStyle(
                              color: isPast
                                  ? Colors.white38
                                  : priorityColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('EEE, MMM d · hh:mm a')
                              .format(r.dateTime),
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ]),
            const SizedBox(height: 20),
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
            if (r.notes != null &&
                r.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white10),
                ),
                child: MarkdownBody(
                  data: r.notes!,
                  selectable: true,
                  shrinkWrap: true,
                  extensionSet: md.ExtensionSet(
                    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                    <md.InlineSyntax>[
                      md.EmojiSyntax(),
                      md.AutolinkExtensionSyntax(),
                      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                    ],
                  ),
                  onTapLink: (text, href, title) async {
                    if (href == null) return;
                    final uri = Uri.tryParse(href);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    a: const TextStyle(
                      color: Color(0xFF64D2FF),
                      decoration: TextDecoration.none,
                    ),
                    strong: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    em: const TextStyle(
                      color: Colors.white60,
                      fontStyle: FontStyle.italic,
                    ),
                    code: const TextStyle(
                      color: Color(0xFF64D2FF),
                      backgroundColor: Color(0xFF252525),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(6),
                      border: const Border(
                        left: BorderSide(
                          color: Color(0xFF0A84FF),
                          width: 3,
                        ),
                      ),
                    ),
                    blockquote: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                    listBullet:
                        const TextStyle(color: Colors.white38),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _DetailChip(
                  label: priorityLabel,
                  color: priorityColor),
              if (r.isRepeating)
                _DetailChip(
                    label: r.repeat.label,
                    color: const Color(0xFF0A84FF)),
              if (r.isLocationBased)
                _DetailChip(
                    label: r.geofence!.fullLabel,
                    color: const Color(0xFF30D158)),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditDialog(r);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius:
                          BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white10),
                    ),
                    child: const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.pencil,
                            color: Colors.white70,
                            size: 16),
                        SizedBox(width: 8),
                        Text('Edit',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
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
                    padding: const EdgeInsets.symmetric(
                        vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30)
                          .withOpacity(0.12),
                      borderRadius:
                          BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFFF3B30)
                              .withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.trash,
                            color: Color(0xFFFF3B30),
                            size: 16),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 15,
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
      ),
    );
  }

  // ── Move reminder to group ─────────────────────────────────

  void _showMoveGroupSheet(Reminder reminder) {
    final groups =
        ReminderGroupService.instance.groups.value;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text('Move "${reminder.title}"'),
        message: const Text(
            'Select a group or remove from group'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(context).pop();
              await _svc.update(
                  reminder.copyWith(clearGroup: true));
            },
            child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.tray,
                      size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Text('No Group',
                      style: TextStyle(
                        color: reminder.groupId == null
                            ? const Color(0xFF0A84FF)
                            : Colors.white,
                        fontWeight:
                            reminder.groupId == null
                                ? FontWeight.w700
                                : FontWeight.w400,
                      )),
                ]),
          ),
          ...groups.map((g) =>
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _svc.update(
                      reminder.copyWith(groupId: g.id));
                },
                child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Text(g.emoji,
                          style: const TextStyle(
                              fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(g.name,
                          style: TextStyle(
                            color:
                                reminder.groupId == g.id
                                    ? g.color
                                    : Colors.white,
                            fontWeight:
                                reminder.groupId == g.id
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                          )),
                      if (reminder.groupId == g.id) ...[
                        const SizedBox(width: 6),
                        Icon(
                            CupertinoIcons
                                .checkmark_alt,
                            size: 14,
                            color: g.color),
                      ],
                    ]),
              )),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Edit reminder ──────────────────────────────────────────

  Future<void> _showEditDialog(
      Reminder existing) async {
    final titleCtrl =
        TextEditingController(text: existing.title);
    final notesCtrl = TextEditingController(
        text: existing.notes ?? '');
    DateTime? picked = existing.dateTime;
    RepeatDays repeat = existing.repeat;
    ReminderPriority priority = existing.priority;
    ReminderGeofence? geofence = existing.geofence;
    String? groupId = existing.groupId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom),
          child: _sheetWrap(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 18),
                Row(children: [
                  const Text('Edit Reminder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await _svc.remove(existing.id);
                      if (ctx.mounted)
                        Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30)
                            .withOpacity(0.12),
                        borderRadius:
                            BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFFF3B30)
                                .withOpacity(0.3)),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.trash,
                                color: Color(0xFFFF3B30),
                                size: 13),
                            SizedBox(width: 5),
                            Text('Delete',
                                style: TextStyle(
                                  color:
                                      Color(0xFFFF3B30),
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w600,
                                )),
                          ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _SheetField(
                    controller: titleCtrl,
                    hint: 'Reminder title',
                    icon: CupertinoIcons.bell),
                const SizedBox(height: 12),
                _DateTimePicker(
                    selected: picked,
                    onPick: (dt) =>
                        ss(() => picked = dt)),
                const SizedBox(height: 16),
                const _SectionLabel('Repeat'),
                const SizedBox(height: 8),
                _RepeatPresets(
                    repeat: repeat,
                    onSelect: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 10),
                _DayCheckboxGrid(
                    repeat: repeat,
                    onChanged: (r) =>
                        ss(() => repeat = r)),
                const SizedBox(height: 16),
                const _SectionLabel('Priority'),
                const SizedBox(height: 8),
                _PrioritySelector(
                    selected: priority,
                    onSelect: (p) =>
                        ss(() => priority = p)),
                const SizedBox(height: 12),
                _SheetField(
                  controller: notesCtrl,
                  hint: 'Notes (optional, Markdown supported)',
                  icon: CupertinoIcons.doc_text,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _GroupPicker(
                  selectedGroupId: groupId,
                  onSelect: (id) =>
                      ss(() => groupId = id),
                ),
                const SizedBox(height: 10),
                _LocationToggle(
                  geofence: geofence,
                  onTap: () async {
                    await showModalBottomSheet(
                      context: ctx,
                      isScrollControlled: true,
                      backgroundColor:
                          Colors.transparent,
                      builder: (_) =>
                          LocationPickerSheet(
                        initial: geofence,
                        onConfirm: (g) =>
                            ss(() => geofence = g),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _sheetSaveBtn('Save Changes',
                    () async {
                  final title =
                      titleCtrl.text.trim();
                  if (title.isEmpty ||
                      picked == null) return;
                  final updated = existing.copyWith(
                    title: title,
                    dateTime: picked,
                    repeat: repeat,
                    priority: priority,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    geofence: geofence,
                    clearGeofence: geofence == null,
                    groupId: groupId,
                    clearGroup: groupId == null,
                  );
                  await _svc.update(updated);
                  ContinuityService.instance.track(
                      ContinuityActionType
                          .editedReminder,
                      detail: title);
                  if (ctx.mounted)
                    Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () =>
                    Navigator.of(context).pop(),
                child: const Icon(CupertinoIcons.back,
                    color: Colors.white54, size: 26),
              ),
              const SizedBox(width: 8),
              const Text('Reminders',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  )),
              const Spacer(),
              _TopIconBtn(
                  icon: CupertinoIcons.plus,
                  onTap: _showAddDialog),
              const SizedBox(width: 4),
              _TopIconBtn(
                  icon: CupertinoIcons
                      .ellipsis_vertical,
                  onTap: _showOptionsMenu),
            ]),
          ),
          Expanded(
            child: ValueListenableBuilder<
                List<Reminder>>(
              valueListenable: _svc.reminders,
              builder: (_, reminders, __) =>
                  SingleChildScrollView(
                physics:
                    const BouncingScrollPhysics(),
                child: Column(children: [
                  const SizedBox(height: 16),
                  _ClockCalendarPanel(
                    now: _now,
                    timezoneLabel: _timezoneLabel,
                    onTimezoneTap: _showTimezoneMenu,
                    reminders: reminders,
                    onDateTap: _showAddDialogForDate,
                    lastAddedReminderId:
                        _lastAddedReminderId,
                    onDotBloomDone: () => setState(
                        () =>
                            _lastAddedReminderId =
                                null),
                  ),
                  const SizedBox(height: 20),
                  _PlacesAwarenessPanel(
                    onManagePlaces: () =>
                        showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor:
                          Colors.transparent,
                      builder: (_) =>
                          LocationPickerSheet(
                        onConfirm: (_) {},
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (reminders.isEmpty)
                    _EmptyReminders(
                        onAdd: _showAddDialog)
                  else
                    _GroupedReminderList(
                      reminders: reminders,
                      now: _now,
                      onDelete: (r) =>
                          _svc.remove(r.id),
                      onEdit: _showEditDialog,
                      onViewDetail: _showDetailSheet,
                      onMoveGroup:
                          _showMoveGroupSheet,
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        child: const Icon(CupertinoIcons.plus,
            color: Colors.white, size: 26),
      ),
    );
  }
}