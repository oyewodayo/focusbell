// lib/services/app_controller.dart
//
// PERMANENT FIX: boot() now returns immediately after kicking off async work.
// The UI renders at once; services initialize in the background.
// No service failure can ever block the splash screen again.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../models/settings.dart';
import 'foreground_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'widget_service.dart';

class AppController extends ChangeNotifier {
  AppController._();
  static final AppController instance = AppController._();

  StorageService? _storage;
  List<Project> _projects = [];
  AppSettings   _settings = const AppSettings();
  bool          _loading  = true;
  Object?       bootError;

  List<Project> get projects  => _projects;
  AppSettings   get settings  => _settings;
  bool          get loading   => _loading;

  Project? get activeProject =>
      _projects.where((p) => p.isActive).firstOrNull;

  // ── Boot ──────────────────────────────────────────────────────────────────

  /// Returns immediately. All heavy work runs in the background.
  /// The UI will rebuild when [_loading] flips to false.
  Future<void> boot() async {
    // Kick off background init — never await this in main()
    _bootInBackground();
  }

  void _bootInBackground() {
    // Each step is individually guarded. One failure never kills the rest.
    Future(() async {
      // ① Storage — the only truly required step
      try {
        _storage  = await StorageService.getInstance()
            .timeout(const Duration(seconds: 10));
        _projects = await _storage!.loadProjects()
            .timeout(const Duration(seconds: 5));
        _settings = _storage!.loadSettings();
      } catch (e, st) {
        debugPrint('[AppController] storage init failed: $e\n$st');
        bootError = e;
        _loading  = false;
        notifyListeners();
        return; // Can't continue without storage
      }

      // ② Mark ready — UI unblocks here
      _loading = false;
      notifyListeners();

      // ③ Non-critical services — all fire-and-forget after UI is shown
      unawaited(_safeInit('WidgetService',
          () => WidgetService.instance.init()));

      unawaited(_safeInit('ForegroundService',
          () async => ForegroundServiceManager.instance.configure(_settings)));

      unawaited(_safeInit('reschedule',
          () => rescheduleIfNeeded()));

      unawaited(_safeInit('pushWidget',
          () async => _pushWidget()));

    });
  }

  /// Runs [fn] with a 6-second timeout, swallowing all errors.
  Future<void> _safeInit(String name, Future<void> Function() fn) async {
    try {
      await fn().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[AppController] $name failed (non-fatal): $e');
    }
  }

  /// Legacy escape hatch — kept for compatibility but no longer needed.
  void forceReady() {
    if (_loading) {
      _loading  = false;
      bootError ??= 'Boot timed out.';
      notifyListeners();
    }
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
    await _storage?.saveProject(project);
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
    _pushWidget();

    await _storage?.setActiveProject(id);
    await _storage?.reorderProjects(reordered.map((p) => p.id).toList());

    final active = activeProject;
    if (active != null && _settings.notificationsEnabled) {
      await NotificationService.instance
          .showInstant(active, soundMode: _settings.soundMode);
      unawaited(_safeInit('foreground',
          () => ForegroundServiceManager.instance.startOrUpdate(active, _settings)));
    }
  }

  Future<void> removeProject(String id) async {
    final wasActive = _projects.firstWhere((p) => p.id == id).isActive;
    _projects = _projects.where((p) => p.id != id).toList();

    if (wasActive && _projects.isNotEmpty) {
      final promoted = _projects.first.copyWith(isActive: true);
      _projects = [promoted, ..._projects.skip(1)];
      await _storage?.setActiveProject(promoted.id);
    }

    notifyListeners();
    _pushWidget();

    await _storage?.deleteProject(id);
    unawaited(_safeInit('reschedule', () => rescheduleIfNeeded()));
  }

  Future<void> archiveProject(String id) async {
    _projects = _projects
        .map((p) =>
            p.id == id ? p.copyWith(isArchived: true, isActive: false) : p)
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage?.updateProject(updated);
    unawaited(_safeInit('reschedule', () => rescheduleIfNeeded()));
  }

  Future<void> unarchiveProject(String id) async {
    _projects = _projects
        .map((p) => p.id == id ? p.copyWith(isArchived: false) : p)
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage?.updateProject(updated);
  }

  Future<void> updateProject(
    String id, {
    required String          name,
    required String          description,
    required Priority        priority,
    required ProjectCategory category,
  }) async {
    _projects = _projects.map((p) {
      if (p.id != id) return p;
      return p.copyWith(
          name: name, description: description,
          priority: priority, category: category);
    }).toList().cast<Project>();
    notifyListeners();
    _pushWidget();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage?.updateProject(updated);

    if (activeProject?.id == id) {
      unawaited(_safeInit('foreground',
          () => ForegroundServiceManager.instance.updateData(activeProject!, _settings)));
    }
  }

  Future<void> updateProjectPriority(String id, Priority priority) async {
    _projects = _projects
        .map((p) => p.id == id ? p.copyWith(priority: priority) : p)
        .toList()
        .cast<Project>();
    notifyListeners();
    _pushWidget();

    final updated = _projects.firstWhere((p) => p.id == id);
    await _storage?.updateProject(updated);

    if (activeProject?.id == id) {
      unawaited(_safeInit('reschedule', () => rescheduleIfNeeded()));
    }
  }

  Future<void> reorderProjects(List<String> orderedIds) async {
    final map = {for (final p in _projects) p.id: p};
    _projects = orderedIds
        .where(map.containsKey)
        .map((id) => map[id]!.copyWith(sortOrder: orderedIds.indexOf(id)))
        .toList()
        .cast<Project>();
    notifyListeners();
    await _storage?.reorderProjects(orderedIds);
  }

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

    final updated = _projects.firstWhere((p) => p.id == projectId);
    await _storage?.updateProject(updated);
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────

  Project? findProject(String projectId) =>
      _projects.where((p) => p.id == projectId).firstOrNull;

  Future<void> addTask(String projectId, String title, {DateTime? dueDate}) async {
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

    if (activeProject?.id == projectId) _pushWidget();
    await _storage?.saveTask(task, projectId);
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

    if (activeProject?.id == projectId) _pushWidget();
    if (updated != null) await _storage?.updateTask(updated!, projectId);
  }

  Future<void> removeTask(String projectId, String taskId) async {
    _projects = _projects.map((p) {
      if (p.id != projectId) return p;
      return p.copyWith(
          tasks: p.tasks.where((t) => t.id != taskId).toList());
    }).toList().cast<Project>();
    notifyListeners();

    if (activeProject?.id == projectId) _pushWidget();
    await _storage?.deleteTask(taskId);
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _storage?.saveSettings(s);
    notifyListeners();
    unawaited(_safeInit('reschedule', () => rescheduleIfNeeded()));
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

  void _pushWidget() {
    unawaited(_safeInit('widget push',
        () async => WidgetService.instance.push(activeProject: activeProject)));
  }
}