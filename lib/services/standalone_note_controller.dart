// lib/services/standalone_note_controller.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:focusbell/services/continuity_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

  // ── Seed asset → real file path ─────────────────────────────────
  //
  // imagePath is a plain file-system path (no asset/file distinction
  // anywhere in NoteBlock), so the editor almost certainly renders it
  // with Image.file(File(imagePath)) — same as a user-picked photo.
  // We copy the bundled asset into the app's documents directory once,
  // then point the welcome note's image block at that real file. This
  // keeps the seeded note indistinguishable from user-created content
  // and avoids needing any special-cased "is this an asset?" branch
  // in the renderer.

  Future<String?> _materializeSeedAsset({
    required String assetPath,
    required String destFileName,
  }) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      final docsDir = await getApplicationDocumentsDirectory();
      final seedDir = Directory(p.join(docsDir.path, 'seed_assets'));
      if (!await seedDir.exists()) {
        await seedDir.create(recursive: true);
      }
      final destFile = File(p.join(seedDir.path, destFileName));
      await destFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      return destFile.path;
    } catch (e) {
      // If the asset is missing or the copy fails, skip the image block
      // rather than seeding a note that points at a dead path.
      debugPrint('StandaloneNoteController: failed to seed image asset: $e');
      return null;
    }
  }

  // ── Welcome note seed ─────────────────────────────────────────

  Future<void> _seedWelcomeNote(Database db) async {
    final now = DateTime.now().toUtc();
    final id  = '${now.millisecondsSinceEpoch}_welcome';

    final auraPath = await _materializeSeedAsset(
      assetPath:    'assets/images/aura.jpg',
      destFileName: 'aura.jpg',
    );

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
            text: 'This is your personal rich-text notebook — text, '
                  'checklists, voice memos, photos, and PDFs, all in one '
                  'place. Everything stays on this device and saves '
                  'automatically whenever you tap ',
          ),
          NoteSeg(
            text:  'Save',
            bold:  true,
            color: const Color(0xFF34C759),
          ),
          NoteSeg(text: '. Here\'s a quick tour — feel free to delete this note once you\'re comfortable.'),
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
          NoteSeg(text: 'Tap '),
          NoteSeg(text: 'Tt', bold: true, color: const Color(0xFFFFD60A)),
          NoteSeg(text: ' in the toolbar to open the Format Bar, then pick '),
          NoteSeg(text: 'H1 ', bold: true, color: const Color(0xFFFF6B9D)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H2 ', bold: true, color: const Color(0xFFFF9F0A)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H3 ', bold: true, color: const Color(0xFFFFD60A)),
          NoteSeg(text: '/ '),
          NoteSeg(text: 'H4 ', bold: true, color: const Color(0xFF64D2FF)),
          NoteSeg(text: 'for headings, or '),
          NoteSeg(text: 'body', color: Colors.white70),
          NoteSeg(text: ' for normal text. Use headings to break long notes into sections you can scan at a glance.'),
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
          NoteSeg(text: 'Select any text to bring up the Format Bar:\n'),
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
          NoteSeg(text: ' — or pick a custom colour for either.'),
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
            text: ' in the Format Bar to insert a hyperlink. Select text '
                  'first to turn it into a link, or type new link text in '
                  'the dialog. Links stay tappable in Preview mode. Example: ',
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
        segs:        [NoteSeg(text: 'Bullet list — good for loose collections of ideas')],
      ),

      NoteBlock(
        id:           noteUid(),
        type:         NoteBlockType.text,
        orderedList:  true,
        segs:         [NoteSeg(text: 'Numbered list — good for steps or rankings')],
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
                  'to-do items, then tap a box to check it off. Enter plain '
                  'numbers in two or more checkboxes and a ',
          ),
          NoteSeg(
            text:  'Checkbox Total',
            bold:  true,
            color: const Color(0xFF34C759),
          ),
          NoteSeg(text: ' appears automatically below them — handy for quick tallies like a packing list budget or a shopping total.'),
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
            text: ' in the bottom toolbar to start recording. A live timer '
                  'and waveform appear while you record. Tap ',
          ),
          NoteSeg(text: 'Stop', bold: true, color: const Color(0xFFFF3B30)),
          NoteSeg(text: ' to save the clip inline, or '),
          NoteSeg(text: 'Cancel', bold: true, color: Colors.white54),
          NoteSeg(text: ' to discard it. Tap play on any clip to listen back — great for capturing a thought faster than you can type it.'),
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
            text: ' in the bottom toolbar to attach a photo — take a new '
                  'one or pick from your gallery. Images sit inline and open '
                  'fullscreen on tap; tap the ✕ badge to remove one. Here\'s '
                  'an example below:',
          ),
        ],
      ),

      // Real image block — only added if the asset copied successfully.
      if (auraPath != null)
        NoteBlock(
          id:        noteUid(),
          type:      NoteBlockType.image,
          imagePath: auraPath,
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
            text: ' in the bottom toolbar to attach any PDF file. The card '
                  'shows the filename, page count, and file size. Tap ',
          ),
          NoteSeg(text: 'Open', bold: true, color: const Color(0xFFFF6B9D)),
          NoteSeg(text: ' to view it in your device\'s PDF reader — useful for keeping a paper, receipt, or contract next to the notes about it.'),
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
            text: ' in the top bar for a clean, read-only view with the '
                  'keyboard tucked away and every link tappable. Tap ',
          ),
          NoteSeg(text: 'Edit', bold: true, color: const Color(0xFF64D2FF)),
          NoteSeg(text: ' to go back to writing.'),
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
            text: ' button turns green whenever you have unsaved changes — '
                  'and navigating back with changes pending saves them for '
                  'you automatically, so you won\'t lose anything. The ',
          ),
          NoteSeg(
            text:  'Clear',
            bold:  true,
            color: const Color(0xFFFF3B30),
          ),
          NoteSeg(
            text: ' button in the top bar permanently deletes this note '
                  'after a confirmation prompt — there\'s no undo, so use it '
                  'deliberately.',
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
    ContinuityService.instance.track(
      ContinuityActionType.addedNote, detail: n.title);   // ← ADD
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
    ContinuityService.instance.track(
      ContinuityActionType.editedNote, detail: title);     // ← ADD
  }

  Future<void> deleteNote(String id) async {
    final deletedTitle =
        _notes.where((n) => n.id == id).firstOrNull?.title;   // ← ADD
    _notes = _notes.where((n) => n.id != id).toList();
    notifyListeners();
    final db = await _getDb();
    await db.delete(
      'standalone_notes',
      where:     'id = ?',
      whereArgs: [id],
    );
    ContinuityService.instance.track(
      ContinuityActionType.deletedNote, detail: deletedTitle); // ← ADD
  }

  StandaloneNote? find(String id) =>
      _notes.where((n) => n.id == id).firstOrNull;
}