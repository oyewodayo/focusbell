// models/saved_place.dart — FULL REPLACEMENT
// Adds isWatched (always-on passive location awareness)

class SavedPlace {
  final String   id;
  final String   name;
  final String   emoji;
  final double   latitude;
  final double   longitude;
  final double   radiusMeters;
  final bool     isWatched;      // true = always-on arrival/departure alerts
  final DateTime createdAt;

  const SavedPlace({
    required this.id,
    required this.name,
    required this.emoji,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 150,
    this.isWatched    = false,
    required this.createdAt,
  });

  SavedPlace copyWith({
    String? name,
    String? emoji,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool?   isWatched,
  }) => SavedPlace(
    id:           id,
    name:         name         ?? this.name,
    emoji:        emoji        ?? this.emoji,
    latitude:     latitude     ?? this.latitude,
    longitude:    longitude    ?? this.longitude,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    isWatched:    isWatched    ?? this.isWatched,
    createdAt:    createdAt,
  );

  // ── Context-aware alarm messages ──────────────────────────────

  String arriveMessage() {
    final n = name.toLowerCase();
    if (n == 'home')         return 'Welcome home $emoji';
    if (n == 'work' ||
        n == 'office')       return 'You\'ve arrived at work $emoji';
    if (n == 'school' ||
        n == 'university' ||
        n == 'college')      return 'You\'re at school $emoji';
    if (n == 'gym')          return 'Time to work out $emoji';
    if (n == 'church' ||
        n == 'mosque' ||
        n == 'temple')       return 'You\'ve arrived at $name $emoji';
    if (n == 'airport')      return 'You\'re at the airport $emoji';
    if (n == 'hospital')     return 'You\'ve arrived at the hospital $emoji';
    return 'Arrived at $name $emoji';
  }

  String leaveMessage() {
    final n = name.toLowerCase();
    if (n == 'home')         return 'Leaving home $emoji';
    if (n == 'work' ||
        n == 'office')       return 'Leaving work $emoji';
    if (n == 'school' ||
        n == 'university' ||
        n == 'college')      return 'Leaving school $emoji';
    if (n == 'gym')          return 'Great workout! Leaving the gym $emoji';
    if (n == 'church' ||
        n == 'mosque' ||
        n == 'temple')       return 'Leaving $name $emoji';
    if (n == 'airport')      return 'Leaving the airport $emoji';
    if (n == 'hospital')     return 'Leaving the hospital $emoji';
    return 'Leaving $name $emoji';
  }

  // ── SQLite ────────────────────────────────────────────────────

  Map<String, dynamic> toRow() => {
    'id':            id,
    'name':          name,
    'emoji':         emoji,
    'latitude':      latitude,
    'longitude':     longitude,
    'radius_meters': radiusMeters,
    'is_watched':    isWatched ? 1 : 0,
    'created_at':    createdAt.toIso8601String(),
  };

  factory SavedPlace.fromRow(Map<String, dynamic> r) => SavedPlace(
    id:           r['id']            as String,
    name:         r['name']          as String,
    emoji:        r['emoji']         as String,
    latitude:     (r['latitude']     as num).toDouble(),
    longitude:    (r['longitude']    as num).toDouble(),
    radiusMeters: (r['radius_meters'] as num?)?.toDouble() ?? 150,
    isWatched:    (r['is_watched']   as int? ?? 0) == 1,
    createdAt:    DateTime.parse(r['created_at'] as String),
  );

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