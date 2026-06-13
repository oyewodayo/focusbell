// reminder_service.dart
//
// Supports repeat scheduling. On add, repeating reminders compute their
// next occurrence and re-insert themselves after firing.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/reminder_model.dart';
import 'alarm_service.dart';
import 'database_helper.dart';

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final reminders = ValueNotifier<List<Reminder>>([]);

  bool _ready = false;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await _ensureTable();
    await _load();
    debugPrint(
      '[ReminderService] ready — ${reminders.value.length} reminder(s).',
    );
  }

  // ── Public API ────────────────────────────────────────────────

  Future<void> add(Reminder reminder) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'reminders',
      _toRow(reminder),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await AlarmService.instance.scheduleForReminder(reminder);

    final updated = List<Reminder>.from(reminders.value)..add(reminder);
    updated.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    reminders.value = updated;
    debugPrint(
      '[ReminderService] added "${reminder.title}" '
      '@ ${reminder.dateTime} repeat=${reminder.repeat.name}',
    );
  }

  Future<void> remove(String id) async {
    final idx = reminders.value.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final reminder = reminders.value[idx];

    final db = await DatabaseHelper.instance.database;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);

    await AlarmService.instance.cancelForReminder(reminder);

    reminders.value =
        reminders.value.where((r) => r.id != id).toList();
    debugPrint('[ReminderService] removed "$id"');
  }

  /// Called by AlarmService after a repeating reminder fires —
  /// reschedules the next occurrence automatically.
  Future<void> rescheduleRepeating(Reminder fired) async {
    if (!fired.isRepeating) return;
    final next = fired.nextOccurrence();
    final rescheduled = fired.copyWith(dateTime: next);
    await remove(fired.id);
    await add(rescheduled);
    debugPrint(
      '[ReminderService] rescheduled "${fired.title}" → $next',
    );
  }

  // ── Persistence ───────────────────────────────────────────────

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    // Create with all columns
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id        TEXT PRIMARY KEY,
        title     TEXT NOT NULL,
        date_time TEXT NOT NULL,
        repeat    TEXT NOT NULL DEFAULT 'once',
        priority  TEXT NOT NULL DEFAULT 'normal',
        notes     TEXT
      )
    ''');
    // Migrate existing installs that lack the new columns
    final info = await db.rawQuery("PRAGMA table_info(reminders)");
    final cols = info.map((r) => r['name'] as String).toSet();
    if (!cols.contains('repeat')) {
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN repeat TEXT NOT NULL DEFAULT 'once'");
    }
    if (!cols.contains('priority')) {
      await db.execute(
          "ALTER TABLE reminders ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'");
    }
    if (!cols.contains('notes')) {
      await db.execute("ALTER TABLE reminders ADD COLUMN notes TEXT");
    }
  }

  Future<void> _load() async {
    final db   = await DatabaseHelper.instance.database;
    final rows = await db.query('reminders', orderBy: 'date_time ASC');
    final list = rows.map(_fromRow).toList();
    reminders.value = list;

    for (final r in list) {
      if (!r.isPast) {
        await AlarmService.instance.scheduleForReminder(r);
      }
    }
  }

  // ── Row mappers ───────────────────────────────────────────────

  Map<String, dynamic> _toRow(Reminder r) => {
        'id':        r.id,
        'title':     r.title,
        'date_time': r.dateTime.toIso8601String(),
        'repeat':    r.repeat.name,
        'priority':  r.priority.name,
        'notes':     r.notes,
      };

  Reminder _fromRow(Map<String, dynamic> row) => Reminder(
        id:       row['id']    as String,
        title:    row['title'] as String,
        dateTime: DateTime.parse(row['date_time'] as String),
        repeat: RepeatMode.values.firstWhere(
          (e) => e.name == (row['repeat'] ?? 'once'),
          orElse: () => RepeatMode.once,
        ),
        priority: ReminderPriority.values.firstWhere(
          (e) => e.name == (row['priority'] ?? 'normal'),
          orElse: () => ReminderPriority.normal,
        ),
        notes: row['notes'] as String?,
      );
}