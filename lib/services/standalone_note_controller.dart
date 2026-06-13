// lib/services/standalone_note_controller.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../models/standalone_note.dart';
import '../models/note_models.dart';
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StandaloneNoteController
// ─────────────────────────────────────────────────────────────────────────────

class StandaloneNoteController extends ChangeNotifier {
  StandaloneNoteController._();
  static final StandaloneNoteController instance =
      StandaloneNoteController._();

  List<StandaloneNote> _notes = [];
  bool _ready = false;

  List<StandaloneNote> get notes => _notes;
  bool get ready => _ready;

  // ── Boot ──────────────────────────────────────────────────────

  Future<void> boot() async {
    final db = await _getDb();
    await _createTable(db);
    _notes = await _loadAll(db);

    // First-ever launch: seed the welcome note.
    if (_notes.isEmpty) {
      await _seedWelcomeNote(db);
      _notes = await _loadAll(db);
    }

    _ready = true;
    notifyListeners();
  }

  // ── Get the already-open database from StorageService ─────────

  Future<Database> _getDb() async {
    final storage = await StorageService.getInstance();
    return storage.database;
  }

  // ── Table creation ────────────────────────────────────────────

  Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS standalone_notes (
        id         TEXT PRIMARY KEY,
        title      TEXT NOT NULL DEFAULT '',
        note       TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ── Welcome note seed ─────────────────────────────────────────

  Future<void> _seedWelcomeNote(Database db) async {
    final now = DateTime.now().toUtc();
    final id  = '${now.millisecondsSinceEpoch}_welcome';

    final blocks = <NoteBlock>[
      // ── Intro heading ─────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH1: true,
        segs: [
          NoteSeg(
            text:  '👋 Welcome to Notes',
            bold:  true,
            color: const Color(0xFF64D2FF),
          ),
        ],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'This is your personal rich-text notebook. '
                  'Everything you write here stays private and '
                  'is saved automatically when you tap ',
          ),
          NoteSeg(
            text:  'Save',
            bold:  true,
            color: const Color(0xFF34C759),
          ),
          NoteSeg(text: '. Below is a tour of every feature.'),
        ],
      ),

      // ── Headings ──────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '✏️  Text & Headings', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the '),
          NoteSeg(text: 'Tt', bold: true, color: const Color(0xFFFFD60A)),
          NoteSeg(text: ' icon in the toolbar to open the Format Bar. '
              'Choose '),
          NoteSeg(text: 'H1 ', bold: true, color: const Color(0xFFFF6B9D)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H2 ', bold: true, color: const Color(0xFFFF9F0A)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H3 ', bold: true, color: const Color(0xFFFFD60A)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H4 ', bold: true, color: const Color(0xFF64D2FF)),
          NoteSeg(text: 'for headings, or '),
          NoteSeg(text: 'body', color: Colors.white70),
          NoteSeg(text: ' for normal text.'),
        ],
      ),

      // ── Inline formatting ─────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '🎨  Inline Formatting', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Select any text, then use the Format Bar:\n'),
          NoteSeg(text: 'Bold  ',      bold: true),
          NoteSeg(text: '  Italic  ',  italic: true, color: Colors.white70),
          NoteSeg(text: '  Underline  ', underline: true, color: Colors.white70),
          NoteSeg(
            text:  '  Strikethrough',
            strikethrough: true,
            color: Colors.white54,
          ),
        ],
      ),

      // ── Colour ────────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Text colours: '),
          NoteSeg(text: 'Red ',    color: const Color(0xFFFF3B30)),
          NoteSeg(text: 'Orange ', color: const Color(0xFFFF9F0A)),
          NoteSeg(text: 'Yellow ', color: const Color(0xFFFFD60A)),
          NoteSeg(text: 'Green ',  color: const Color(0xFF34C759)),
          NoteSeg(text: 'Blue ',   color: const Color(0xFF0A84FF)),
          NoteSeg(text: 'Purple ', color: const Color(0xFFBF5AF2)),
          NoteSeg(text: 'Pink',    color: const Color(0xFFFF6B9D)),
        ],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Highlights: '),
          NoteSeg(text: 'Yellow',  highlight: const Color(0x66FFD60A)),
          NoteSeg(text: '  Green', highlight: const Color(0x6634C759)),
          NoteSeg(text: '  Blue',  highlight: const Color(0x660A84FF)),
          NoteSeg(text: '  Red',   highlight: const Color(0x66FF3B30)),
          NoteSeg(text: '  Purple',highlight: const Color(0x66BF5AF2)),
          NoteSeg(text: '  Orange',highlight: const Color(0x66FF9F0A)),
          NoteSeg(text: ' — or pick a custom colour.'),
        ],
      ),

      // ── Links ─────────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '🔗  Links', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the '),
          NoteSeg(
            text:      '🔗 link icon',
            bold:      true,
            color:     const Color(0xFF64D2FF),
            underline: true,
          ),
          NoteSeg(
            text: ' in the Format Bar to insert a hyperlink. '
                  'Select text first to turn it into a link, or '
                  'type new link text in the dialog. In Preview mode '
                  'all links are tappable. Example: ',
          ),
          NoteSeg(
            text:      'focusbell.app',
            url:       'https://focusbell.app',
            color:     const Color(0xFF64D2FF),
            underline: true,
          ),
        ],
      ),

      // ── Alignment & Lists ─────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '📐  Alignment & Lists', bold: true)],
      ),

      NoteBlock(
        id:    noteUid(),
        type:  NoteBlockType.text,
        align: NoteAlign.center,
        segs:  [
          NoteSeg(
            text:  'This line is centred.',
            italic: true,
            color:  Colors.white60,
          ),
        ],
      ),

      NoteBlock(
        id:          noteUid(),
        type:        NoteBlockType.text,
        bulletList:  true,
        segs:        [NoteSeg(text: 'Bullet list item')],
      ),

      NoteBlock(
        id:           noteUid(),
        type:         NoteBlockType.text,
        orderedList:  true,
        segs:         [NoteSeg(text: 'Numbered list item')],
      ),

      // ── Checkboxes ────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '☑️  Checkboxes & Totals', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Tap the checkbox icon in the bottom toolbar to add '
                  'to-do items. Check them off by tapping the box. '
                  'If you enter plain numbers in two or more checkboxes, '
                  'a ',
          ),
          NoteSeg(
            text:  'Checkbox Total',
            bold:  true,
            color: const Color(0xFF34C759),
          ),
          NoteSeg(text: ' is automatically calculated and shown below them.'),
        ],
      ),

      NoteBlock(
        id:      noteUid(),
        type:    NoteBlockType.checkbox,
        checked: true,
        segs:    [NoteSeg(text: 'Buy groceries')],
      ),

      NoteBlock(
        id:      noteUid(),
        type:    NoteBlockType.checkbox,
        checked: false,
        segs:    [NoteSeg(text: 'Finish the project report')],
      ),

      NoteBlock(
        id:      noteUid(),
        type:    NoteBlockType.checkbox,
        checked: false,
        segs:    [NoteSeg(text: 'Call the dentist')],
      ),

      // ── Voice notes ───────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '🎙️  Voice Notes', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the '),
          NoteSeg(
            text:  'mic icon',
            bold:  true,
            color: const Color(0xFFFF3B30),
          ),
          NoteSeg(
            text: ' in the bottom toolbar to start recording. '
                  'A live timer and waveform appear while you record. '
                  'Tap ',
          ),
          NoteSeg(text: 'Stop', bold: true, color: const Color(0xFFFF3B30)),
          NoteSeg(
            text: ' to save the audio clip inline, or ',
          ),
          NoteSeg(text: 'Cancel', bold: true, color: Colors.white54),
          NoteSeg(text: ' to discard it. Tap the play button on any clip to listen back.'),
        ],
      ),

      // ── Images ────────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '🖼️  Images', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the '),
          NoteSeg(
            text:  'photo icon',
            bold:  true,
            color: const Color(0xFF64D2FF),
          ),
          NoteSeg(
            text: ' in the bottom toolbar to attach an image — '
                  'either take a new photo or pick one from your gallery. '
                  'Images render inline and can be tapped to open fullscreen. '
                  'Tap the ✕ badge on an image to remove it.',
          ),
        ],
      ),

      // ── PDFs ──────────────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '📄  PDF Attachments', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the '),
          NoteSeg(
            text:  'PDF icon',
            bold:  true,
            color: const Color(0xFFFF6B9D),
          ),
          NoteSeg(
            text: ' in the bottom toolbar to attach any PDF file. '
                  'The card shows the filename, page count and file size. '
                  'Tap ',
          ),
          NoteSeg(text: 'Open', bold: true, color: const Color(0xFFFF6B9D)),
          NoteSeg(text: ' to view it in your device\'s PDF reader.'),
        ],
      ),

      // ── Preview mode ──────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '👁️  Preview Mode', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap '),
          NoteSeg(
            text:  'Preview',
            bold:  true,
            color: const Color(0xFF64D2FF),
          ),
          NoteSeg(
            text: ' in the top bar to switch to a clean read-only view '
                  'where all links are tappable and the keyboard stays hidden. '
                  'Tap ',
          ),
          NoteSeg(text: 'Edit', bold: true, color: const Color(0xFF64D2FF)),
          NoteSeg(text: ' to return to editing.'),
        ],
      ),

      // ── Save & Clear ──────────────────────────────────────────
      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        isH2: true,
        segs: [NoteSeg(text: '💾  Saving & Clearing', bold: true)],
      ),

      NoteBlock(
        id:   noteUid(),
        type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'The '),
          NoteSeg(
            text:  'Save',
            bold:  true,
            color: const Color(0xFF34C759),
          ),
          NoteSeg(
            text: ' button turns green whenever there are unsaved changes. '
                  'Navigating back with unsaved changes auto-saves. '
                  'The ',
          ),
          NoteSeg(
            text:  'Clear',
            bold:  true,
            color: const Color(0xFFFF3B30),
          ),
          NoteSeg(
            text: ' button in the top bar permanently deletes this note '
                  'after a confirmation prompt.',
          ),
        ],
      ),

      // ── Footer ────────────────────────────────────────────────
      NoteBlock(
        id:    noteUid(),
        type:  NoteBlockType.text,
        align: NoteAlign.center,
        segs:  [
          NoteSeg(
            text:  '— You\'re all set. Happy writing! 🚀 —',
            italic: true,
            color:  Colors.white38,
          ),
        ],
      ),
    ];

    final encoded = NoteBlock.encodeList(blocks);

    final welcome = StandaloneNote(
      id:        id,
      title:     'Welcome to Notes ✨',
      note:      encoded,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      'standalone_notes',
      welcome.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── CRUD ──────────────────────────────────────────────────────

  Future<List<StandaloneNote>> _loadAll(Database db) async {
    final rows = await db.query(
      'standalone_notes',
      orderBy: 'updated_at DESC',
    );
    return rows.map(StandaloneNote.fromRow).toList();
  }

  Future<StandaloneNote> createNote() async {
    final n = StandaloneNote.blank();
    _notes = [n, ..._notes];
    notifyListeners();
    final db = await _getDb();
    await db.insert(
      'standalone_notes',
      n.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return n;
  }

  Future<void> saveNote(String id, String title, String? note) async {
    final now = DateTime.now().toUtc();
    _notes = _notes.map((n) {
      if (n.id != id) return n;
      return n.copyWith(
        title:     title,
        note:      note,
        clearNote: note == null,
        updatedAt: now,
      );
    }).toList();
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();

    final updated = _notes.firstWhere((n) => n.id == id);
    final db = await _getDb();
    await db.update(
      'standalone_notes',
      updated.toRow(),
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNote(String id) async {
    _notes = _notes.where((n) => n.id != id).toList();
    notifyListeners();
    final db = await _getDb();
    await db.delete(
      'standalone_notes',
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  StandaloneNote? find(String id) =>
      _notes.where((n) => n.id == id).firstOrNull;
}