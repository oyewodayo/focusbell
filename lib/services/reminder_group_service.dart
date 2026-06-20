// services/reminder_group_service.dart — NEW FILE

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder_group.dart';
import 'database_helper.dart';

class ReminderGroupService {
  ReminderGroupService._();
  static final ReminderGroupService instance = ReminderGroupService._();

  final groups = ValueNotifier<List<ReminderGroup>>([]);
  bool _ready = false;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await _ensureTable();
    await _seedDefaults();
    await _load();
    debugPrint('[GroupService] ready — ${groups.value.length} group(s).');
  }

  // ── CRUD ──────────────────────────────────────────────────────

  Future<ReminderGroup> add({
    required String name,
    required Color  color,
    required String emoji,
  }) async {
    final g = ReminderGroup(
      id:        const Uuid().v4(),
      name:      name,
      color:     color,
      emoji:     emoji,
      sortOrder: groups.value.length,
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('reminder_groups', g.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    groups.value = [...groups.value, g];
    return g;
  }

  Future<void> update(ReminderGroup g) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('reminder_groups', g.toRow(),
        where: 'id = ?', whereArgs: [g.id]);
    groups.value = groups.value.map((e) => e.id == g.id ? g : e).toList();
  }

  Future<void> remove(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('reminder_groups', where: 'id = ?', whereArgs: [id]);
    // Ungroup all reminders that were in this group
    await db.update('reminders', {'group_id': null},
        where: 'group_id = ?', whereArgs: [id]);
    groups.value = groups.value.where((g) => g.id != id).toList();
  }

  // ── Lookup ────────────────────────────────────────────────────

  ReminderGroup? findById(String? id) {
    if (id == null) return null;
    try {
      return groups.value.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── DB ────────────────────────────────────────────────────────

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminder_groups (
        id         TEXT PRIMARY KEY,
        name       TEXT NOT NULL,
        color_hex  TEXT NOT NULL DEFAULT 'ff0a84ff',
        emoji      TEXT NOT NULL DEFAULT '📁',
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _seedDefaults() async {
    final db   = await DatabaseHelper.instance.database;
    final rows = await db.query('reminder_groups', limit: 1);
    if (rows.isNotEmpty) return;
    for (final g in ReminderGroup.defaults) {
      await db.insert('reminder_groups', g.toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    debugPrint('[GroupService] seeded defaults.');
  }

  Future<void> _load() async {
    final db   = await DatabaseHelper.instance.database;
    final rows = await db.query('reminder_groups', orderBy: 'sort_order ASC');
    groups.value = rows.map(ReminderGroup.fromRow).toList();
  }
}