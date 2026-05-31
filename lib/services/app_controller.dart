import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../models/settings.dart';
import 'foreground_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Application state manager.
///
/// Owns the in-memory project list and delegates all persistence to
/// [StorageService]. UI widgets listen via [ChangeNotifier].
///
/// Design rules:
///   - Every mutating method updates [_projects] optimistically in memory
///     first, then persists to SQLite, then calls [notifyListeners].
///   - [StorageService] (and through it [DatabaseHelper]) is the only
///     persistence boundary — no SQL leaks into this class.
class AppController extends ChangeNotifier {
  AppController._();
  static final AppController instance = AppController._();

  late StorageService _storage;
  List<Project> _projects = [];
  AppSettings   _settings = const AppSettings();
  bool          _loading  = true;

  List<Project>  get projects => _projects;
  AppSettings    get settings => _settings;
  bool           get loading  => _loading;

  Project? get activeProject =>
      _projects.where((p) => p.isActive).firstOrNull;

  // ── Boot ──────────────────────────────────────────────────────

  // Exposed so the UI can display the error instead of hanging forever.
  Object? bootError;

  Future<void> boot() async {
    try {
      _storage  = await StorageService.getInstance();
      _projects = await _storage.loadProjects();
      _settings = _storage.loadSettings();
    } catch (e, stack) {
      debugPrint('[AppController] boot() failed:\n$e\n$stack');
      bootError = e;
      _loading  = false;
      notifyListeners();
      return;
    }

    _loading = false;
    notifyListeners();

    ForegroundServiceManager.instance.configure(_settings);
    await rescheduleIfNeeded();
  }

  // ── Projects ──────────────────────────────────────────────────

  Future<void> addProject(
    String name,
    Priority priority,
    String description,
  ) async {
    final project = Project(
      id:          const Uuid().v4(),
      name:        name,
      description: description,
      priority:    priority,
      createdAt:   DateTime.now(),
    );
    _projects = [..._projects, project];
    notifyListeners();
    await _storage.saveProject(project);
  }

 Future<void> setActive(String id) async {
  // Move newly active project to position 0 in sort_order.
  final reordered = [
    _projects.firstWhere((p) => p.id == id),
    ..._projects.where((p) => p.id != id),
  ];

  _projects = reordered
      .asMap()
      .entries
      .map((e) => e.value.copyWith(
            isActive: e.value.id == id,
            sortOrder: e.key,
          ))
      .toList();
  notifyListeners();

  await _storage.setActiveProject(id);
  // Persist the new order so it survives restarts.
  await _storage.reorderProjects(reordered.map((p) => p.id).toList());

  final active = activeProject;
  if (active != null && _settings.notificationsEnabled) {
    await NotificationService.instance
        .showInstant(active, soundMode: _settings.soundMode);
    await ForegroundServiceManager.instance.startOrUpdate(active, _settings);
  }
}

  Future<void> removeProject(String id) async {
    final wasActive = _projects.firstWhere((p) => p.id == id).isActive;
    _projects = _projects.where((p) => p.id != id).toList();

    if (wasActive && _projects.isNotEmpty) {
      // Promote the first remaining project to active.
      final promoted = _projects.first.copyWith(isActive: true);
      _projects = [promoted, ..._projects.skip(1)];
      await _storage.setActiveProject(promoted.id);
    }

    notifyListeners();
    // ON DELETE CASCADE in SQLite removes child tasks automatically.
    await _storage.deleteProject(id);
    await rescheduleIfNeeded();
  }

  Future<void> updateProject(
    String id, {
    required String   name,
    required String   description,
    required Priority priority,
  }) async {
    _projects = _projects.map((p) {
      if (p.id != id) return p;
      return p.copyWith(name: name, description: description, priority: priority);
    }).toList();
    notifyListeners();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage.updateProject(updated);

    if (activeProject?.id == id) {
      await ForegroundServiceManager.instance
          .updateData(activeProject!, _settings);
    }
  }

  Future<void> updateProjectPriority(String id, Priority priority) async {
    _projects = _projects
        .map((p) => p.id == id ? p.copyWith(priority: priority) : p)
        .toList();
    notifyListeners();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage.updateProject(updated);

    if (activeProject?.id == id) await rescheduleIfNeeded();
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    // Reorder in-memory list to match.
    final map = {for (final p in _projects) p.id: p};
    _projects = orderedIds
        .where(map.containsKey)
        .map((id) => map[id]!.copyWith(sortOrder: orderedIds.indexOf(id)))
        .toList();
    notifyListeners();
    await _storage.reorderProjects(orderedIds);
  }

  // ── Tasks ─────────────────────────────────────────────────────

  /// Returns the live in-memory project, or null.
  Project? findProject(String projectId) =>
      _projects.where((p) => p.id == projectId).firstOrNull;

  Future<void> addTask(String projectId, String title) async {
    final task = Task(
      id:        const Uuid().v4(),
      title:     title,
      status:    TaskStatus.todo,
      createdAt: DateTime.now(),
    );

    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(tasks: [...p.tasks, task]);
    }).toList();
    notifyListeners();

    await _storage.saveTask(task, projectId);
  }

  Future<void> updateTask(
    String projectId,
    String taskId, {
    String?     title,
    TaskStatus? status,
  }) async {
    Task? updated;

    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
        tasks: p.tasks.map((t) {
          if (t.id != taskId) return t;
          updated = t.copyWith(title: title, status: status);
          return updated!;
        }).toList(),
      );
    }).toList();
    notifyListeners();

    if (updated != null) {
      await _storage.updateTask(updated!, projectId);
    }
  }

  Future<void> removeTask(String projectId, String taskId) async {
    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
          tasks: p.tasks.where((t) => t.id != taskId).toList());
    }).toList();
    notifyListeners();

    await _storage.deleteTask(taskId);
  }

  // ── Settings ──────────────────────────────────────────────────

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _storage.saveSettings(s);
    notifyListeners();
    await rescheduleIfNeeded();
  }

  // ── Foreground service ─────────────────────────────────────────

  Future<void> rescheduleIfNeeded() async {
    final active = activeProject;
    if (active == null || !_settings.notificationsEnabled) {
      await ForegroundServiceManager.instance.stop();
    } else {
      await ForegroundServiceManager.instance.startOrUpdate(active, _settings);
    }
  }
}