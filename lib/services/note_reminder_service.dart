// ─────────────────────────────────────────────────────────────────────────────
// services/note_reminder_service.dart
//
// Persists a single DateTime reminder per note (project or standalone).
// Keyed by the note/project ID. Backed by a single SQLite table.
//
// Usage:
//   final dt = await NoteReminderService.instance.get(noteId);
//   await NoteReminderService.instance.set(noteId, dateTime);
//   await NoteReminderService.instance.clear(noteId);
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class NoteReminderService {
  NoteReminderService._();
  static final instance = NoteReminderService._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'note_reminders.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE note_reminders (
          note_id   TEXT PRIMARY KEY,
          remind_at TEXT NOT NULL
        )
      '''),
    );
    return _db!;
  }

  /// Returns the scheduled reminder for [noteId], or null if none is set.
  Future<DateTime?> get(String noteId) async {
    final db = await _database;
    final rows = await db.query(
      'note_reminders',
      where: 'note_id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['remind_at'] as String);
  }

  /// Persists (or replaces) the reminder for [noteId].
  Future<void> set(String noteId, DateTime remindAt) async {
    final db = await _database;
    await db.insert(
      'note_reminders',
      {'note_id': noteId, 'remind_at': remindAt.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the reminder for [noteId].
  Future<void> clear(String noteId) async {
    final db = await _database;
    await db.delete(
      'note_reminders',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
  }
}