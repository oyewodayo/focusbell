import 'dart:convert';

import 'package:focusbell/models/focus_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../models/settings.dart';
import 'database_helper.dart';

/// Public storage façade used by [AppController].
///
/// - Projects + Tasks  → SQLite via [DatabaseHelper].
/// - [AppSettings]     → SharedPreferences (pure key-value, no relations).
///
/// [AppController] never imports [DatabaseHelper] directly; all SQL details
/// are encapsulated here.
class StorageService {
  static const _settingsKey = 'settings';

  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      final svc = StorageService._();
      svc._prefs = await SharedPreferences.getInstance();
      // Touching `database` here ensures the DB is open (and the one-time
      // SharedPreferences migration runs) before the first caller needs it.
      await DatabaseHelper.instance.database;
      _instance = svc;
    }
    return _instance!;
  }

  // ── Projects ──────────────────────────────────────────────────

  /// Returns all projects with their tasks, ordered by creation date.
  Future<List<Project>> loadProjects() =>
      DatabaseHelper.instance.fetchAllProjects();

  Future<void> saveProject(Project project) =>
      DatabaseHelper.instance.insertProject(project);

  Future<void> updateProject(Project project) =>
      DatabaseHelper.instance.updateProject(project);

  /// Persists the new display order for the full project list.
  Future<void> reorderProjects(List<String> orderedIds) =>
      DatabaseHelper.instance.reorderProjects(orderedIds);

  Future<void> deleteProject(String id) =>
      DatabaseHelper.instance.deleteProject(id);

  /// Atomically clears the active flag on all projects, then sets [id].
  Future<void> setActiveProject(String id) =>
      DatabaseHelper.instance.setActiveProject(id);

  // ── Tasks ─────────────────────────────────────────────────────

  Future<void> saveTask(Task task, String projectId) =>
      DatabaseHelper.instance.insertTask(task, projectId);

  Future<void> updateTask(Task task, String projectId) =>
      DatabaseHelper.instance.updateTask(task, projectId);

  Future<void> deleteTask(String taskId) =>
      DatabaseHelper.instance.deleteTask(taskId);

  // ── Settings ──────────────────────────────────────────────────

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  // ── Focus sessions ────────────────────────────────────────────

  Future<void> saveFocusSession(FocusSession session) async {
    await DatabaseHelper.instance.insertFocusSession(session);
  }

  Future<List<FocusSession>> fetchSessionsForProject(String projectId) async {
    return DatabaseHelper.instance.fetchSessionsForProject(projectId);
  }

  /// Fetches sessions across all (or one) project within [from]..[to].
  Future<List<FocusSession>> fetchSessionsInRange(
    DateTime from,
    DateTime to, {
    String? projectId,
  }) async {
    final all = await DatabaseHelper.instance.fetchSessionsInRange(from, to);
    if (projectId == null) return all;
    return all.where((s) => s.projectId == projectId).toList();
  }
}
