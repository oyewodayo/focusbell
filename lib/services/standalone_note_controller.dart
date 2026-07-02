// lib/services/standalone_note_controller.dart
// Full replacement — comprehensive FocusBell welcome note + continuity tracking

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:focusbell/services/continuity_service.dart';
import 'package:focusbell/theme/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/standalone_note.dart';
import '../models/note_models.dart';
import 'storage_service.dart';

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

    if (_notes.isEmpty) {
      await _seedWelcomeNote(db);
      _notes = await _loadAll(db);
    }

    _ready = true;
    notifyListeners();
  }

  Future<Database> _getDb() async {
    final storage = await StorageService.getInstance();
    return storage.database;
  }

  /// Creates the standalone_notes table.
  /// Includes `is_locked` (INTEGER 0/1) — SQLite has no native boolean.
  Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS standalone_notes (
        id         TEXT    PRIMARY KEY,
        title      TEXT    NOT NULL DEFAULT '',
        note       TEXT,
        created_at TEXT    NOT NULL,
        updated_at TEXT    NOT NULL,
        is_locked  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<String?> _materializeSeedAsset({
    required String assetPath,
    required String destFileName,
  }) async {
    try {
      final bytes   = await rootBundle.load(assetPath);
      final docsDir = await getApplicationDocumentsDirectory();
      final seedDir = Directory(p.join(docsDir.path, 'seed_assets'));
      if (!await seedDir.exists()) await seedDir.create(recursive: true);
      final destFile = File(p.join(seedDir.path, destFileName));
      await destFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      return destFile.path;
    } catch (e) {
      debugPrint('StandaloneNoteController: seed asset failed: $e');
      return null;
    }
  }

  Future<void> _seedWelcomeNote(Database db) async {
    final now = DateTime.now().toUtc();
    final id  = '${now.millisecondsSinceEpoch}_welcome';

    final auraPath = await _materializeSeedAsset(
      assetPath:    'assets/images/aura.jpg',
      destFileName: 'aura.jpg',
    );

    final blocks = <NoteBlock>[

      // ════════════════════════════════════════════════════════
      // HERO
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [
          NoteSeg(text: '🔔 Welcome to FocusBell', bold: true,
              color: const Color(0xFF64D2FF)),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'FocusBell is your personal '
                'cognitive overload management system. '
                'It keeps track of your time, your tasks, your location, '
                'and your context — so your brain doesn\'t have to. '
                'This note is your complete guide. Read it once, '
                'then delete it and start fresh.',
            color: null,   // inherits from theme at render time
            ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 1. REMINDERS
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '⏰  Reminders', bold: true,
            color: const Color(0xFFFF9F0A))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Reminders are the heartbeat of FocusBell. '
                'Tap ',
          ),
          NoteSeg(text: '+', bold: true, color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' on the Reminders screen to create one. '
              'You have three ways to set when it fires:'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Set time', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' — pick a specific date and time.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'In minutes', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: ' — "remind me in 25 minutes." '
              'Great for quick countdowns.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Location trigger', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: ' — fire when you arrive at or leave a place. '
              'No time needed.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Smart Time Suggestions', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Start typing a title like "'),
          NoteSeg(text: 'Take medication', bold: true,
              color: const Color(0xFF64D2FF)),
          NoteSeg(text: '" or "'),
          NoteSeg(text: 'Gym', bold: true, color: const Color(0xFF64D2FF)),
          NoteSeg(text: '" and a '),
          NoteSeg(text: '💡 suggestion chip', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(
            text: ' appears below the title field. '
                'Tap it to auto-fill the most sensible time — '
                '8 AM for medication, 6 AM for gym, 9 PM for journaling, '
                'and 25 more keyword triggers. '
                'One tap instead of navigating the date picker.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Repeat Patterns', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Choose '),
          NoteSeg(text: 'Once', bold: true, color: const Color(0xFF0A84FF)),
          NoteSeg(text: ', '),
          NoteSeg(text: 'Daily', bold: true, color: const Color(0xFF30D158)),
          NoteSeg(text: ', '),
          NoteSeg(text: 'Weekdays', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: ', '),
          NoteSeg(text: 'Weekends', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(
            text: ', or tap individual day circles for a custom pattern. '
                'For repeating reminders, the date picker disappears — '
                'you only pick the ',
          ),
          NoteSeg(text: 'time', bold: true),
          NoteSeg(
            text: ', because the date is irrelevant when something repeats. '
                'FocusBell finds the next valid occurrence automatically.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Multiple Dates at Once', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'For one-time reminders, after picking your primary '
                'date and time, tap ',
          ),
          NoteSeg(text: '+ Add date', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(
            text: ' to attach additional dates. '
                'Each extra date creates a separate reminder automatically — '
                'one tap, multiple events. '
                'Perfect for a recurring meeting that doesn\'t follow a '
                'weekly pattern.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Priority & Notes', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Every reminder has three priority levels: '),
          NoteSeg(text: '↓ Low', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: ', '),
          NoteSeg(text: '→ Normal', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ', '),
          NoteSeg(text: '↑ High', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(
            text: '. The priority colour appears on the bell icon in the '
                'list and on the countdown label. '
                'Reminders firing in under 10 minutes have a pulsing '
                'countdown — hard to miss. '
                'Add optional notes for extra context; they show as a '
                'single greyed line in the list, and in full in the '
                'detail view.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Swipe Gestures', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Swipe right', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' on any reminder → Edit button appears.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Swipe left', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(text: ' on any reminder → Delete button appears.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Tap the title/date area', bold: true),
          NoteSeg(
            text: ' → full detail view with complete title, notes, '
                'all metadata, and Edit/Delete actions.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Long-press', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: ' any reminder → move it to a different group.'),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 2. REMINDER GROUPS
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '📁  Reminder Groups', bold: true,
            color: const Color(0xFFBF5AF2))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'As your reminders grow, Groups keep them organised '
                'by context. Six groups come pre-loaded: ',
          ),
          NoteSeg(text: '💼 Work', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ',  '),
          NoteSeg(text: '💊 Health', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: ',  '),
          NoteSeg(text: '🏠 Personal', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: ',  '),
          NoteSeg(text: '🛒 Shopping', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(text: ',  '),
          NoteSeg(text: '👨‍👩‍👧 Family', bold: true,
              color: const Color(0xFFBF5AF2)),
          NoteSeg(text: ',  '),
          NoteSeg(text: '🏋️ Fitness', bold: true,
              color: const Color(0xFFFF6B35)),
          NoteSeg(
            text: '. You can create custom groups with any emoji and colour.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Assign a group when creating or editing a reminder '
              'using the horizontal pill selector. Each group section in the '
              'list is '),
          NoteSeg(text: 'collapsible', bold: true),
          NoteSeg(
            text: ' — tap the section header to collapse it and clear '
                'visual noise. Each section has a coloured dot, an emoji, '
                'and a count badge. A coloured ',
          ),
          NoteSeg(text: 'left-edge stripe', bold: true),
          NoteSeg(
            text: ' on each tile shows its group at a glance without '
                'reading anything.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Colour-coded Calendar Dots', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Swipe the clock panel left to see the calendar. '
                'Every day that has reminders shows up to ',
          ),
          NoteSeg(text: '3 coloured dots', bold: true,
              color: const Color(0xFF64D2FF)),
          NoteSeg(
            text: ' — one per group colour present that day. '
                'Blue dot = Work, green = Health, orange = Personal, etc. '
                'When you add a new reminder, the dot on its calendar day '
                'blooms in with a glow animation. '
                'Tap any calendar day to open the Add Reminder sheet '
                'pre-filled with that date.',
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 3. CLOCK & CALENDAR
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '🕐  Clock & Calendar', bold: true,
            color: const Color(0xFF64D2FF))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'The top panel of the Reminders screen shows a '
                'live analogue clock. When the screen first opens, '
                'the hands sweep from 12 o\'clock to the real time '
                'in under a second — a signature FocusBell moment. '
                'Swipe the clock ',
          ),
          NoteSeg(text: 'left', bold: true),
          NoteSeg(text: ' to reveal the full-month calendar, or tap '
              'the dots below. Swipe the calendar '),
          NoteSeg(text: 'left/right', bold: true),
          NoteSeg(text: ' to change months. The animated month title '
              'slides in the direction you navigate.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'World Clock / Timezone', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Tap the city label under the digital time, '
              'or tap '),
          NoteSeg(text: '⋮ → Change Clock City', bold: true),
          NoteSeg(
            text: '. A full-world city picker opens — searchable by city '
                'or country, with a draggable A–Z scrubber on the right. '
                'Drag a finger down the scrubber and a large letter bubble '
                'tracks your position. Tap any city to set the clock to '
                'that timezone. The second hand spins a full revolution to '
                '"resync" — a visual confirmation the time changed. '
                'The digital time cross-fades to the new timezone\'s time. '
                'Tap ',
          ),
          NoteSeg(text: 'Use device', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' to revert to local time.'),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 4. LOCATION REMINDERS
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '📍  Location Reminders', bold: true,
            color: const Color(0xFF30D158))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Location reminders fire based on where you are, '
                'not when. When creating a reminder, tap ',
          ),
          NoteSeg(text: 'Add location trigger', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: ' to attach a saved place and choose a trigger:'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '📍 When I arrive', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(
            text: ' — fires the first time you enter the geofence. '
                'E.g. "Pick up prescription" fires when you arrive at '
                'the pharmacy.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🚶 When I leave', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(
            text: ' — fires when you leave the geofence. '
                'E.g. "Lock the door" fires when you leave home.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'The detection radius is adjustable from '),
          NoteSeg(text: '50 m → 500 m', bold: true),
          NoteSeg(
            text: '. Location is polled every 30 seconds using a Haversine '
                'distance calculation — accurate, battery-efficient, '
                'and requires no Google Play Services.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Saved Places', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Save named places once and reuse them across all your '
                'location reminders. Tap the location toggle in any reminder '
                'sheet, then tap ',
          ),
          NoteSeg(text: '+ Add place', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: '. Walk to the location, tap '),
          NoteSeg(text: 'Use my current location', bold: true),
          NoteSeg(
            text: ' to capture GPS coordinates, give it a name, pick an '
                'emoji icon, set a default radius, and save. '
                'Your saved places persist forever. Edit or delete them '
                'anytime via the pencil icon in the location picker.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Always-On Place Awareness', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Beyond reminders, you can enable '),
          NoteSeg(text: 'Always-on awareness', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(
            text: ' for any saved place. When enabled, FocusBell fires a '
                'contextual alarm every time you arrive or leave — '
                'no reminder needed, no time set. '
                'The messages are intelligent:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🏠 Arrive at Home', bold: true),
          NoteSeg(text: '  →  "Welcome home 🏠"'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '💼 Arrive at Work', bold: true),
          NoteSeg(text: '  →  "You\'ve arrived at work 💼"'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🏋️ Leave Gym', bold: true),
          NoteSeg(text: '  →  "Great workout! Leaving the gym 🏋️"'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🏫 Arrive at School', bold: true),
          NoteSeg(text: '  →  "You\'re at school 🏫"'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'The Places panel on the Reminders screen shows '
                'all watched places as a horizontal row of cards. '
                'A green dot appears live on any card when you\'re '
                'currently inside that location\'s radius. '
                'Long-press any card to delete a watched place. '
                'Tap ',
          ),
          NoteSeg(text: 'Manage', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' to add or edit places.'),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 5. ALARM & SMART SNOOZE
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '🔔  Alarm & Smart Snooze', bold: true,
            color: const Color(0xFFFF453A))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'When a reminder fires, the full-screen alarm activates '
                'with sound and vibration. Five smart snooze options are '
                'available in a horizontal pill selector:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: '5 min — Quick snooze')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: '15 min — Short break')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: '1 hour — Come back later')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Tonight — Fires at 9:00 PM tonight')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Tomorrow — Fires at 9:00 AM tomorrow')],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'The selected snooze option shows on the Snooze button '
                'in real time — you always know exactly when it will fire '
                'again before you tap. Tap ',
          ),
          NoteSeg(text: 'Done', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(
            text: ' to permanently dismiss. For repeating reminders, '
                'Done schedules the next occurrence automatically.',
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 6. FOCUS GUARD
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '🛡️  Focus Guard', bold: true,
            color: const Color(0xFF0A84FF))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'When a focus session is active, FocusBell '
                'intercepts alarms silently. Instead of ringing and '
                'interrupting your deep work, the reminder is ',
          ),
          NoteSeg(text: 'held', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(
            text: '. The alarm screen shows a shield icon and lists '
                'what\'s being held, with a "Dismiss anyway" escape if '
                'it\'s urgent. When your session ends, all held reminders '
                'surface immediately as a batch — nothing is lost, and '
                'nothing interrupted your flow while you were focused.',
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 7. FOCUS SESSIONS
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '🔴  Focus Sessions', bold: true,
            color: const Color(0xFFFF453A))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Focus Sessions are structured deep-work timers tied '
                'to your projects. Three presets are available:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Pomodoro', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(text: ' — 25 min work · 5 min break · long break every 4'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Deep Work', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: ' — 50 min work · 10 min break · long break every 3'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Ultra Focus', bold: true,
              color: const Color(0xFFBF5AF2)),
          NoteSeg(text: ' — 90 min work · 20 min break · long break every 2'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Sessions track actual vs planned time, completion rate, '
                'and build daily streaks. Analytics show your focus '
                'history per project. The timer runs in the background '
                'with a persistent notification. A completion chime '
                'plays when a segment ends.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(
            text: 'Focus Zone (Location-aware sessions)', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'When a focus session starts, FocusBell captures your '
                'GPS position as your ',
          ),
          NoteSeg(text: 'focus anchor', bold: true),
          NoteSeg(text: '. If you move more than '),
          NoteSeg(text: '50 metres', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(
            text: ' from that anchor while the timer is running, '
                'a warning overlay appears:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, align: NoteAlign.center,
        segs: [
          NoteSeg(text: '"Hey! Where are you going? 🚨\n',
              bold: true, color: const Color(0xFFFF453A)),
          NoteSeg(
            text: 'You\'re Xm away from your focus zone.\n'
                'Go back and stay focused. You\'ve got this."',
            italic: true, color: Colors.white60,
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'A 3-minute cooldown prevents repeated nudges. '
                'Once you return inside the focus zone, the warning resets. '
                'Tap ',
          ),
          NoteSeg(text: '"I\'ll be back shortly"', italic: true,
              color: Colors.white38),
          NoteSeg(
              text: ' to temporarily dismiss without ending your session.'),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 8. COGNITIVE CONTINUITY
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '🧠  Cognitive Continuity', bold: true,
            color: const Color(0xFF64D2FF))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'This is the feature that makes FocusBell different '
                'from every other app. FocusBell silently tracks your '
                'every action in the background — what you added, edited, '
                'opened, and focused on. When you return after being away '
                'for 5+ minutes, a ',
          ),
          NoteSeg(text: 'Quick Brief card', bold: true,
              color: const Color(0xFF64D2FF)),
          NoteSeg(
            text: ' slides in from the top of the screen, synthesising '
                'your context into a single paragraph:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, align: NoteAlign.center,
        segs: [
          NoteSeg(
            text: '"Welcome back. You\'ve been away for 47 minutes. '
                'You had a focus session running on BriefBrew when you left. '
                '"Take medication" fired while you were away. '
                '"Call dentist" is up in 12 minutes."',
            italic: true,
            color: Colors.white60,
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'The card has three urgency levels: '),
          NoteSeg(text: '✨ Low', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: ' (all clear), '),
          NoteSeg(text: '📋 Medium', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(text: ' (something to note), '),
          NoteSeg(text: '⚡ High', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(
            text: ' (urgent — something fired or fires in <15 min). '
                'A countdown arc auto-dismisses it in 30 seconds. '
                'Swipe up to dismiss instantly. '
                'If a focus session was interrupted, a ',
          ),
          NoteSeg(text: '▶ Resume', bold: true,
              color: const Color(0xFF0A84FF)),
          NoteSeg(
            text: ' button appears — tap it to jump straight back to '
                'your session.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'The greeting adapts to time of day — '
                '"Good morning" before noon, "Good evening" after 5 PM, '
                '"Hey, night owl" after midnight. '
                'If you\'ve been away for days, the tone shifts accordingly. '
                'Your brain never has to remember where it left off.',
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 9. NOTES
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '📝  Notes', bold: true,
            color: const Color(0xFFFFD60A))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Notes is a full rich-text editor that lives alongside '
                'your reminders. Everything is stored locally on your device.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Text & Formatting', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Headings:', bold: true),
          NoteSeg(text: '  H1  H2  H3  H4  and body text'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Inline:', bold: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Bold', bold: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Italic', italic: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Underline', underline: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Strikethrough', strikethrough: true),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Colours:', bold: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Red ', color: const Color(0xFFFF3B30)),
          NoteSeg(text: 'Orange ', color: const Color(0xFFFF9F0A)),
          NoteSeg(text: 'Yellow ', color: const Color(0xFFFFD60A)),
          NoteSeg(text: 'Green ', color: const Color(0xFF34C759)),
          NoteSeg(text: 'Blue ', color: const Color(0xFF0A84FF)),
          NoteSeg(text: 'Purple ', color: const Color(0xFFBF5AF2)),
          NoteSeg(text: 'Pink', color: const Color(0xFFFF6B9D)),
          NoteSeg(text: '  + custom picker'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Highlights:', bold: true),
          NoteSeg(text: '  '),
          NoteSeg(text: 'Yellow ', highlight: const Color(0x66FFD60A)),
          NoteSeg(text: ' Green ', highlight: const Color(0x6634C759)),
          NoteSeg(text: ' Blue ', highlight: const Color(0x660A84FF)),
          NoteSeg(text: ' Red ', highlight: const Color(0x66FF3B30)),
          NoteSeg(text: ' Purple', highlight: const Color(0x66BF5AF2)),
          NoteSeg(text: '  + custom'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Alignment:', bold: true),
          NoteSeg(text: '  Left · Centre · Right'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Lists:', bold: true),
          NoteSeg(text: '  Bullet  ·  Numbered'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Links:', bold: true),
          NoteSeg(text: '  Select text → tap 🔗 → enter URL. '
              'Tappable in Preview mode.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Checkboxes & Auto-Totals', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(
            text: 'Tap the checkbox icon in the toolbar to add to-do items. '
                'Here\'s the powerful part: if you enter ',
          ),
          NoteSeg(text: 'numbers only', bold: true),
          NoteSeg(text: ' in two or more consecutive checkboxes, '
              'FocusBell automatically appends a '),
          NoteSeg(text: 'Checkbox Total', bold: true,
              color: const Color(0xFF34C759)),
          NoteSeg(
            text: ' — a live sum of all the numbers. '
                'It updates whenever you check or uncheck items. '
                'Example — a shopping budget:',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Rice — 2500')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Eggs — 1800')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Tomatoes — 600')],
      ),
      NoteBlock(
        id: noteUid(), type: NoteBlockType.checkbox, checked: false,
        segs: [NoteSeg(text: 'Total = 4900  ← auto-calculated')],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Rich Media', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🎙️ Voice notes', bold: true),
          NoteSeg(
            text: ' — tap the mic icon to record. Live waveform and timer '
                'while recording. Clips play inline. '
                'Faster than typing for quick thoughts.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '🖼️ Images', bold: true),
          NoteSeg(
            text: ' — take a photo or pick from gallery. '
                'Tap any image to open fullscreen. '
                'Tap ✕ to remove.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: '📄 PDFs', bold: true),
          NoteSeg(
            text: ' — attach any PDF. Card shows filename, page count, '
                'and file size. Tap Open to view in your PDF reader. '
                'Keep contracts, research papers, and receipts next to '
                'your notes about them.',
          ),
        ],
      ),

      if (auraPath != null)
        NoteBlock(
          id: noteUid(), type: NoteBlockType.image,
          imagePath: auraPath,
        ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Preview Mode & Saving', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Preview mode', bold: true),
          NoteSeg(
            text: ' hides the keyboard and renders a clean read-only view. '
                'All links become tappable. '
                'Tap Edit to return to writing.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Save', bold: true, color: const Color(0xFF34C759)),
          NoteSeg(
            text: ' button turns green when there are unsaved changes. '
                'Navigating back with changes pending saves automatically.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Clear', bold: true, color: const Color(0xFFFF3B30)),
          NoteSeg(
            text: ' permanently deletes the note after a confirmation. '
                'No undo — use deliberately.',
          ),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // 10. PUTTING IT ALL TOGETHER
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH1: true,
        segs: [NoteSeg(text: '⚡  The Full System at Work', bold: true,
            color: const Color(0xFFFF9F0A))],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        segs: [
          NoteSeg(text: 'Here\'s what a day with FocusBell looks like:'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '7:00 AM', bold: true,
              color: const Color(0xFFFFD60A)),
          NoteSeg(text: '  — Location alarm fires: '),
          NoteSeg(text: '"Leaving home 🏠"', italic: true),
          NoteSeg(text: ' as you step out. '
              'Your "Buy groceries on way home" reminder is waiting.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '9:00 AM', bold: true,
              color: const Color(0xFFFF9F0A)),
          NoteSeg(text: '  — You start a Deep Work session '
              'on your BriefBrew project. '
              'Focus Guard silently holds a "Check email" reminder '
              'that fires mid-session.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '9:40 AM', bold: true,
              color: const Color(0xFFFF453A)),
          NoteSeg(text: '  — You walk to the kitchen. '
              '50 metres breached. Focus nudge: '),
          NoteSeg(text: '"Come back. You were doing great." ',
              italic: true, color: const Color(0xFFFF453A)),
          NoteSeg(text: 'You return to your desk.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '10:00 AM', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: '  — Session complete. Held reminder surfaces. '
              'You snooze "Check email" to Tonight.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '1:00 PM', bold: true,
              color: const Color(0xFF64D2FF)),
          NoteSeg(text: '  — You open the app after lunch. '
              'Continuity brief: '),
          NoteSeg(
            text: '"Welcome back. You\'ve been away for 3 hours. '
                '\'Prayer\' is up in 8 minutes."',
            italic: true, color: Colors.white60,
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '6:00 PM', bold: true,
              color: const Color(0xFFBF5AF2)),
          NoteSeg(text: '  — You arrive at the supermarket. '
              'Location alarm: '),
          NoteSeg(text: '"Buy groceries 🛒"', italic: true),
          NoteSeg(text: '. You open your shopping note and '
              'check off items as the auto-total updates.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, orderedList: true,
        segs: [
          NoteSeg(text: '8:00 PM', bold: true,
              color: const Color(0xFF30D158)),
          NoteSeg(text: '  — You arrive home. Alarm fires: '),
          NoteSeg(text: '"Welcome home 🏠"', italic: true),
          NoteSeg(
              text: '. Your "Tonight: Check email" reminder fires at 9 PM.'),
        ],
      ),

      // ════════════════════════════════════════════════════════
      // FOOTER
      // ════════════════════════════════════════════════════════

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, isH2: true,
        segs: [NoteSeg(text: 'Tips for Power Users', bold: true)],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(text: 'Let group colours do the work', bold: true),
          NoteSeg(
            text: ' — you can scan the calendar dots and tile stripes '
                'without reading a word.',
          ),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(
              text: 'Use the Continuity brief as your daily entry point',
              bold: true),
          NoteSeg(text: ' — don\'t open reminders first. Let the brief '
              'tell you what matters.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(
              text: 'Save your most-used places immediately', bold: true),
          NoteSeg(text: ' — go to each location and tap '
              '"Use my current location" to capture it accurately.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(
              text: 'Use location reminders for habits', bold: true),
          NoteSeg(text: ' — "When I leave work → call Mum" costs zero '
              'mental effort to remember.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text, bulletList: true,
        segs: [
          NoteSeg(
              text: 'Use Focus Zone for deep work spaces', bold: true),
          NoteSeg(text: ' — sit at your dedicated desk, start a session. '
              'FocusBell knows if you drift.'),
        ],
      ),

      NoteBlock(
        id: noteUid(), type: NoteBlockType.text,
        align: NoteAlign.center,
        segs: [
          NoteSeg(
            text: '— FocusBell. Your cognitive co-pilot. —',
            italic: true,
            bold: true,
            color: const Color(0xFF64D2FF),
          ),
        ],
      ),

    ]; // end blocks

    final encoded = NoteBlock.encodeList(blocks);
    final welcome = StandaloneNote(
      id:        id,
      title:     'FocusBell — Complete Guide ✨',
      note:      encoded,
      createdAt: now,
      updatedAt: now,
      // Welcome note is never locked.
      isLocked:  false,
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
        'standalone_notes', orderBy: 'updated_at DESC');
    return rows.map(StandaloneNote.fromRow).toList();
  }

  /// Creates a blank note and tracks it.
  Future<StandaloneNote> createNote() async {
    final n  = StandaloneNote.blank();
    _notes   = [n, ..._notes];
    notifyListeners();

    final db = await _getDb();
    await db.insert('standalone_notes', n.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    ContinuityService.instance.track(
      ContinuityActionType.addedNote,
      detail: n.title.isEmpty ? 'Untitled note' : n.title,
    );
    return n;
  }

  /// Saves note content and tracks the edit.
  /// Skips tracking for the welcome/guide note to avoid cluttering the brief.
  Future<void> saveNote(String id, String title, String? note) async {
    final now = DateTime.now().toUtc();
    _notes = _notes.map((n) {
      if (n.id != id) return n;
      return n.copyWith(
        title: title, note: note,
        clearNote: note == null, updatedAt: now,
      );
    }).toList();
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();

    final updated = _notes.firstWhere((n) => n.id == id);
    final db = await _getDb();
    await db.update('standalone_notes', updated.toRow(),
        where: 'id = ?', whereArgs: [id]);

    final isGuide = id.endsWith('_welcome');
    if (!isGuide) {
      ContinuityService.instance.track(
        ContinuityActionType.editedNote,
        detail: title.isEmpty ? 'Untitled note' : title,
      );
    }
  }

  /// Toggles [isLocked] on a note without touching any other field.
  ///
  /// Follows the same minimal-field-update pattern used throughout the app
  /// (e.g. AppController.updateProjectLockState) to avoid re-encoding the
  /// entire NoteBlock payload just to flip one boolean.
  Future<void> updateNoteLockState(
    String id, {
    required bool isLocked,
  }) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx == -1) return;

    // Update in-memory list first for instant UI response.
    _notes[idx] = _notes[idx].copyWith(isLocked: isLocked);
    notifyListeners();

    // Persist only the is_locked column — no need to re-encode note content.
    final db = await _getDb();
    await db.update(
      'standalone_notes',
      {'is_locked': isLocked ? 1 : 0},
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a note.
  /// No continuity tracking on delete — deletions aren't surfaced in the brief.
  Future<void> deleteNote(String id) async {
    _notes = _notes.where((n) => n.id != id).toList();
    notifyListeners();
    final db = await _getDb();
    await db.delete('standalone_notes', where: 'id = ?', whereArgs: [id]);
  }

  StandaloneNote? find(String id) =>
      _notes.where((n) => n.id == id).firstOrNull;
}