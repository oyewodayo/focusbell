import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import '../models/settings.dart';

class StorageService {
  static const _projectsKey = 'projects';
  static const _settingsKey = 'settings';

  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      final svc = StorageService._();
      svc._prefs = await SharedPreferences.getInstance();
      _instance = svc;
    }
    return _instance!;
  }

  // ── Projects ──────────────────────────────────────────────────

  List<Project> loadProjects() {
    final raw = _prefs.getString(_projectsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProjects(List<Project> projects) async {
    final encoded = jsonEncode(projects.map((p) => p.toJson()).toList());
    await _prefs.setString(_projectsKey, encoded);
  }

  // ── Settings ──────────────────────────────────────────────────

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}