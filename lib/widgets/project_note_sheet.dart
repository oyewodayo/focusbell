// ─────────────────────────────────────────────────────────────────────────────
// project_note_sheet.dart
//
// Root widget and State for the rich-note editor.
//
// Architecture — Dart mixin composition:
//   NoteStateInterface          shared abstract getters (state_interface.dart)
//   ProjectNoteActionsMixin     block CRUD, save, pickers, audio, links
//   ProjectNoteTextBlocksMixin  top bar, editor scaffold, text + checkbox UI
//   ProjectNoteMediaBlocksMixin image, audio, PDF, recording panel
//   ProjectNoteFormatBarMixin   format bar rows + bottom toolbar
//
// Each mixin declares `on State<ProjectNoteSheet> with NoteStateInterface`
// and accesses shared state via the abstract getters — no casting, no `dynamic`.
// _ProjectNoteSheetState simply declares each field and Dart satisfies the
// abstract getters automatically.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/services/note_rich_controller.dart';
import 'package:record/record.dart';

import '../models/project.dart';
import '../services/app_controller.dart';

import 'note_fullscreen_image.dart';

import 'project_note/project_note_state_interface.dart';
import 'project_note/project_note_actions_mixin.dart';
import 'project_note/project_note_text_blocks_mixin.dart';
import 'project_note/project_note_media_blocks_mixin.dart';
import 'project_note/project_note_format_bar_mixin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class ProjectNoteSheet extends StatefulWidget {
  final Project project;

  /// Save override used by standalone notes; project notes use AppController.
  final Future<void> Function(String title, String? note)? onSaveNote;

  /// Clear override used by standalone notes.
  final Future<void> Function()? onClearNote;

  const ProjectNoteSheet({
    super.key,
    required this.project,
    this.onSaveNote,
    this.onClearNote,
  });

  @override
  State<ProjectNoteSheet> createState() => _ProjectNoteSheetState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectNoteSheetState extends State<ProjectNoteSheet>
    with
        TickerProviderStateMixin,
        NoteStateInterface,       // abstract getters — satisfied by fields below
        ProjectNoteActionsMixin,
        ProjectNoteMediaBlocksMixin,
        ProjectNoteTextBlocksMixin,
        ProjectNoteFormatBarMixin {

  // ── Document ──────────────────────────────────────────────────────────────
  @override late List<NoteBlock> blocks;
  @override final Map<String, NoteRichController> ctrl = {};
  @override final Map<String, FocusNode> fn = {};
  @override final Map<String, GlobalKey> textKeys = {};

  @override String? activeId;
  @override bool dirty = false;
  @override String? fmtUrl;
  @override bool readOnly = false;

  // ── Title ─────────────────────────────────────────────────────────────────
  @override late TextEditingController titleCtrl;
  late FocusNode _titleFn; // private — only used in _buildTitleBlock

  // ── Format bar toggles ────────────────────────────────────────────────────
  @override bool showFormatBar = false;
  @override bool fmtBold = false;
  @override bool fmtItalic = false;
  @override bool fmtUnder = false;
  @override bool fmtStrike = false;
  @override bool fmtH1 = false;
  @override bool fmtH2 = false;
  @override bool fmtH3 = false;
  @override bool fmtH4 = false;
  @override Color? fmtColor;
  @override Color? fmtHighlight;
  @override NoteAlign fmtAlign = NoteAlign.left;
  @override bool fmtOL = false;
  @override bool fmtBL = false;

  // ── Checkbox total guard ──────────────────────────────────────────────────
  @override bool suppressTotalRecompute = false;
  @override Timer? totalDebounce;

  // ── Audio ─────────────────────────────────────────────────────────────────
  @override final AudioRecorder recorder = AudioRecorder();
  @override final AudioPlayer player = AudioPlayer();
  @override bool recording = false;
  @override String? currentlyPlayingId;
  @override Timer? positionPoller;
  @override final Map<String, bool> playing = {};
  @override final Map<String, Duration> playPos = {};
  @override final Map<String, Duration> playDur = {};

  @override Ticker? recTicker;
  @override Duration recElapsed = Duration.zero;
  @override DateTime? recStart;
  @override late AnimationController pulseCtrl;
  @override late Animation<double> pulseAnim;

  // ── Fullscreen image overlay ───────────────────────────────────────────────
  @override String? fullscreenImage;

  // ─────────────────────────────────────────────────────────────────────────
  // NoteStateInterface — convenience getters
  // ─────────────────────────────────────────────────────────────────────────

  @override
  NoteBlock? get activeBlock =>
      blocks.where((b) => b.id == activeId).firstOrNull;

  @override
  NoteRichController? get activeCtrl =>
      activeId != null ? ctrl[activeId] : null;

  // ─────────────────────────────────────────────────────────────────────────
  // NoteStateInterface — initBlock / refreshFmtBar / ensureTrailingTextBlock
  // (live here because they touch `setState` and all fields simultaneously)
  // ─────────────────────────────────────────────────────────────────────────

  /// Wires a [NoteRichController] and [FocusNode] for text / checkbox blocks.
  /// Media blocks need no controller and are skipped.
  @override
  void initBlock(NoteBlock b) {
    if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox) {
      return;
    }
    final c = NoteRichController(segs: List.from(b.segs));
    c.addListener(() {
      if (activeId == b.id && mounted) setState(() => refreshFmtBar(b, c));
    });
    ctrl[b.id] = c;
    textKeys[b.id] = GlobalKey();

    final f = FocusNode();
    f.addListener(() {
      if (f.hasFocus && mounted) {
        final isTotal = b.segs.isNotEmpty &&
            b.segs.first.text.trimLeft().startsWith('Checkbox Total:');
        setState(() {
          activeId = b.id;
          if (!isTotal) refreshFmtBar(b, c);
          else showFormatBar = false;
        });
      }
    });
    fn[b.id] = f;
  }

  /// Reads the current selection and block properties, then updates every
  /// `fmt*` field so the format bar re-renders correctly.
  @override
  void refreshFmtBar(NoteBlock b, NoteRichController c) {
    final sel = c.selection;
    final style = c.styleAt(sel);
    fmtBold = style['bold'] as bool;
    fmtItalic = style['italic'] as bool;
    fmtUnder = style['underline'] as bool;
    fmtStrike = style['strikethrough'] as bool;
    fmtColor = style['color'] as Color?;
    fmtHighlight = style['highlight'] as Color?;
    fmtUrl = style['url'] as String?;
    fmtAlign = b.align;
    fmtH1 = b.isH1; fmtH2 = b.isH2; fmtH3 = b.isH3; fmtH4 = b.isH4;
    fmtOL = b.orderedList;
    fmtBL = b.bulletList;
  }

  /// Guarantees the document always ends with a text block so the user can
  /// always tap below content to continue typing.
  @override
  void ensureTrailingTextBlock() {
    if (blocks.isEmpty || blocks.last.type != NoteBlockType.text) {
      final nb = NoteBlock(id: noteUid(), type: NoteBlockType.text);
      blocks.add(nb);
      initBlock(nb);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    blocks = NoteBlock.decodeList(widget.project.note);
    for (final b in blocks) initBlock(b);
    ensureTrailingTextBlock();

    titleCtrl = TextEditingController(text: widget.project.name);
    _titleFn = FocusNode();

    // Pulsing dot animation for the recording indicator.
    pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: pulseCtrl, curve: Curves.easeInOut),
    );

    // Listen to audio player events.
    player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      if (s == PlayerState.completed) {
        setState(() {
          if (currentlyPlayingId != null) {
            playing[currentlyPlayingId!] = false;
            playPos[currentlyPlayingId!] = Duration.zero;
            currentlyPlayingId = null;
          }
        });
      }
    });
    player.onPositionChanged.listen((pos) {
      if (!mounted || currentlyPlayingId == null) return;
      final prev = playPos[currentlyPlayingId!] ?? Duration.zero;
      if ((pos - prev).abs() >= const Duration(milliseconds: 100)) {
        setState(() => playPos[currentlyPlayingId!] = pos);
      }
    });
    player.onDurationChanged.listen((dur) {
      if (!mounted || currentlyPlayingId == null) return;
      setState(() => playDur[currentlyPlayingId!] = dur);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (blocks.isNotEmpty) fn[blocks.first.id]?.requestFocus();
    });
  }

  @override
  void dispose() {
    positionPoller?.cancel();
    for (final c in ctrl.values) c.dispose();
    for (final f in fn.values) f.dispose();
    titleCtrl.dispose();
    _titleFn.dispose();
    pulseCtrl.dispose();
    recTicker?.dispose();
    recorder.dispose();
    player.dispose();
    totalDebounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // While a fullscreen image is active, swap the whole scaffold for the viewer.
    if (fullscreenImage != null) {
      return NoteFullscreenImage(
        path: fullscreenImage!,
        onClose: () => setState(() => fullscreenImage = null),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0F),
      body: SafeArea(
        child: Column(
          children: [
            buildTopBar(),                                     // ProjectNoteTextBlocksMixin
            Expanded(child: buildEditor()),                    // ProjectNoteTextBlocksMixin
            if (recording) buildRecordingPanel(),              // ProjectNoteMediaBlocksMixin
            if (showFormatBar && !readOnly) buildFormatBar(),  // ProjectNoteFormatBarMixin
            if (!readOnly) buildBottomBar(),                   // ProjectNoteFormatBarMixin
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Pushes [ProjectNoteSheet] as a full-screen dialog route.
///
/// [onSaveNote] and [onClearNote] are optional overrides for standalone notes.
/// Project notes use the default [AppController]-based persistence.
void showProjectNoteSheet(
  BuildContext context, {
  required Project project,
  Future<void> Function(String title, String? note)? onSaveNote,
  Future<void> Function()? onClearNote,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ProjectNoteSheet(
      project: project,
      onSaveNote: onSaveNote,
      onClearNote: onClearNote,
    ),
  ));
}