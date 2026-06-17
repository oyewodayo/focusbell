// models/saved_place.dart — NEW FILE
//
// A named location the user saves once and reuses across reminders.
// Stored in SQLite via ReminderService._ensureTable().

class SavedPlace {
  final String id;
  final String name;
  final String emoji;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  const SavedPlace({
    required this.id,
    required this.name,
    required this.emoji,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 150,
    required this.createdAt,
  });

  SavedPlace copyWith({
    String? name,
    String? emoji,
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) => SavedPlace(
    id:           id,
    name:         name         ?? this.name,
    emoji:        emoji        ?? this.emoji,
    latitude:     latitude     ?? this.latitude,
    longitude:    longitude    ?? this.longitude,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    createdAt:    createdAt,
  );

  Map<String, dynamic> toRow() => {
    'id':           id,
    'name':         name,
    'emoji':        emoji,
    'latitude':     latitude,
    'longitude':    longitude,
    'radius_meters': radiusMeters,
    'created_at':   createdAt.toIso8601String(),
  };

  factory SavedPlace.fromRow(Map<String, dynamic> r) => SavedPlace(
    id:           r['id']           as String,
    name:         r['name']         as String,
    emoji:        r['emoji']        as String,
    latitude:     (r['latitude']    as num).toDouble(),
    longitude:    (r['longitude']   as num).toDouble(),
    radiusMeters: (r['radius_meters'] as num?)?.toDouble() ?? 150,
    createdAt:    DateTime.parse(r['created_at'] as String),
  );

  // ── Built-in presets (no coords yet — user captures them) ─────
  static const List<(String emoji, String name)> presets = [
    ('🏠', 'Home'),
    ('💼', 'Work'),
    ('🏋️', 'Gym'),
    ('🏫', 'School'),
    ('✈️', 'Airport'),
    ('🏥', 'Hospital'),
    ('🛒', 'Supermarket'),
    ('⛪', 'Church'),
    ('🍽️', 'Restaurant'),
    ('👨‍👩‍👧', 'Family'),
  ];
}