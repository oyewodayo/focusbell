// lib/models/standalone_note.dart

import 'note_models.dart'; // for noteUid

// ─────────────────────────────────────────────────────────────────────────────
// StandaloneNote
// A free-standing rich note that lives outside any project.
// The `note` field stores the same NoteBlock JSON that ProjectNoteSheet uses.
// ─────────────────────────────────────────────────────────────────────────────

class StandaloneNote {
  final String   id;
  final String   title;        // plain-text title (mirrors _titleCtrl)
  final String?  note;         // NoteBlock JSON or null when empty
  final DateTime createdAt;
  final DateTime updatedAt;

  const StandaloneNote({
    required this.id,
    required this.title,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isEmpty => (note == null || note!.isEmpty) && title.trim().isEmpty;

  StandaloneNote copyWith({
    String?   title,
    String?   note,
    bool      clearNote = false,
    DateTime? updatedAt,
  }) =>
      StandaloneNote(
        id:        id,
        title:     title      ?? this.title,
        note:      clearNote ? null : (note ?? this.note),
        createdAt: createdAt,
        updatedAt: updatedAt  ?? this.updatedAt,
      );

  // ── Serialisation ─────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':        id,
        'title':     title,
        'note':      note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StandaloneNote.fromJson(Map<String, dynamic> j) => StandaloneNote(
        id:        j['id']        as String,
        title:     j['title']     as String? ?? '',
        note:      j['note']      as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  // ── SQLite row helpers ────────────────────────────────────────

  Map<String, dynamic> toRow() => {
        'id':         id,
        'title':      title,
        'note':       note,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StandaloneNote.fromRow(Map<String, dynamic> row) => StandaloneNote(
        id:        row['id']         as String,
        title:     row['title']      as String? ?? '',
        note:      row['note']       as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  /// Creates a brand-new blank note with a fresh UID.
  static StandaloneNote blank() {
    final now = DateTime.now().toUtc();
    return StandaloneNote(
      id:        noteUid(),
      title:     '',
      createdAt: now,
      updatedAt: now,
    );
  }
}