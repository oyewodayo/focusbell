// services/reminder_service.dart — FULL REPLACEMENT
// Adds GeofenceService wiring alongside existing alarm scheduling

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:focusbell/services/app_controller.dart';
import 'package:focusbell/services/continuity_service.dart';
import 'package:sqflite/sqflite.dart';

import '../models/reminder_model.dart';
import '../models/settings.dart';
import 'alarm_service.dart';
import 'database_helper.dart';
import 'geofence_service.dart';
import 'reminder_group_service.dart';

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final reminders = ValueNotifier<List<Reminder>>([]);
  bool _ready = false;
  Timer? _sweepTimer;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await _ensureTable();
    await _load();
    // Boot geofence service after reminders are loaded so it can poll
    await GeofenceService.instance.init();
    await sweepAutoDelete();
    _sweepTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => sweepAutoDelete());
    debugPrint('[ReminderService] ready — ${reminders.value.length} reminder(s).');
  }

  /// Removes reminders whose due time has passed by at least the grace
  /// period configured in Settings (`AppSettings.reminderAutoDelete`).
  /// Repeating reminders are never swept — they're rescheduled instead.
  /// When the setting is `manual` (the default), this is a no-op: reminders
  /// only ever go away when the user deletes them.
  Future<void> sweepAutoDelete() async {
    final graceMinutes = AppController.instance.settings.reminderAutoDelete.minutes;
    if (graceMinutes == null) return;

    final now = DateTime.now();
    final expired = reminders.value.where((r) =>
        !r.isRepeating &&
        r.isPast &&
        now.difference(r.dateTime).inMinutes >= graceMinutes).toList();

    for (final r in expired) {
      await remove(r.id);
    }
    if (expired.isNotEmpty) {
      debugPrint('[ReminderService] auto-deleted ${expired.length} passed reminder(s).');
    }
  }

  void dispose() => _sweepTimer?.cancel();

  Future<void> add(Reminder reminder) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('reminders', _toRow(reminder),
        conflictAlgorithm: ConflictAlgorithm.replace);

    ContinuityService.instance.track(
        ContinuityActionType.addedReminder, detail: reminder.title);
    // Schedule alarm only for time-based reminders
    if (!reminder.isLocationBased) {
      await AlarmService.instance.scheduleForReminder(reminder);
    }

    final updated = List<Reminder>.from(reminders.value)..add(reminder);
    updated.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    reminders.value = updated;
    debugPrint('[ReminderService] added "${reminder.title}" '
        'geo=${reminder.isLocationBased}');
  }

  Future<void> remove(String id) async {
    final idx = reminders.value.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final reminder = reminders.value[idx];

    final db = await DatabaseHelper.instance.database;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);

    if (!reminder.isLocationBased) {
      await AlarmService.instance.cancelForReminder(reminder);
    }
    GeofenceService.instance.removeGeofence(id);

    reminders.value = reminders.value.where((r) => r.id != id).toList();
    ContinuityService.instance.track(                              // ← ADD
        ContinuityActionType.deletedReminder, detail: reminder.title);
    debugPrint('[ReminderService] removed "$id"');
  }

  Future<void> update(Reminder updated) async {
    final idx = reminders.value.indexWhere((r) => r.id == updated.id);
    if (idx == -1) return;
    final old = reminders.value[idx];

    final db = await DatabaseHelper.instance.database;
    await db.update('reminders', _toRow(updated),
        where: 'id = ?', whereArgs: [updated.id]);

    // Cancel old alarm if it was time-based
    if (!old.isLocationBased) {
      await AlarmService.instance.cancelForReminder(old);
    }
    // Schedule new alarm if now time-based
    if (!updated.isLocationBased && !updated.isPast) {
      await AlarmService.instance.scheduleForReminder(updated);
    }
    // Clear geofence inside-state if geofence was removed
    if (old.geofence != null && updated.geofence == null) {
      GeofenceService.instance.removeGeofence(updated.id);
    }

    ContinuityService.instance.track(
      ContinuityActionType.editedReminder, detail: updated.title);

    final list = List<Reminder>.from(reminders.value);
    list[idx] = updated;
    list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    reminders.value = list;
    debugPrint('[ReminderService] updated "${updated.title}"');
  }

  Future<void> snoozeAll(List<Reminder> toSnooze, Duration by) async {
    for (final r in toSnooze) {
      final snoozed = r.copyWith(dateTime: DateTime.now().add(by));
      await update(snoozed);
    }
    debugPrint('[ReminderService] snoozed ${toSnooze.length} '
        'reminder(s) +${by.inMinutes} min.');
  }

  Future<void> rescheduleRepeating(Reminder fired) async {
    if (!fired.isRepeating) return;
    final next        = fired.nextOccurrence();
    final rescheduled = fired.copyWith(dateTime: next);
    await remove(fired.id);
    await add(rescheduled);
    debugPrint('[ReminderService] rescheduled "${fired.title}" → $next');
  }

  // ── DB ────────────────────────────────────────────────────────

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id        TEXT PRIMARY KEY,
        title     TEXT NOT NULL,
        date_time TEXT NOT NULL,
        repeat    TEXT NOT NULL DEFAULT '',
        priority  TEXT NOT NULL DEFAULT 'normal',
        notes     TEXT,
        geofence  TEXT,
        group_id  TEXT
      )
    ''');
    final info = await db.rawQuery('PRAGMA table_info(reminders)');
    final cols = info.map((r) => r['name'] as String).toSet();
    if (!cols.contains('repeat'))
      await db.execute("ALTER TABLE reminders ADD COLUMN repeat TEXT NOT NULL DEFAULT ''");
    if (!cols.contains('priority'))
      await db.execute("ALTER TABLE reminders ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'");
    if (!cols.contains('notes'))
      await db.execute("ALTER TABLE reminders ADD COLUMN notes TEXT");
    if (!cols.contains('geofence'))
      await db.execute("ALTER TABLE reminders ADD COLUMN geofence TEXT");
    if (!cols.contains('group_id'))
      await db.execute("ALTER TABLE reminders ADD COLUMN group_id TEXT");
  }

  Future<void> _load() async {
    final db   = await DatabaseHelper.instance.database;
    final rows = await db.query('reminders', orderBy: 'date_time ASC');
    final list = rows.map(_fromRow).toList();
    reminders.value = list;
    for (final r in list) {
      if (!r.isLocationBased && !r.isPast) {
        await AlarmService.instance.scheduleForReminder(r);
      }
    }
  }

  Map<String, dynamic> _toRow(Reminder r) => {
    'id':        r.id,
    'title':     r.title,
    'date_time': r.dateTime.toIso8601String(),
    'repeat':    r.repeat.toStorageString(),
    'priority':  r.priority.name,
    'notes':     r.notes,
    'geofence':  r.geofence != null
        ? jsonEncode(r.geofence!.toJson())
        : null,
    'group_id':  r.groupId,
  };

  Reminder _fromRow(Map<String, dynamic> row) {
    final geoRaw = row['geofence'] as String?;
    return Reminder(
      id:       row['id']    as String,
      title:    row['title'] as String,
      dateTime: DateTime.parse(row['date_time'] as String),
      repeat:   RepeatDays.fromStorage(row['repeat'] as String?),
      priority: ReminderPriority.values.firstWhere(
        (e) => e.name == (row['priority'] ?? 'normal'),
        orElse: () => ReminderPriority.normal,
      ),
      notes:    row['notes'] as String?,
      geofence: geoRaw != null
          ? ReminderGeofence.fromJson(
              jsonDecode(geoRaw) as Map<String, dynamic>)
          : null,
      groupId: row['group_id'] as String?,
    );
  }
}