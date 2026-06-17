// services/saved_places_service.dart — NEW FILE
//
// CRUD for saved places stored in SQLite.
// Singleton — call SavedPlacesService.instance.init() from main.dart.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/saved_place.dart';
import 'database_helper.dart';

class SavedPlacesService {
  SavedPlacesService._();
  static final SavedPlacesService instance = SavedPlacesService._();

  final places = ValueNotifier<List<SavedPlace>>([]);
  bool _ready = false;

  // ── Init ──────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await _ensureTable();
    await _load();
    debugPrint('[SavedPlacesService] ready — ${places.value.length} place(s).');
  }

  // ── CRUD ──────────────────────────────────────────────────────

  Future<SavedPlace> add({
    required String name,
    required String emoji,
    required double latitude,
    required double longitude,
    double radiusMeters = 150,
  }) async {
    final place = SavedPlace(
      id:           const Uuid().v4(),
      name:         name,
      emoji:        emoji,
      latitude:     latitude,
      longitude:    longitude,
      radiusMeters: radiusMeters,
      createdAt:    DateTime.now(),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert('saved_places', place.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    places.value = [...places.value, place];
    debugPrint('[SavedPlacesService] added "${place.name}"');
    return place;
  }

  Future<void> update(SavedPlace updated) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('saved_places', updated.toRow(),
        where: 'id = ?', whereArgs: [updated.id]);
    places.value = places.value
        .map((p) => p.id == updated.id ? updated : p)
        .toList();
    debugPrint('[SavedPlacesService] updated "${updated.name}"');
  }

  Future<void> remove(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('saved_places', where: 'id = ?', whereArgs: [id]);
    places.value = places.value.where((p) => p.id != id).toList();
    debugPrint('[SavedPlacesService] removed $id');
  }

  // ── Helpers ───────────────────────────────────────────────────

  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_places (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        emoji         TEXT NOT NULL DEFAULT '📍',
        latitude      REAL NOT NULL,
        longitude     REAL NOT NULL,
        radius_meters REAL NOT NULL DEFAULT 150,
        created_at    TEXT NOT NULL
      )
    ''');
  }

  Future<void> _load() async {
    final db   = await DatabaseHelper.instance.database;
    final rows = await db.query('saved_places', orderBy: 'created_at ASC');
    places.value = rows.map(SavedPlace.fromRow).toList();
  }
}