import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:focusbell/models/focus_session.dart';
import 'package:path/path.dart' show join;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/project.dart';

/// Low-level SQLite access.
///
/// [StorageService] is the only caller — nothing else should import this file.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _dbName            = 'focusbell.db';
  static const int    _dbVersion         = 7; // v7: project note columns
  static const String _legacyProjectsKey = 'projects';

  Database? _db;

  // ── Open ──────────────────────────────────────────────────────

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    try {
      final dbsPath = await getDatabasesPath();
      final dbPath  = join(dbsPath, _dbName);
      debugPrint('[DB] Opening database at: $dbPath');

      final db = await openDatabase(
        dbPath,
        version:     _dbVersion,
        onConfigure: _onConfigure,
        onCreate:    _onCreate,
        onUpgrade:   _onUpgrade,
      );

      debugPrint('[DB] Database opened successfully (version $_dbVersion).');
      await _migrateFromSharedPreferences(db);
      return db;
    } catch (e, stack) {
      debugPrint('[DB] FATAL: Failed to open database.\n$e\n$stack');
      rethrow;
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[DB] Creating schema (v$version)...');

    await db.execute('''
      CREATE TABLE projects (
        id              TEXT    PRIMARY KEY,
        name            TEXT    NOT NULL,
        description     TEXT    NOT NULL DEFAULT '',
        priority        INTEGER NOT NULL,
        is_active       INTEGER NOT NULL DEFAULT 0,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        is_archived     INTEGER NOT NULL DEFAULT 0,
        note            TEXT,
        note_updated_at TEXT,
        created_at      TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id              TEXT    PRIMARY KEY,
        project_id      TEXT    NOT NULL
                                REFERENCES projects(id) ON DELETE CASCADE,
        title           TEXT    NOT NULL,
        status          INTEGER NOT NULL DEFAULT 0,
        due_date        TEXT,
        note            TEXT,
        note_updated_at TEXT,
        created_at      TEXT    NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_tasks_project_id ON tasks(project_id)');
    await db.execute('CREATE INDEX idx_projects_is_active ON projects(is_active)');

    await db.execute('''
      CREATE TABLE focus_sessions (
        id              TEXT    PRIMARY KEY,
        project_id      TEXT    NOT NULL
                                REFERENCES projects(id) ON DELETE CASCADE,
        type            INTEGER NOT NULL,
        preset          INTEGER NOT NULL,
        started_at      TEXT    NOT NULL,
        ended_at        TEXT    NOT NULL,
        planned_seconds INTEGER NOT NULL,
        actual_seconds  INTEGER NOT NULL,
        completed       INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_focus_sessions_project_id ON focus_sessions(project_id)',
    );
    await db.execute(
      'CREATE INDEX idx_focus_sessions_started_at ON focus_sessions(started_at)',
    );

    debugPrint('[DB] Schema created.');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[DB] Upgrading schema from v$oldVersion to v$newVersion...');

    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE projects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );
      final rows = await db.query('projects',
          columns: ['id'], orderBy: 'created_at ASC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('projects', {'sort_order': i},
            where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
      debugPrint('[DB] Migration v2: sort_order added and seeded.');
    }

    if (oldVersion < 3) {
      await db.execute('ALTER TABLE tasks ADD COLUMN due_date TEXT');
      debugPrint('[DB] Migration v3: due_date column added to tasks.');
    }

    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE projects ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0',
      );
      debugPrint('[DB] Migration v4: is_archived column added to projects.');
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS focus_sessions (
          id              TEXT    PRIMARY KEY,
          project_id      TEXT    NOT NULL
                                  REFERENCES projects(id) ON DELETE CASCADE,
          type            INTEGER NOT NULL,
          preset          INTEGER NOT NULL,
          started_at      TEXT    NOT NULL,
          ended_at        TEXT    NOT NULL,
          planned_seconds INTEGER NOT NULL,
          actual_seconds  INTEGER NOT NULL,
          completed       INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_focus_sessions_project_id ON focus_sessions(project_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_focus_sessions_started_at ON focus_sessions(started_at)',
      );
      debugPrint('[DB] Migration v5: focus_sessions table created.');
    }

    if (oldVersion < 6) {
      await db.execute('ALTER TABLE tasks ADD COLUMN note TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN note_updated_at TEXT');
      debugPrint('[DB] Migration v6: note columns added to tasks.');
    }

    if (oldVersion < 7) {
      await db.execute('ALTER TABLE projects ADD COLUMN note TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN note_updated_at TEXT');
      debugPrint('[DB] Migration v7: note columns added to projects.');
    }
  }

  // ── Focus sessions ────────────────────────────────────────────

  Future<void> insertFocusSession(FocusSession session) async {
    final db = await database;
    await db.insert(
      'focus_sessions',
      {
        'id':              session.id,
        'project_id':      session.projectId,
        'type':            session.type.index,
        'preset':          session.preset.index,
        'started_at':      session.startedAt.toIso8601String(),
        'ended_at':        session.endedAt.toIso8601String(),
        'planned_seconds': session.plannedSeconds,
        'actual_seconds':  session.actualSeconds,
        'completed':       session.completed ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[DB] insertFocusSession: ${session.id} (${session.actualSeconds}s)');
  }

  Future<List<FocusSession>> fetchSessionsForProject(String projectId) async {
    final db   = await database;
    final rows = await db.query(
      'focus_sessions',
      where:     'project_id = ?',
      whereArgs: [projectId],
      orderBy:   'started_at DESC',
    );
    return rows.map(_rowToSession).toList();
  }

  Future<List<FocusSession>> fetchSessionsInRange(
      DateTime from, DateTime to) async {
    final db   = await database;
    final rows = await db.query(
      'focus_sessions',
      where:     'started_at >= ? AND started_at < ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy:   'started_at ASC',
    );
    return rows.map(_rowToSession).toList();
  }

  Future<void> deleteSessionsForProject(String projectId) async {
    final db    = await database;
    final count = await db.delete(
      'focus_sessions',
      where:     'project_id = ?',
      whereArgs: [projectId],
    );
    debugPrint('[DB] deleteSessionsForProject: $projectId — $count deleted.');
  }

  FocusSession _rowToSession(Map<String, dynamic> row) => FocusSession(
        id:             row['id']              as String,
        projectId:      row['project_id']      as String,
        type:           SessionType.values[row['type']   as int],
        preset:         TimerPreset.values[row['preset'] as int],
        startedAt:      DateTime.parse(row['started_at'] as String),
        endedAt:        DateTime.parse(row['ended_at']   as String),
        plannedSeconds: row['planned_seconds'] as int,
        actualSeconds:  row['actual_seconds']  as int,
        completed:      (row['completed'] as int) == 1,
      );

  // ── SharedPreferences migration ───────────────────────────────

  Future<void> _migrateFromSharedPreferences(Database db) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[DB] Migration: could not open SharedPreferences — skipping. $e');
      return;
    }

    final raw = prefs.getString(_legacyProjectsKey);
    if (raw == null) {
      debugPrint('[DB] Migration: no legacy data found — clean install.');
      return;
    }

    debugPrint('[DB] Migration: found legacy SharedPreferences data, migrating...');

    try {
      final list     = jsonDecode(raw) as List<dynamic>;
      final projects = list
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();

      await db.transaction((txn) async {
        for (final project in projects) {
          final existing = await txn.query(
            'projects',
            columns:   ['id'],
            where:     'id = ?',
            whereArgs: [project.id],
            limit:     1,
          );
          if (existing.isNotEmpty) {
            debugPrint('[DB] Migration: project ${project.id} already exists, skipping.');
            continue;
          }

          await txn.insert('projects', _projectToRow(project));
          for (final task in project.tasks) {
            await txn.insert('tasks', _taskToRow(task, project.id));
          }
          debugPrint('[DB] Migration: inserted "${project.name}" with ${project.tasks.length} tasks.');
        }
      });

      await prefs.remove(_legacyProjectsKey);
      debugPrint('[DB] Migration: completed and legacy key removed.');
    } catch (e, stack) {
      debugPrint('[DB] Migration FAILED — will retry on next boot.\n$e\n$stack');
    }
  }

  // ── Projects ──────────────────────────────────────────────────

  Future<List<Project>> fetchAllProjects() async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT
        p.id              AS p_id,
        p.name            AS p_name,
        p.description     AS p_description,
        p.priority        AS p_priority,
        p.is_active       AS p_is_active,
        p.sort_order      AS p_sort_order,
        p.is_archived     AS p_is_archived,
        p.note            AS p_note,
        p.note_updated_at AS p_note_updated_at,
        p.created_at      AS p_created_at,
        t.id              AS t_id,
        t.title           AS t_title,
        t.status          AS t_status,
        t.due_date        AS t_due_date,
        t.note            AS t_note,
        t.note_updated_at AS t_note_updated_at,
        t.created_at      AS t_created_at
      FROM projects p
      LEFT JOIN tasks t ON t.project_id = p.id
      ORDER BY p.sort_order ASC, t.created_at ASC
    ''');

    debugPrint('[DB] fetchAllProjects: ${rows.length} rows returned.');
    return _rowsToProjects(rows);
  }

  Future<void> insertProject(Project project) async {
    final db = await database;
    await db.insert('projects', _projectToRow(project),
        conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint('[DB] insertProject: "${project.name}"');
  }

  Future<void> updateProject(Project project) async {
    final db    = await database;
    final count = await db.update(
      'projects',
      _projectToRow(project),
      where:     'id = ?',
      whereArgs: [project.id],
    );
    debugPrint('[DB] updateProject: "${project.name}" — $count row(s) affected.');
  }

  Future<void> deleteProject(String id) async {
    final db    = await database;
    final count = await db.delete('projects',
        where: 'id = ?', whereArgs: [id]);
    debugPrint('[DB] deleteProject: $id — $count row(s) deleted (cascade removes tasks).');
  }

  Future<void> setActiveProject(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('projects', {'is_active': 0});
      await txn.update('projects', {'is_active': 1},
          where: 'id = ?', whereArgs: [id]);
    });
    debugPrint('[DB] setActiveProject: $id');
  }

  // ── Tasks ─────────────────────────────────────────────────────

  Future<void> insertTask(Task task, String projectId) async {
    final db = await database;
    await db.insert('tasks', _taskToRow(task, projectId),
        conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint('[DB] insertTask: "${task.title}" → project $projectId');
  }

  Future<void> updateTask(Task task, String projectId) async {
    final db    = await database;
    final count = await db.update(
      'tasks',
      _taskToRow(task, projectId),
      where:     'id = ?',
      whereArgs: [task.id],
    );
    debugPrint('[DB] updateTask: "${task.title}" — $count row(s) affected.');
  }

  Future<void> deleteTask(String taskId) async {
    final db    = await database;
    final count = await db.delete('tasks',
        where: 'id = ?', whereArgs: [taskId]);
    debugPrint('[DB] deleteTask: $taskId — $count row(s) deleted.');
  }

  /// Efficient note-only update — only touches the two note columns.
  Future<void> updateTaskNote(String taskId, String? note) async {
    final db = await database;
    await db.update(
      'tasks',
      {
        'note':            note,
        'note_updated_at': note != null
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      },
      where:     'id = ?',
      whereArgs: [taskId],
    );
    debugPrint('[DB] updateTaskNote: $taskId — ${note == null ? "cleared" : "saved"}');
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update('projects', {'sort_order': i},
            where: 'id = ?', whereArgs: [orderedIds[i]]);
      }
    });
    debugPrint('[DB] reorderProjects: ${orderedIds.length} projects reordered.');
  }

  // ── Row mappers ───────────────────────────────────────────────

  Map<String, dynamic> _projectToRow(Project proj) => {
        'id':              proj.id,
        'name':            proj.name,
        'description':     proj.description,
        'priority':        proj.priority.index,
        'is_active':       proj.isActive   ? 1 : 0,
        'is_archived':     proj.isArchived ? 1 : 0,
        'sort_order':      proj.sortOrder,
        'created_at':      proj.createdAt.toIso8601String(),
        'note':            proj.note,
        'note_updated_at': proj.noteUpdatedAt?.toIso8601String(),
      };

  Map<String, dynamic> _taskToRow(Task t, String projectId) => {
        'id':              t.id,
        'project_id':      projectId,
        'title':           t.title,
        'status':          t.status.index,
        'due_date':        t.dueDate?.toIso8601String(),
        'note':            t.note,
        'note_updated_at': t.noteUpdatedAt?.toIso8601String(),
        'created_at':      t.createdAt.toIso8601String(),
      };

  List<Project> _rowsToProjects(List<Map<String, dynamic>> rows) {
    final Map<String, _ProjectBuilder> projectMap = {};

    for (final row in rows) {
      final projectId = row['p_id'] as String;

      projectMap.putIfAbsent(
        projectId,
        () => _ProjectBuilder(
          id:            projectId,
          name:          row['p_name']        as String,
          description:   row['p_description'] as String,
          priority:      Priority.values[row['p_priority'] as int],
          isActive:      (row['p_is_active']  as int) == 1,
          isArchived:    (row['p_is_archived'] as int? ?? 0) == 1,
          sortOrder:     row['p_sort_order']  as int,
          createdAt:     DateTime.parse(row['p_created_at'] as String),
          note:          row['p_note'] as String?,
          noteUpdatedAt: (row['p_note_updated_at'] as String?) == null
              ? null
              : DateTime.tryParse(row['p_note_updated_at'] as String),
        ),
      );

      final taskId = row['t_id'];
      if (taskId != null) {
        projectMap[projectId]!.tasks.add(Task(
          id:            taskId as String,
          title:         row['t_title']  as String,
          status:        TaskStatus.values[row['t_status'] as int],
          createdAt:     DateTime.parse(row['t_created_at'] as String),
          dueDate:       (row['t_due_date'] as String?) == null
              ? null
              : DateTime.tryParse(row['t_due_date'] as String),
          note:          row['t_note'] as String?,
          noteUpdatedAt: (row['t_note_updated_at'] as String?) == null
              ? null
              : DateTime.tryParse(row['t_note_updated_at'] as String),
        ));
      }
    }

    return projectMap.values.map((b) => b.build()).toList();
  }

  // ── Dispose ───────────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
    debugPrint('[DB] Database closed.');
  }
}

// ── Internal accumulator ──────────────────────────────────────────

class _ProjectBuilder {
  final String     id;
  final String     name;
  final String     description;
  final Priority   priority;
  final bool       isActive;
  final bool       isArchived;
  final int        sortOrder;
  final DateTime   createdAt;
  final String?    note;
  final DateTime?  noteUpdatedAt;
  final List<Task> tasks = [];

  _ProjectBuilder({
    required this.id,
    required this.name,
    required this.description,
    required this.priority,
    required this.isActive,
    required this.isArchived,
    required this.sortOrder,
    required this.createdAt,
    this.note,
    this.noteUpdatedAt,
  });

  Project build() => Project(
        id:            id,
        name:          name,
        description:   description,
        priority:      priority,
        isActive:      isActive,
        isArchived:    isArchived,
        sortOrder:     sortOrder,
        createdAt:     createdAt,
        tasks:         List.unmodifiable(tasks),
        note:          note,
        noteUpdatedAt: noteUpdatedAt,
      );
}