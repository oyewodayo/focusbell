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

  /// Whether this note is locked behind the app PIN.
  /// Has no effect if no PIN is configured in AppSettings.
  final bool isLocked;

  const StandaloneNote({
    required this.id,
    required this.title,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.isLocked = false,
  });

  bool get isEmpty =>
      (note == null || note!.isEmpty) && title.trim().isEmpty;

  StandaloneNote copyWith({
    String?   title,
    String?   note,
    bool      clearNote = false,
    DateTime? updatedAt,
    bool?     isLocked,
  }) =>
      StandaloneNote(
        id:        id,
        title:     title     ?? this.title,
        note:      clearNote ? null : (note ?? this.note),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isLocked:  isLocked  ?? this.isLocked,
      );

  // ── Serialisation ─────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':        id,
        'title':     title,
        'note':      note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isLocked':  isLocked,
      };

  factory StandaloneNote.fromJson(Map<String, dynamic> j) => StandaloneNote(
        id:        j['id']        as String,
        title:     j['title']     as String?  ?? '',
        note:      j['note']      as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        isLocked:  j['isLocked']  as bool?    ?? false,
      );

  // ── SQLite row helpers ────────────────────────────────────────
  // The `is_locked` column is stored as INTEGER (0 / 1) — SQLite
  // has no native boolean type.

  Map<String, dynamic> toRow() => {
        'id':         id,
        'title':      title,
        'note':       note,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_locked':  isLocked ? 1 : 0,
      };

  factory StandaloneNote.fromRow(Map<String, dynamic> row) => StandaloneNote(
        id:        row['id']         as String,
        title:     row['title']      as String? ?? '',
        note:      row['note']       as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        // SQLite returns int; guard against bool on non-SQLite storage.
        isLocked:  (row['is_locked'] == 1 || row['is_locked'] == true),
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