// ─────────────────────────────────────────────────────────────────────────────
// project_note_format_bar_mixin.dart
//
// Builds the floating format toolbar + the persistent bottom toolbar:
//
//   buildFormatBar()  — 4-row scrollable toolbar above the keyboard:
//     Row 1  Heading chips  H1 / H2 / H3 / H4 / body
//     Row 2  Inline styles  B / I / U / S / link / align / lists
//     Row 3  Text colour swatches
//     Row 4  Highlight colour swatches
//
//   buildBottomBar()  — always-visible bar at the very bottom:
//     image | pdf | format-toggle | mic | checkbox
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';

import '../../widgets/note_toolbar_widgets.dart';
import 'project_note_state_interface.dart';
import 'project_note_actions_mixin.dart';

mixin ProjectNoteFormatBarMixin
    on State<ProjectNoteSheet>, NoteStateInterface, ProjectNoteActionsMixin {

  // ── Colour palette constants ───────────────────────────────────────────────

  /// Sentinel value for the "open custom HSV picker" slot.
  static const _kCustomColor = Color(0x00000001);

  static const _textColors = <Color?>[
    null,                  // Clear / default
    Color(0xFFFFFFFF),     // Pure white
    Color(0xFFE8E8E8),     // Soft white
    Color(0xFFCCCCCC),     // Light grey
    Color(0xFFAAAAAA),     // Mid grey
    Color(0xFF888888),     // Dim grey
    Color(0xFFFF3B30),     // Red
    Color(0xFFFF9F0A),     // Orange
    Color(0xFFFFD60A),     // Yellow
    Color(0xFF34C759),     // Green
    Color(0xFF0A84FF),     // Blue
    Color(0xFFBF5AF2),     // Purple
    Color(0xFFFF6B9D),     // Pink
    Color(0xFF64D2FF),     // Sky
    _kCustomColor,         // Custom picker
  ];

  static const _highlights = <Color?>[
    null,
    Color(0x66FFD60A), // Yellow
    Color(0x6634C759), // Green
    Color(0x660A84FF), // Blue
    Color(0x66FF3B30), // Red
    Color(0x66BF5AF2), // Purple
    Color(0x66FF9F0A), // Orange
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // Format bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget buildFormatBar() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        color: Color(0xFF141414),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1E1E)),
          bottom: BorderSide(color: Color(0xFF1E1E1E)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: heading style chips ──────────────────────────────────────
          _fmtRow([
            NoteTChip('H1', fmtH1, const Color(0xFFFF6B9D),
                () => applyParagraphFmt((b) { b.isH1 = !b.isH1; b.isH2 = b.isH3 = b.isH4 = false; })),
            NoteTChip('H2', fmtH2, const Color(0xFFFF9F0A),
                () => applyParagraphFmt((b) { b.isH2 = !b.isH2; b.isH1 = b.isH3 = b.isH4 = false; })),
            NoteTChip('H3', fmtH3, const Color(0xFFFFD60A),
                () => applyParagraphFmt((b) { b.isH3 = !b.isH3; b.isH1 = b.isH2 = b.isH4 = false; })),
            NoteTChip('H4', fmtH4, const Color(0xFF64D2FF),
                () => applyParagraphFmt((b) { b.isH4 = !b.isH4; b.isH1 = b.isH2 = b.isH3 = false; })),
            // "body" chip is active when no heading level is set.
            NoteTChip('body', !fmtH1 && !fmtH2 && !fmtH3 && !fmtH4, Colors.white,
                () => applyParagraphFmt((b) => b.isH1 = b.isH2 = b.isH3 = b.isH4 = false)),
          ]),

          // ── Row 2: inline styles + alignment + list toggles ─────────────────
          _fmtRow([
            NoteFBtn('B', bold: true,   active: fmtBold,
                onTap: () => applyInlineFmt((s) => s.bold = !s.bold)),
            NoteFBtn('I', italic: true, active: fmtItalic,
                onTap: () => applyInlineFmt((s) => s.italic = !s.italic)),
            NoteFBtn('U', under: true,  active: fmtUnder,
                onTap: () => applyInlineFmt((s) => s.underline = !s.underline)),
            NoteFBtn('S', strike: true, active: fmtStrike,
                onTap: () => applyInlineFmt((s) => s.strikethrough = !s.strikethrough)),
            NoteIBtn(Icons.link_rounded, fmtUrl != null && fmtUrl!.isNotEmpty, showLinkDialog),
            const NoteToolbarSep(),
            NoteIBtn(Icons.format_align_left_rounded,   fmtAlign == NoteAlign.left,
                () => applyParagraphFmt((b) => b.align = NoteAlign.left)),
            NoteIBtn(Icons.format_align_center_rounded, fmtAlign == NoteAlign.center,
                () => applyParagraphFmt((b) => b.align = NoteAlign.center)),
            NoteIBtn(Icons.format_align_right_rounded,  fmtAlign == NoteAlign.right,
                () => applyParagraphFmt((b) => b.align = NoteAlign.right)),
            const NoteToolbarSep(),
            NoteIBtn(Icons.format_list_numbered_rounded, fmtOL,
                () => applyParagraphFmt((b) { b.orderedList = !b.orderedList; b.bulletList = false; })),
            NoteIBtn(Icons.format_list_bulleted_rounded, fmtBL,
                () => applyParagraphFmt((b) { b.bulletList = !b.bulletList; b.orderedList = false; })),
          ]),

          // ── Row 3: text colour swatches ─────────────────────────────────────
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(child: Text('A',
                  style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700))),
            ),
            ..._textColors.map((c) => NoteColorDot(
              color: c == _kCustomColor ? null : c,
              selected: c == _kCustomColor
                  ? (fmtColor != null && !_textColors.contains(fmtColor))
                  : c == fmtColor,
              isCustom: c == _kCustomColor,
              customPreview: (fmtColor != null && !_textColors.contains(fmtColor)) ? fmtColor : null,
              onTap: () => c == _kCustomColor
                  ? showColorPicker(isHighlight: false)
                  : applyInlineFmt((s) => s.color = c),
            )),
          ]),

          // ── Row 4: highlight colour swatches ────────────────────────────────
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(child: Icon(Icons.highlight_rounded, size: 14, color: Colors.white38)),
            ),
            ..._highlights.map((c) => NoteColorDot(
              color: c,
              selected: c == fmtHighlight,
              onTap: () => applyInlineFmt((s) => s.highlight = c),
            )),
            // Custom highlight slot (opens HSV picker).
            NoteColorDot(
              color: null,
              isCustom: true,
              selected: fmtHighlight != null && !_highlights.contains(fmtHighlight),
              customPreview: (fmtHighlight != null && !_highlights.contains(fmtHighlight))
                  ? fmtHighlight : null,
              onTap: () => showColorPicker(isHighlight: true),
            ),
          ]),
        ],
      ),
    );
  }

  /// Wraps [children] in a horizontally scrollable 44-px-tall row with
  /// consistent horizontal padding.
  Widget _fmtRow(List<Widget> children) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      children: children,
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom toolbar
  // ─────────────────────────────────────────────────────────────────────────

  /// Persistent toolbar at the very bottom: insert media, toggle format bar,
  /// toggle recording, and add checkbox.
  Widget buildBottomBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0F),
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BarIcon(icon: CupertinoIcons.photo_fill_on_rectangle_fill, onTap: showImageOptions),
          _BarIcon(icon: Icons.picture_as_pdf_rounded, onTap: pickPdf),
          _BarIcon(
            icon: CupertinoIcons.textformat,
            active: showFormatBar,
            activeColor: const Color(0xFFFFD60A),
            onTap: () => setState(() => showFormatBar = !showFormatBar),
          ),
          _BarIcon(
            icon: CupertinoIcons.mic_solid,
            active: recording,
            activeColor: const Color(0xFFFF3B30),
            // While recording: tapping stops; while idle: tapping starts.
            onTap: recording ? stopRecording : toggleRecording,
          ),
          _BarIcon(icon: CupertinoIcons.checkmark_square, onTap: addCheckboxBlock),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BarIcon — icon button used in the bottom toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  /// Whether the button is in an "active" state (format bar open, recording).
  final bool active;

  /// Tint colour applied when [active] is true.
  final Color activeColor;

  const _BarIcon({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor = const Color(0xFF0A84FF),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52, height: 56,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 24, color: active ? activeColor : Colors.white60),
          ),
        ),
      ),
    );
  }
}