import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/settings.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

class AppController extends ChangeNotifier {
  AppController._();
  static final AppController instance = AppController._();

  late StorageService _storage;
  List<Project> _projects = [];
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  List<Project> get projects => _projects;
  AppSettings get settings => _settings;
  bool get loading => _loading;

  Project? get activeProject =>
      _projects.where((p) => p.isActive).firstOrNull;

  // ── Boot ─────────────────────────────────────────────────────

  Future<void> boot() async {
    _storage = await StorageService.getInstance();
    _projects = _storage.loadProjects();
    _settings = _storage.loadSettings();
    _loading = false;
    notifyListeners();
  }

  // ── Projects ──────────────────────────────────────────────────

  Future<void> addProject(String name, Priority priority) async {
    final p = Project(
      id: const Uuid().v4(),
      name: name,
      priority: priority,
      createdAt: DateTime.now(),
    );
    _projects = [..._projects, p];
    await _persist();
  }

  Future<void> setActive(String id) async {
    _projects = _projects.map((p) => p.copyWith(isActive: p.id == id)).toList();
    await _persist();
    final active = activeProject;
    if (active != null && _settings.notificationsEnabled) {
      await NotificationService.instance.showInstant(active);
      await NotificationService.instance.scheduleReminders(active, _settings);
    }
  }

  Future<void> removeProject(String id) async {
    final wasActive = _projects.firstWhere((p) => p.id == id).isActive;
    _projects = _projects.where((p) => p.id != id).toList();
    if (wasActive && _projects.isNotEmpty) {
      _projects = [
        _projects.first.copyWith(isActive: true),
        ..._projects.skip(1),
      ];
    }
    await _persist();
    if (wasActive) await _rescheduleIfNeeded();
  }

  Future<void> updateProjectPriority(String id, Priority priority) async {
    _projects = _projects
        .map((p) => p.id == id ? p.copyWith(priority: priority) : p)
        .toList();
    await _persist();
    if (activeProject?.id == id) await _rescheduleIfNeeded();
  }

  // ── Settings ──────────────────────────────────────────────────

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _storage.saveSettings(s);
    notifyListeners();
    await _rescheduleIfNeeded();
  }

  // ── Internal ──────────────────────────────────────────────────

  Future<void> _persist() async {
    await _storage.saveProjects(_projects);
    notifyListeners();
  }

  Future<void> _rescheduleIfNeeded() async {
    final active = activeProject;
    if (active == null || !_settings.notificationsEnabled) {
      await NotificationService.instance.cancelAll();
    } else {
      await NotificationService.instance.scheduleReminders(active, _settings);
    }
  }
}