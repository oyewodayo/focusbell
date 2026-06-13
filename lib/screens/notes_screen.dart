// lib/screens/notes_screen.dart
//
// Standalone notes list — dark aesthetic matching ProjectNoteSheet.
// Each note is opened with the same rich ProjectNoteSheet editor.
// Backed by StandaloneNoteController (SQLite).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../models/note_models.dart';
import '../models/project.dart';
import '../models/standalone_note.dart';
import '../services/standalone_note_controller.dart';
import '../widgets/project_note_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotesScreen
// ─────────────────────────────────────────────────────────────────────────────

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = StandaloneNoteController.instance;
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _query = '';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

 @override
void initState() {
  super.initState();
  _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();
  _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  if (!_ctrl.ready) {
    _ctrl.boot();
  }
}

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────

  List<StandaloneNote> get _filtered {
    if (_query.trim().isEmpty) return _ctrl.notes;
    final q = _query.toLowerCase();
    return _ctrl.notes.where((n) {
      if (n.title.toLowerCase().contains(q)) return true;
      final preview = _extractPreview(n.note);
      return preview.toLowerCase().contains(q);
    }).toList();
  }

  /// Pulls a plain-text snippet from the NoteBlock JSON for the card preview.
  String _extractPreview(String? noteJson) {
    if (noteJson == null || noteJson.isEmpty) return '';
    try {
      final blocks = NoteBlock.decodeList(noteJson);
      final buf = StringBuffer();
      for (final b in blocks) {
        if (b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox) {
          final text = b.plainText.trim();
          if (text.isNotEmpty) {
            buf.write(text);
            buf.write(' ');
          }
        } else if (b.type == NoteBlockType.image) {
          buf.write('[Image] ');
        } else if (b.type == NoteBlockType.audio) {
          buf.write('[Voice note] ');
        } else if (b.type == NoteBlockType.pdf) {
          buf.write('[PDF: ${b.pdfName ?? 'document'}] ');
        }
        if (buf.length > 200) break;
      }
      return buf.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Returns block-type badges for the card (image / audio / pdf).
  List<_BlockBadge> _extractBadges(String? noteJson) {
    if (noteJson == null || noteJson.isEmpty) return [];
    try {
      final blocks = NoteBlock.decodeList(noteJson);
      final badges = <_BlockBadge>[];
      bool hasImg = false, hasAud = false, hasPdf = false, hasCbx = false;
      for (final b in blocks) {
        if (b.type == NoteBlockType.image && !hasImg) {
          badges.add(const _BlockBadge(
              icon: Icons.image_outlined,
              label: 'Photo',
              color: Color(0xFF64D2FF)));
          hasImg = true;
        } else if (b.type == NoteBlockType.audio && !hasAud) {
          badges.add(const _BlockBadge(
              icon: Icons.mic_outlined,
              label: 'Audio',
              color: Color(0xFF0A84FF)));
          hasAud = true;
        } else if (b.type == NoteBlockType.pdf && !hasPdf) {
          badges.add(const _BlockBadge(
              icon: Icons.picture_as_pdf_outlined,
              label: 'PDF',
              color: Color(0xFFFF6B9D)));
          hasPdf = true;
        } else if (b.type == NoteBlockType.checkbox && !hasCbx) {
          badges.add(const _BlockBadge(
              icon: CupertinoIcons.checkmark_square,
              label: 'Tasks',
              color: Color(0xFF34C759)));
          hasCbx = true;
        }
      }
      return badges;
    } catch (_) {
      return [];
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year}';
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _newNote() async {
    final note = await _ctrl.createNote();
    if (!mounted) return;
    _openNote(note);
  }

  void _openNote(StandaloneNote note) {
    // Build a throwaway Project shell so ProjectNoteSheet has something to
    // display. The callbacks intercept all save/clear calls.
    final shell = _buildShell(note);

    showProjectNoteSheet(
      context,
      project: shell,
      onSaveNote: (title, richNote) =>
          _ctrl.saveNote(note.id, title, richNote),
      onClearNote: () => _ctrl.deleteNote(note.id),
    );
  }

  Project _buildShell(StandaloneNote note) => Project(
        id:            note.id,
        name:          note.title.isEmpty ? 'Untitled' : note.title,
        description:   '',
        priority:      Priority.low,
        note:          note.note,
        noteUpdatedAt: note.updatedAt,
        createdAt:     note.createdAt,
      );

  Future<void> _deleteNote(StandaloneNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete note?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'This note will be permanently removed.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteNote(note.id);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0F),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) {
            return FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  _buildTopBar(),
                  if (_searching) _buildSearchBar(),
                  Expanded(child: _buildBody()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white.withValues(alpha: 0.6),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Notes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          if (_ctrl.notes.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_ctrl.notes.length}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          // Search toggle
          GestureDetector(
            onTap: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            }),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _searching
                    ? CupertinoIcons.xmark
                    : CupertinoIcons.search,
                color: _searching
                    ? const Color(0xFF64D2FF)
                    : Colors.white38,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // New note button
          GestureDetector(
            onTap: _newNote,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2A1C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF34C759).withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: Color(0xFF34C759), size: 14),
                  SizedBox(width: 4),
                  Text('New',
                      style: TextStyle(
                        color: Color(0xFF34C759),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.search,
              color: Colors.white24, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search notes…',
                hintStyle: TextStyle(color: Colors.white24),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchCtrl.clear();
              }),
              child: const Icon(CupertinoIcons.xmark_circle_fill,
                  color: Colors.white24, size: 16),
            ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────

  Widget _buildBody() {
    if (!_ctrl.ready) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Color(0xFF34C759),
        ),
      );
    }

    final notes = _filtered;

    if (notes.isEmpty && _ctrl.notes.isEmpty) {
      return _EmptyState(onNew: _newNote);
    }

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.search,
                color: Colors.white12, size: 36),
            const SizedBox(height: 12),
            Text(
              'No notes match "$_query"',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      itemCount: notes.length,
      itemBuilder: (ctx, i) {
        final note = notes[i];
        return _NoteCard(
          key: ValueKey(note.id),
          note: note,
          preview: _extractPreview(note.note),
          badges: _extractBadges(note.note),
          relTime: _relativeTime(note.updatedAt),
          onTap: () => _openNote(note),
          onDelete: () => _deleteNote(note),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NoteCard
// ─────────────────────────────────────────────────────────────────────────────

class _NoteCard extends StatefulWidget {
  final StandaloneNote note;
  final String preview;
  final List<_BlockBadge> badges;
  final String relTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteCard({
    super.key,
    required this.note,
    required this.preview,
    required this.badges,
    required this.relTime,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        widget.preview.isEmpty && (widget.note.title.isEmpty);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onDelete,
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) => setState(() => _pressing = false),
      onTapCancel: () => setState(() => _pressing = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressing
              ? const Color(0xFF1E1E20)
              : const Color(0xFF161618),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressing
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.note.title.isEmpty
                        ? 'Untitled'
                        : widget.note.title,
                    style: TextStyle(
                      color: widget.note.title.isEmpty
                          ? Colors.white24
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.relTime,
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(width: 10),
                // Delete button (subtle)
                GestureDetector(
                  onTap: widget.onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.more_horiz_rounded,
                        color: Colors.white24, size: 16),
                  ),
                ),
              ],
            ),

            // Preview
            if (!isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.preview.isEmpty
                    ? ''
                    : widget.preview,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Block-type badges
            if (widget.badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.badges
                    .map((b) => _BadgeChip(badge: b))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BlockBadge / _BadgeChip
// ─────────────────────────────────────────────────────────────────────────────

class _BlockBadge {
  final IconData icon;
  final String label;
  final Color color;
  const _BlockBadge(
      {required this.icon, required this.label, required this.color});
}

class _BadgeChip extends StatelessWidget {
  final _BlockBadge badge;
  const _BadgeChip({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: badge.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 10, color: badge.color),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: TextStyle(
              color: badge.color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon cluster
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A1A1A),
                    border: Border.all(color: Colors.white10),
                  ),
                ),
                const Icon(CupertinoIcons.square_pencil,
                    color: Colors.white24, size: 32),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'No notes yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Capture ideas, plans, voice memos,\nimages — anything worth keeping.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onNew,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2A1C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF34C759)
                          .withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Color(0xFF34C759), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'New Note',
                      style: TextStyle(
                        color: Color(0xFF34C759),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}