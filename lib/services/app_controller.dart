// lib/services/app_controller.dart
//
// Changes vs previous version:
//   • import widget_service.dart
//   • private _pushWidget() helper added at bottom
//   • _pushWidget() called after notifyListeners() in every mutating method
//   • WidgetService.instance.init() called inside boot() after storage loads
//   • boot() pushes widget after _loading = false so cold-start widget is correct

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../models/settings.dart';
import 'foreground_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'widget_service.dart'; // ← NEW

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
///   - After every [notifyListeners()] call, [_pushWidget()] syncs the
///     Android home-screen / lock-screen widget with the latest state.
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

  // ── Boot ──────────────────────────────────────────────────────────────────

  // Exposed so the UI can display the error instead of hanging forever.
  Object? bootError;

  Future<void> boot() async {
    try {
      _storage  = await StorageService.getInstance();
      _projects = await _storage.loadProjects();
      _settings = _storage.loadSettings();

      // Init widget bridge early so the first push() below works.
      await WidgetService.instance.init(); // ← NEW
    } catch (e, stack) {
      debugPrint('[AppController] boot() failed:\n$e\n$stack');
      bootError = e;
      _loading  = false;
      notifyListeners();
      return;
    }

    _loading = false;
    notifyListeners();

    // Sync the widget immediately after boot so it reflects the current
    // active project even if the user hasn't interacted with the app yet.
    _pushWidget(); // ← NEW

    ForegroundServiceManager.instance.configure(_settings);
    await rescheduleIfNeeded();
  }

  // ── Projects ──────────────────────────────────────────────────────────────

  Future<void> addProject(
    String name,
    Priority priority,
    String description,
    ProjectCategory category,
  ) async {
    final project = Project(
      id:          const Uuid().v4(),
      name:        name,
      description: description,
      priority:    priority,
      category:    category,
      createdAt:   DateTime.now(),
    );
    _projects = [..._projects, project];
    notifyListeners();
    // No _pushWidget() here: adding a project doesn't change the active one,
    // so the widget content is unchanged. If the first-ever project should
    // auto-activate in your flow, add _pushWidget() after that logic instead.
    await _storage.saveProject(project);
  }

  Future<void> setActive(String id) async {
    final List<Project> reordered = [
      _projects.firstWhere((p) => p.id == id),
      ..._projects.where((p) => p.id != id),
    ];

    _projects = reordered
        .asMap()
        .entries
        .map((e) => e.value.copyWith(
              isActive:  e.value.id == id,
              sortOrder: e.key,
            ))
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget(); // ← NEW — active project changed; widget must update

    await _storage.setActiveProject(id);
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
    _pushWidget(); // ← NEW — active project may have changed or cleared

    await _storage.deleteProject(id); // CASCADE removes child tasks
    await rescheduleIfNeeded();
  }

  Future<void> archiveProject(String id) async {
    _projects = _projects
        .map((p) =>
            p.id == id ? p.copyWith(isArchived: true, isActive: false) : p)
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget(); // ← NEW — archived project can no longer be active

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage.updateProject(updated);
    await rescheduleIfNeeded();
  }

  Future<void> unarchiveProject(String id) async {
    _projects = _projects
        .map((p) => p.id == id ? p.copyWith(isArchived: false) : p)
        .toList()
        .cast<Project>();
    notifyListeners();
    // No active-project change here, but the project list changed;
    // push anyway so task_summary stays consistent if it was active before.
    _pushWidget(); // ← NEW

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage.updateProject(updated);
  }

  Future<void> updateProject(
    String id, {
    required String   name,
    required String   description,
    required Priority priority,
    required ProjectCategory category,
  }) async {
    _projects = _projects.map((p) {
      if (p.id != id) return p;
      return p.copyWith(name: name, description: description, priority: priority, category: category);
    }).toList().cast<Project>();
    notifyListeners();
    _pushWidget(); // ← NEW — name / priority shown in widget may have changed

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
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget(); // ← NEW — priority dot in widget must update

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage.updateProject(updated);

    if (activeProject?.id == id) await rescheduleIfNeeded();
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    final map = {for (final p in _projects) p.id: p};
    _projects = orderedIds
        .where(map.containsKey)
        .map((id) => map[id]!.copyWith(sortOrder: orderedIds.indexOf(id)))
        .toList()
        .cast<Project>();
    notifyListeners();
    // Reordering doesn't change which project is active, so no _pushWidget().
    await _storage.reorderProjects(orderedIds);
  }

  /// Saves (or clears) the rich-text note for [projectId].
  /// Passing null clears the note and its timestamp.
  Future<void> updateProjectNote(String projectId, String? note) async {
    final now = note != null ? DateTime.now().toUtc() : null;

    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
        note:          note,
        clearNote:     note == null,
        noteUpdatedAt: now,
      );
    }).toList().cast<Project>();
    notifyListeners();
    // Note changes are not shown in the widget, so no _pushWidget() needed.

    final updated = _projects.firstWhere((p) => p.id == projectId);
    await _storage.updateProject(updated);
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────

  /// Returns the live in-memory project, or null.
  Project? findProject(String projectId) =>
      _projects.where((p) => p.id == projectId).firstOrNull;

  Future<void> addTask(
    String projectId,
    String title, {
    DateTime? dueDate,
  }) async {
    final task = Task(
      id:        const Uuid().v4(),
      title:     title,
      status:    TaskStatus.todo,
      createdAt: DateTime.now(),
      dueDate:   dueDate,
    );

    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(tasks: [...p.tasks, task]);
    }).toList().cast<Project>();
    notifyListeners();

    // Task count / overdue summary is displayed in the widget.
    // Only push if the affected project is the active one.
    if (activeProject?.id == projectId) _pushWidget(); // ← NEW

    await _storage.saveTask(task, projectId);
  }

  Future<void> updateTask(
    String projectId,
    String taskId, {
    String?     title,
    TaskStatus? status,
    DateTime?   dueDate,
    bool        clearDueDate = false,
  }) async {
    Task? updated;

    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
        tasks: p.tasks.map((t) {
          if (t.id != taskId) return t;
          updated = t.copyWith(
            title:        title,
            status:       status,
            dueDate:      dueDate,
            clearDueDate: clearDueDate,
          );
          return updated!;
        }).toList(),
      );
    }).toList().cast<Project>();
    notifyListeners();

    // Task status / overdue changes affect the widget task_summary.
    if (activeProject?.id == projectId) _pushWidget(); // ← NEW

    if (updated != null) await _storage.updateTask(updated!, projectId);
  }

  Future<void> removeTask(String projectId, String taskId) async {
    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
          tasks: p.tasks.where((t) => t.id != taskId).toList());
    }).toList().cast<Project>();
    notifyListeners();

    if (activeProject?.id == projectId) _pushWidget(); // ← NEW

    await _storage.deleteTask(taskId);
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _storage.saveSettings(s);
    notifyListeners();
    await rescheduleIfNeeded();
  }

  // ── Foreground service ────────────────────────────────────────────────────

  Future<void> rescheduleIfNeeded() async {
    final active = activeProject;
    if (active == null || !_settings.notificationsEnabled) {
      await ForegroundServiceManager.instance.stop();
    } else {
      await ForegroundServiceManager.instance.startOrUpdate(active, _settings);
    }
  }

  // ── Widget bridge ─────────────────────────────────────────────────────────

  /// Fire-and-forget: push current active project state to the home widget.
  ///
  /// Never awaited by callers — a widget failure must never block app logic.
  /// Errors are caught and logged inside [WidgetService.push].
  void _pushWidget() {
    WidgetService.instance.push(activeProject: activeProject);
  }
}