// ─────────────────────────────────────────────────────────────────────────────
// project_note_state_interface.dart
//
// Abstract getters / setters that every mixin in the project_note/ folder
// needs to access from _ProjectNoteSheetState.
//
// WHY THIS FILE EXISTS
// Dart mixins cannot reference private fields on the class they are mixed into
// unless those fields are exposed via abstract getters in the mixin's `on`
// constraint. Putting all the abstract declarations here in one interface mixin
// means each concrete mixin only needs `on State<ProjectNoteSheet> with NoteStateInterface`
// and immediately gets type-safe access to every shared field — no casting,
// no `dynamic`, no part-file gymnastics.
//
// _ProjectNoteSheetState satisfies the interface simply by declaring each
// field with the same name; Dart implicitly generates the required getter/setter.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/services/note_rich_controller.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:record/record.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Interface mixin
// ─────────────────────────────────────────────────────────────────────────────

mixin NoteStateInterface on State<ProjectNoteSheet> {
  // ── Document ──────────────────────────────────────────────────────────────
  List<NoteBlock> get blocks;
  Map<String, NoteRichController> get ctrl;
  Map<String, FocusNode> get fn;
  Map<String, GlobalKey> get textKeys;

  String? get activeId;
  set activeId(String? v);

  bool get dirty;
  set dirty(bool v);

  String? get fmtUrl;
  set fmtUrl(String? v);

  bool get readOnly;
  set readOnly(bool v);

  // ── Title ─────────────────────────────────────────────────────────────────
  TextEditingController get titleCtrl;

  // ── Format bar toggles ────────────────────────────────────────────────────
  bool get showFormatBar;
  set showFormatBar(bool v);

  bool get fmtBold;
  set fmtBold(bool v);
  bool get fmtItalic;
  set fmtItalic(bool v);
  bool get fmtUnder;
  set fmtUnder(bool v);
  bool get fmtStrike;
  set fmtStrike(bool v);

  bool get fmtH1;
  set fmtH1(bool v);
  bool get fmtH2;
  set fmtH2(bool v);
  bool get fmtH3;
  set fmtH3(bool v);
  bool get fmtH4;
  set fmtH4(bool v);

  Color? get fmtColor;
  set fmtColor(Color? v);
  Color? get fmtHighlight;
  set fmtHighlight(Color? v);

  NoteAlign get fmtAlign;
  set fmtAlign(NoteAlign v);

  bool get fmtOL;
  set fmtOL(bool v);
  bool get fmtBL;
  set fmtBL(bool v);

  // ── Checkbox total guard ──────────────────────────────────────────────────
  bool get suppressTotalRecompute;
  set suppressTotalRecompute(bool v);
  Timer? get totalDebounce;
  set totalDebounce(Timer? v);

  // ── Audio ─────────────────────────────────────────────────────────────────
  AudioRecorder get recorder;
  AudioPlayer get player;

  bool get recording;
  set recording(bool v);

  String? get currentlyPlayingId;
  set currentlyPlayingId(String? v);

  Timer? get positionPoller;
  set positionPoller(Timer? v);

  Map<String, bool> get playing;
  Map<String, Duration> get playPos;
  Map<String, Duration> get playDur;

  Ticker? get recTicker;
  set recTicker(Ticker? v);

  Duration get recElapsed;
  set recElapsed(Duration v);

  DateTime? get recStart;
  set recStart(DateTime? v);

  AnimationController get pulseCtrl;
  Animation<double> get pulseAnim;

  // ── Fullscreen image overlay ───────────────────────────────────────────────
  String? get fullscreenImage;
  set fullscreenImage(String? v);

  // ── Convenience getters (implemented on the State class) ──────────────────
  NoteBlock? get activeBlock;
  NoteRichController? get activeCtrl;

  // ── Methods that mixins call on the host State ────────────────────────────

  /// Wires controller + focus node for a new text/checkbox block.
  void initBlock(NoteBlock b);

  /// Refreshes all `fmt*` fields from the active block's current state.
  void refreshFmtBar(NoteBlock b, NoteRichController c);

  /// Guarantees a trailing empty text block always exists.
  void ensureTrailingTextBlock();

  // TickerProviderStateMixin method — available because the host State
  // mixes in TickerProviderStateMixin.
  Ticker createTicker(TickerCallback onTick);
}