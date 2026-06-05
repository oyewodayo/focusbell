import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Inline segment — one contiguous run of text with uniform formatting
// ─────────────────────────────────────────────────────────────────────────────

class _Seg {
  String text;
  bool bold;
  bool italic;
  bool underline;
  bool strikethrough;
  Color? color;
  Color? highlight; // background highlight colour

  _Seg({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
    this.highlight,
  });

  bool sameStyle(_Seg o) =>
      bold == o.bold &&
      italic == o.italic &&
      underline == o.underline &&
      strikethrough == o.strikethrough &&
      color == o.color &&
      highlight == o.highlight;

  _Seg copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    Color? color,
    bool clearColor = false,
    Color? highlight,
    bool clearHighlight = false,
  }) =>
      _Seg(
        text: text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        color: clearColor ? null : (color ?? this.color),
        highlight: clearHighlight ? null : (highlight ?? this.highlight),
      );

  Map<String, dynamic> toJson() => {
        'tx': text,
        if (bold) 'b': true,
        if (italic) 'i': true,
        if (underline) 'u': true,
        if (strikethrough) 's': true,
        if (color != null) 'c': color!.value,
        if (highlight != null) 'hl': highlight!.value,
      };

  factory _Seg.fromJson(Map<String, dynamic> j) => _Seg(
        text: j['tx'] as String? ?? '',
        bold: j['b'] as bool? ?? false,
        italic: j['i'] as bool? ?? false,
        underline: j['u'] as bool? ?? false,
        strikethrough: j['s'] as bool? ?? false,
        color: j['c'] != null ? Color(j['c'] as int) : null,
        highlight: j['hl'] != null ? Color(j['hl'] as int) : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RichTextController
// ─────────────────────────────────────────────────────────────────────────────
//
// Design: segs is the ONE source of truth for both text content and styling.
// The base TextEditingController.text is kept equal to segs.join() at all
// times via _rebuildText().  The TextField's onChanged callback is the ONLY
// place where we reconcile a user edit back into segs; we never override
// set value because Flutter calls that for cursor moves, selection, composing
// etc. — not just text changes.

class _RichController extends TextEditingController {
  List<_Seg> segs;

  _RichController({List<_Seg>? segs})
      : segs = segs ?? [] {
    // Seed base text from segs without triggering listeners.
    super.text = this.segs.map((s) => s.text).join();
  }

  // ── Called from TextField.onChanged ─────────────────────────
  // newText is exactly what the user typed / deleted / pasted.
  // We compute the minimal diff against the current segs plain-text and
  // update segs accordingly, preserving formatting outside the edit region.
void handleTextChange(String newText) {
  final oldText = segs.map((s) => s.text).join();
  if (newText == oldText) return;

  int pre = 0;
  while (pre < oldText.length &&
      pre < newText.length &&
      oldText[pre] == newText[pre]) {
    pre++;
  }

  int oldSuf = 0;
  final oldAvail = oldText.length - pre;
  final newAvail = newText.length - pre;
  final maxSuf = oldAvail < newAvail ? oldAvail : newAvail;
  while (oldSuf < maxSuf &&
      oldText[oldText.length - 1 - oldSuf] ==
          newText[newText.length - 1 - oldSuf]) {
    oldSuf++;
  }

  final delFrom = pre;
  final delTo = oldText.length - oldSuf;
  final inserted = newText.substring(pre, newText.length - oldSuf);

  _Seg inherit = segs.isNotEmpty ? segs.last : _Seg(text: '');
  int pos = 0;
  for (final s in segs) {
    final end = pos + s.text.length;
    if (pre >= pos && pre <= end) {
      inherit = s;
      break;
    }
    pos = end;
  }

  if (delFrom < delTo) segs = _del(segs, delFrom, delTo);
  if (inserted.isNotEmpty) segs = _ins(segs, delFrom, inserted, inherit);
  segs = _merge(segs);

  final plain = segs.map((s) => s.text).join();
  if (plain != newText) {
    segs = [_Seg(text: newText)];
  }

  rebuildText();
}
  // ── Called after applyToRange / external segs mutations ──────
  // Pushes the current segs plain-text back into the base controller
  // so the TextField re-renders the new spans.
  void rebuildText() {
    final plain = segs.map((s) => s.text).join();
    // Preserve cursor position — don't move it.
    final sel = selection;
    super.value = TextEditingValue(
      text: plain,
      selection: sel.isValid
          ? TextSelection.collapsed(
              offset: sel.baseOffset.clamp(0, plain.length))
          : TextSelection.collapsed(offset: plain.length),
    );
  }

  // ── Segment list operations ──────────────────────────────────

  static List<_Seg> _del(List<_Seg> segs, int from, int to) {
    final out = <_Seg>[];
    int pos = 0;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (end <= from || pos >= to) {
        out.add(s);
      } else {
        final bLen = (from - pos).clamp(0, s.text.length);
        final aStart = (to - pos).clamp(0, s.text.length);
        if (bLen > 0) out.add(s.copyWith(text: s.text.substring(0, bLen)));
        if (aStart < s.text.length) out.add(s.copyWith(text: s.text.substring(aStart)));
      }
      pos = end;
    }
    return out;
  }

  static List<_Seg> _ins(List<_Seg> segs, int at, String text, _Seg style) {
    if (segs.isEmpty) return [style.copyWith(text: text)];
    final out = <_Seg>[];
    int pos = 0;
    bool done = false;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (!done && at >= pos && at <= end) {
        final split = at - pos;
        if (split > 0) out.add(s.copyWith(text: s.text.substring(0, split)));
        // Inherit surrounding segment style for new chars
        final newSeg = s.sameStyle(style) ? s.copyWith(text: text) : style.copyWith(text: text);
        out.add(newSeg);
        if (split < s.text.length) out.add(s.copyWith(text: s.text.substring(split)));
        done = true;
      } else {
        out.add(s);
      }
      pos = end;
    }
    if (!done) out.add(style.copyWith(text: text));
    return out;
  }

  static List<_Seg> _merge(List<_Seg> segs) {
    final out = <_Seg>[];
    for (final s in segs) {
      if (s.text.isEmpty) continue;
      if (out.isNotEmpty && out.last.sameStyle(s)) {
        final prev = out.removeLast();
        out.add(prev.copyWith(text: prev.text + s.text));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  // ── Apply formatting to a character range ────────────────────

  void applyToRange(int start, int end, void Function(_Seg s) fn) {
    if (start >= end) return;
    segs = _splitAt(_splitAt(segs, start), end);
    int pos = 0;
    for (final s in segs) {
      final sEnd = pos + s.text.length;
      if (pos >= start && sEnd <= end) fn(s);
      pos = sEnd;
    }
    segs = _merge(segs);
    if (segs.isEmpty) segs = [_Seg(text: '')];
  }

  static List<_Seg> _splitAt(List<_Seg> segs, int at) {
    final out = <_Seg>[];
    int pos = 0;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (at > pos && at < end) {
        final split = at - pos;
        out.add(s.copyWith(text: s.text.substring(0, split)));
        out.add(s.copyWith(text: s.text.substring(split)));
      } else {
        out.add(s);
      }
      pos = end;
    }
    return out;
  }

  // ── Formatting state at cursor / selection ────────────────────

  Map<String, dynamic> styleAt(TextSelection sel) {
    final start = sel.isCollapsed ? sel.baseOffset     : sel.start;
    final end   = sel.isCollapsed ? sel.baseOffset + 1 : sel.end;
    bool bold = false, italic = false, under = false, strike = false;
    Color? color, highlight;
    int pos = 0;
    for (final s in segs) {
      final sEnd = pos + s.text.length;
      if (sEnd > start && pos < end) {
        bold      = bold      || s.bold;
        italic    = italic    || s.italic;
        under     = under     || s.underline;
        strike    = strike    || s.strikethrough;
        color     ??= s.color;
        highlight ??= s.highlight;
      }
      pos = sEnd;
    }
    return {
      'bold': bold, 'italic': italic, 'underline': under,
      'strikethrough': strike, 'color': color, 'highlight': highlight,
    };
  }

  // ── Render ────────────────────────────────────────────────────

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (segs.isEmpty) return TextSpan(text: '', style: style);
    return TextSpan(
      style: style,
      children: segs.map((s) => TextSpan(
        text: s.text,
        style: TextStyle(
          fontWeight:  s.bold          ? FontWeight.w700  : FontWeight.w400,
          fontStyle:   s.italic        ? FontStyle.italic : FontStyle.normal,
          color:       s.color,
          backgroundColor: s.highlight,
          decoration: TextDecoration.combine([
            if (s.underline)      TextDecoration.underline,
            if (s.strikethrough)  TextDecoration.lineThrough,
          ]),
        ),
      )).toList(),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Block types
// ─────────────────────────────────────────────────────────────────────────────

enum NoteBlockType { text, image, audio, checkbox, pdf }

enum NoteAlign { left, center, right }

// ─────────────────────────────────────────────────────────────────────────────
// NoteBlock
// ─────────────────────────────────────────────────────────────────────────────

class NoteBlock {
  final String id;
  final NoteBlockType type;

  // text / checkbox
  List<_Seg> segs; // rich segments
  NoteAlign align;
  bool orderedList;
  bool bulletList;
  bool isH1, isH2, isH3, isH4; // paragraph-level heading style

  // image
  String? imagePath;

  // audio
  String? audioPath;
  Duration audioDuration;

  // pdf
    String? pdfPath;
    String? pdfName;
    int     pdfSizeBytes;
    int     pdfPageCount;

  // checkbox
  bool checked;

  NoteBlock({
    required this.id,
    this.type = NoteBlockType.text,
    List<_Seg>? segs,
    this.align = NoteAlign.left,
    this.orderedList = false,
    this.bulletList = false,
    this.isH1 = false,
    this.isH2 = false,
    this.isH3 = false,
    this.isH4 = false,
    this.imagePath,
    this.audioPath,
    this.audioDuration = Duration.zero,
    this.checked = false,
    this.pdfPath,
    this.pdfName,
    this.pdfSizeBytes = 0,
    this.pdfPageCount = 0,
  }) : segs = segs ?? [];

  String get plainText => segs.map((s) => s.text).join();

  double get fontSize {
    if (isH1) return 26;
    if (isH2) return 22;
    if (isH3) return 18;
    if (isH4) return 15;
    return 14;
  }

  TextStyle get baseStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: fontSize,
        fontWeight: (isH1 || isH2 || isH3 || isH4) ? FontWeight.w700 : FontWeight.w400,
        height: 1.5,
      );

  // ── Serialisation ─────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'segs': segs.map((s) => s.toJson()).toList(),
        'al': align.index,
        'ol': orderedList,
        'bl': bulletList,
        if (isH1) 'h1': true,
        if (isH2) 'h2': true,
        if (isH3) 'h3': true,
        if (isH4) 'h4': true,
        if (imagePath != null) 'img': imagePath,
        if (audioPath != null) 'aud': audioPath,
        if (pdfPath != null) 'pdf': pdfPath,
        if (pdfName != null) 'pdfn': pdfName,
        if (pdfSizeBytes > 0) 'pdfsz': pdfSizeBytes,
        if (pdfPageCount > 0) 'pdfpg': pdfPageCount,
                'dur': audioDuration.inMilliseconds,
        'chk': checked,
        // Legacy plain-text field for backward compat
        'tx': plainText,
      };

  factory NoteBlock.fromJson(Map<String, dynamic> j) {
    // Support both new segs format and old span/plain-text format.
    final segsRaw = j['segs'] as List<dynamic>?;
    
    List<_Seg> segs;
    if (segsRaw != null && segsRaw.isNotEmpty) {
      segs = segsRaw
          .map((e) => _Seg.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Migrate from old NoteSpan format.
      final spansRaw = j['sp'] as List<dynamic>?;
      if (spansRaw != null && spansRaw.isNotEmpty) {
        segs = spansRaw.map((e) {
          final m = e as Map<String, dynamic>;
          return _Seg(
            text: m['tx'] as String? ?? '',
            bold: m['b'] as bool? ?? false,
            italic: m['i'] as bool? ?? false,
            underline: m['u'] as bool? ?? false,
            strikethrough: m['s'] as bool? ?? false,
            color: m['c'] != null ? Color(m['c'] as int) : null,
          );
        }).toList();
      } else {
        final plain = j['tx'] as String? ?? '';
        segs = plain.isNotEmpty ? [_Seg(text: plain)] : [];
      }
    }
    return NoteBlock(
      id: j['id'] as String,
      type: NoteBlockType.values[j['type'] as int? ?? 0],
      segs: segs,
      align: NoteAlign.values[j['al'] as int? ?? 0],
      orderedList: j['ol'] as bool? ?? false,
      bulletList: j['bl'] as bool? ?? false,
      isH1: j['h1'] as bool? ?? false,
      isH2: j['h2'] as bool? ?? false,
      isH3: j['h3'] as bool? ?? false,
      isH4: j['h4'] as bool? ?? false,
      imagePath: j['img'] as String?,
      audioPath: j['aud'] as String?,
      audioDuration: Duration(milliseconds: j['dur'] as int? ?? 0),
      checked: j['chk'] as bool? ?? false,
      pdfPath:      j['pdf']   as String?,
        pdfName:      j['pdfn']  as String?,
        pdfSizeBytes: j['pdfsz'] as int? ?? 0,
        pdfPageCount: j['pdfpg'] as int? ?? 0,
    );
  }

  static String encodeList(List<NoteBlock> blocks) =>
      jsonEncode(blocks.map((b) => b.toJson()).toList());

  static List<NoteBlock> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [NoteBlock(id: _uid())];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => NoteBlock.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [NoteBlock(id: _uid())];
    }
  }
}

int _c = 0;
String _uid() => '${DateTime.now().millisecondsSinceEpoch}_${_c++}';

// ─────────────────────────────────────────────────────────────────────────────
// ProjectNoteSheet
// ─────────────────────────────────────────────────────────────────────────────

class ProjectNoteSheet extends StatefulWidget {
  final Project project;
  const ProjectNoteSheet({super.key, required this.project});

  @override
  State<ProjectNoteSheet> createState() => _ProjectNoteSheetState();
}

class _ProjectNoteSheetState extends State<ProjectNoteSheet>
    with TickerProviderStateMixin {
  // ── Document ────────────────────────────────────────────────
  late List<NoteBlock> _blocks;
  final Map<String, _RichController> _ctrl = {};
  final Map<String, FocusNode> _fn = {};
  String? _activeId;
  bool _dirty = false;

  // ── Title ────────────────────────────────────────────────────
  late TextEditingController _titleCtrl;
  late FocusNode _titleFn;

  // ── Format bar state ─────────────────────────────────────────
  bool _showFormatBar = false;

  // Mirrors the selection-based formatting state for toolbar UI.
  bool _fmtBold = false;
  bool _fmtItalic = false;
  bool _fmtUnder = false;
  bool _fmtStrike = false;
  bool _fmtH1 = false, _fmtH2 = false, _fmtH3 = false, _fmtH4 = false;
  Color? _fmtColor;
  Color? _fmtHighlight;
  NoteAlign _fmtAlign = NoteAlign.left;
  bool _fmtOL = false;
  bool _fmtBL = false;

  // ── Colour palettes ──────────────────────────────────────────
  static const _textColors = <Color?>[
    null,
    Color(0xFFFFFFFF),
    Color(0xFFFF3B30),
    Color(0xFFFF9F0A),
    Color(0xFFFFD60A),
    Color(0xFF34C759),
    Color(0xFF0A84FF),
    Color(0xFFBF5AF2),
    Color(0xFFFF6B9D),
    Color(0xFF64D2FF),
  ];

  static const _highlights = <Color?>[
    null,
    Color(0x66FFD60A),
    Color(0x6634C759),
    Color(0x660A84FF),
    Color(0x66FF3B30),
    Color(0x66BF5AF2),
    Color(0x66FF9F0A),
  ];

  // ── Audio ────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  final Map<String, bool> _playing = {};
  final Map<String, Duration> _playPos = {};

  // ── Fullscreen image ─────────────────────────────────────────
  String? _fullscreenImage;

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _blocks = NoteBlock.decodeList(widget.project.note);
    for (final b in _blocks) _initBlock(b);

    _titleCtrl = TextEditingController(text: widget.project.name);
    _titleFn = FocusNode();

    _player.onPlayerStateChanged.listen((s) {
      if (s == PlayerState.completed && mounted) {
        setState(() {
          for (final k in _playing.keys.toList()) _playing[k] = false;
        });
      }
    });
    _player.onPositionChanged.listen((pos) {
      if (_activeId != null && mounted) setState(() => _playPos[_activeId!] = pos);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_blocks.isNotEmpty) _fn[_blocks.first.id]?.requestFocus();
    });
  }

  void _initBlock(NoteBlock b) {
    if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox) return;

    final ctrl = _RichController(segs: List.from(b.segs));

    // The listener only refreshes the toolbar UI state — text/segs sync
    // is handled by the onChanged callback on the TextField itself.
    ctrl.addListener(() {
      if (_activeId == b.id && mounted) setState(() => _refreshFmtBar(b, ctrl));
    });

    _ctrl[b.id] = ctrl;

    final fn = FocusNode();
    fn.addListener(() {
      if (fn.hasFocus && mounted) {
        setState(() {
          _activeId = b.id;
          _refreshFmtBar(b, ctrl);
        });
      }
    });
    _fn[b.id] = fn;
  }

  void _refreshFmtBar(NoteBlock b, _RichController ctrl) {
    final sel = ctrl.selection;
    final style = ctrl.styleAt(sel);
    _fmtBold = style['bold'] as bool;
    _fmtItalic = style['italic'] as bool;
    _fmtUnder = style['underline'] as bool;
    _fmtStrike = style['strikethrough'] as bool;
    _fmtColor = style['color'] as Color?;
    _fmtHighlight = style['highlight'] as Color?;
    _fmtAlign = b.align;
    _fmtH1 = b.isH1;
    _fmtH2 = b.isH2;
    _fmtH3 = b.isH3;
    _fmtH4 = b.isH4;
    _fmtOL = b.orderedList;
    _fmtBL = b.bulletList;
  }

  NoteBlock? get _active => _blocks.where((b) => b.id == _activeId).firstOrNull;
  _RichController? get _activeCtrl => _activeId != null ? _ctrl[_activeId] : null;

  // ─────────────────────────────────────────────────────────────
  // Inline formatting (applied to selected range or whole block)
  // ─────────────────────────────────────────────────────────────

  void _applyInlineFmt(void Function(_Seg s) fn) {
    final b = _active;
    final ctrl = _activeCtrl;
    if (b == null || ctrl == null) return;

    final sel = ctrl.selection;
    int start, end;
    if (sel.isValid && !sel.isCollapsed) {
      start = sel.start;
      end = sel.end;
    } else {
      // No selection → apply to whole block.
      start = 0;
      end = ctrl.text.length;
    }

    setState(() {
      ctrl.applyToRange(start, end, fn);
      b.segs = List.from(ctrl.segs);
      ctrl.rebuildText(); // refresh the span tree without corrupting _prevText
      _refreshFmtBar(b, ctrl);
      _dirty = true;
    });
  }

  void _applyParagraphFmt(void Function(NoteBlock b) fn) {
    final b = _active;
    if (b == null) return;
    setState(() {
      fn(b);
      final ctrl = _activeCtrl;
      if (ctrl != null) _refreshFmtBar(b, ctrl);
      _dirty = true;
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Block management
  // ─────────────────────────────────────────────────────────────

  void _addTextBlockAfter(String afterId) {
    final idx = _blocks.indexWhere((b) => b.id == afterId);
    final nb = NoteBlock(id: _uid(), type: NoteBlockType.text);
    _blocks.insert(idx + 1, nb);
    _initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fn[nb.id]?.requestFocus());
  }

  void _addCheckboxBlock() {
    final nb = NoteBlock(id: _uid(), type: NoteBlockType.checkbox);
    final idx = _activeId == null
        ? _blocks.length
        : _blocks.indexWhere((b) => b.id == _activeId) + 1;
    _blocks.insert(idx, nb);
    _initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fn[nb.id]?.requestFocus());
  }

    void _removeBlock(String id) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx == -1) return;

    final block = _blocks[idx]; // ← capture before any mutation

    // If this is the only text block, just clear it.
    final textBlocks = _blocks.where(
        (b) => b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox);
    if (_blocks.length <= 1 ||
        (textBlocks.length == 1 && textBlocks.first.id == id)) {
        final ctrl = _ctrl[id];
        if (ctrl != null) {
        ctrl.segs = [];
        ctrl.text = '';
        _blocks[idx].segs = [];
        }
        setState(() => _dirty = true);
        return;
    }

    // Clean up copied PDF file before removing the block.
    if (block.type == NoteBlockType.pdf && block.pdfPath != null) {
        File(block.pdfPath!).delete().catchError((_) {});
    }

    setState(() {
        _ctrl[id]?.dispose();
        _fn[id]?.dispose();
        _ctrl.remove(id);
        _fn.remove(id);
        _blocks.removeAt(idx);
    });

    // Focus the nearest preceding text/checkbox block, or the next one.
    final focusIdx = (idx - 1).clamp(0, _blocks.length - 1);
    final targetId = _blocks[focusIdx].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
        _fn[targetId]?.requestFocus();
        final c = _ctrl[targetId];
        if (c != null) {
        c.selection = TextSelection.collapsed(offset: c.text.length);
        }
    });
    }
  // ─────────────────────────────────────────────────────────────
  // Image picker
  // ─────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;

    final imgBlock = NoteBlock(
        id: _uid(), type: NoteBlockType.image, imagePath: file.path);
    // Always add a text block after the image so the user can keep writing.
    final textAfter = NoteBlock(id: _uid(), type: NoteBlockType.text);
    final idx = _activeId == null
        ? _blocks.length
        : _blocks.indexWhere((b) => b.id == _activeId) + 1;

    setState(() {
      _blocks.insert(idx, imgBlock);
      _blocks.insert(idx + 1, textAfter);
      _dirty = true;
    });
    _initBlock(textAfter);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fn[textAfter.id]?.requestFocus());
  }

  Future<void> _pickPdf() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: false,
    withReadStream: false,
  );
  if (result == null || result.files.isEmpty) return;

  final picked = result.files.first;
  if (picked.path == null) return;

  // Copy into app documents so it survives external moves/deletions.
  final docsDir = await getApplicationDocumentsDirectory();
  final destName =
      '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
  final destPath = '${docsDir.path}/$destName';
  await File(picked.path!).copy(destPath);

  // Best-effort page count via byte scan (fast, no heavy dependency).
  int pageCount = 0;
  try {
    final bytes = await File(destPath).readAsBytes();
    final content = String.fromCharCodes(bytes);
    final matches = RegExp(r'/Type\s*/Page[^s]').allMatches(content);
    pageCount = matches.length;
  } catch (_) {}

  final pdfBlock = NoteBlock(
    id:           _uid(),
    type:         NoteBlockType.pdf,
    pdfPath:      destPath,
    pdfName:      picked.name,
    pdfSizeBytes: picked.size,
    pdfPageCount: pageCount,
  );
  final textAfter = NoteBlock(id: _uid(), type: NoteBlockType.text);

  final idx = _activeId == null
      ? _blocks.length
      : _blocks.indexWhere((b) => b.id == _activeId) + 1;

  setState(() {
    _blocks.insert(idx, pdfBlock);
    _blocks.insert(idx + 1, textAfter);
    _dirty = true;
  });
  _initBlock(textAfter);
  WidgetsBinding.instance
      .addPostFrameCallback((_) => _fn[textAfter.id]?.requestFocus());
}

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: Color(0xFF0A84FF)),
              title: const Text('Take Photo',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF0A84FF)),
              title: const Text('Choose Photo',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Audio
  // ─────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;

      final audioBlock =
          NoteBlock(id: _uid(), type: NoteBlockType.audio, audioPath: path);
      final textAfter = NoteBlock(id: _uid(), type: NoteBlockType.text);
      final idx = _activeId == null
          ? _blocks.length
          : _blocks.indexWhere((b) => b.id == _activeId) + 1;

      setState(() {
        _blocks.insert(idx, audioBlock);
        _blocks.insert(idx + 1, textAfter);
        _dirty = true;
      });
      _initBlock(textAfter);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _fn[textAfter.id]?.requestFocus());
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/note_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      setState(() => _recording = true);
    }
  }

  Future<void> _togglePlayback(NoteBlock b) async {
    final isPlaying = _playing[b.id] ?? false;
    if (isPlaying) {
      await _player.pause();
      setState(() => _playing[b.id] = false);
    } else {
      for (final k in _playing.keys.toList()) _playing[k] = false;
      await _player.play(DeviceFileSource(b.audioPath!));
      setState(() {
        _playing[b.id] = true;
        _activeId = b.id;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Save / clear
  // ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Flush controller state to blocks before encoding.
    for (final b in _blocks) {
      if (_ctrl[b.id] != null) b.segs = List.from(_ctrl[b.id]!.segs);
    }
    final trimmed = _blocks.length > 1
        ? (_blocks.toList()
          ..removeWhere((b) =>
              b == _blocks.last &&
              b.type == NoteBlockType.text &&
              b.plainText.trim().isEmpty))
        : _blocks;
    final encoded = NoteBlock.encodeList(trimmed);
    await AppController.instance.updateProjectNote(widget.project.id, encoded);
    if (mounted) {
      AppToast.show(context,
          msg: 'Note saved',
          backgroundColor: const Color(0xFF0A1F0A),
          textColor: const Color(0xFF34C759));
    }
    setState(() => _dirty = false);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Clear note?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text('All note content will be removed.',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear',
                style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppController.instance.updateProjectNote(widget.project.id, null);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) c.dispose();
    for (final f in _fn.values) f.dispose();
    _titleCtrl.dispose();
    _titleFn.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_fullscreenImage != null) {
      return _FullscreenImage(
          path: _fullscreenImage!,
          onClose: () => setState(() => _fullscreenImage = null));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildEditor()),
            if (_showFormatBar) _buildFormatBar(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Top bar
  // ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E)))),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_dirty) await _save();
              if (mounted) Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: widget.project.priority.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: widget.project.priority.color.withValues(alpha: 0.5),
                    blurRadius: 5)
              ],
            ),
          ),
          Expanded(
            child: Text(
              widget.project.noteUpdatedAt != null
                  ? _fmtDate(widget.project.noteUpdatedAt!)
                  : 'New note',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          if (widget.project.hasNote)
            GestureDetector(
              onTap: _clear,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0A0A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.3)),
                ),
                child: const Text('Clear',
                    style: TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          GestureDetector(
            onTap: _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _dirty
                    ? const Color(0xFF34C759)
                    : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: _dirty
                        ? const Color(0xFF34C759).withValues(alpha: 0.5)
                        : Colors.white10),
              ),
              child: Text('Save',
                  style: TextStyle(
                      color: _dirty ? Colors.black : Colors.white30,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Editor
  // ─────────────────────────────────────────────────────────────

  Widget _buildEditor() {
    return GestureDetector(
      onTap: () {
        // Tap on empty space below content → focus last text-input block.
        final last = _blocks.lastWhere(
          (b) =>
              b.type == NoteBlockType.text ||
              b.type == NoteBlockType.checkbox,
          orElse: () => _blocks.last,
        );
        _fn[last.id]?.requestFocus();
        final c = _ctrl[last.id];
        if (c != null) {
          c.selection =
              TextSelection.collapsed(offset: c.text.length);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        itemCount: _blocks.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildTitleBlock();
          final b = _blocks[i - 1];
          return _buildBlock(b, i - 1);
        },
      ),
    );
  }

  Widget _buildTitleBlock() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _titleCtrl,
        focusNode: _titleFn,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.3),
        decoration: const InputDecoration(
          hintText: 'Title',
          hintStyle: TextStyle(
              color: Colors.white24,
              fontSize: 26,
              fontWeight: FontWeight.w700),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        onChanged: (_) => setState(() => _dirty = true),
      ),
    );
  }

  Widget _buildBlock(NoteBlock b, int index) {
    return switch (b.type) {
      NoteBlockType.text => _buildTextBlock(b, index),
      NoteBlockType.checkbox => _buildCheckboxBlock(b, index),
      NoteBlockType.image => _buildImageBlock(b),
      NoteBlockType.audio => _buildAudioBlock(b),
      NoteBlockType.pdf      => _buildPdfBlock(b),
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Text block — full native editing: cursor anywhere, delete, select
  // ─────────────────────────────────────────────────────────────

  Widget _buildTextBlock(NoteBlock b, int index) {
    final baseStyle = b.baseStyle;
    final prefix = b.orderedList
        ? '${index + 1}.  '
        : b.bulletList
            ? '•  '
            : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prefix.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text(prefix,
                  style: baseStyle.copyWith(color: Colors.white38)),
            ),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _ctrl[b.id]?.text.isEmpty == true) {
                  _removeBlock(b.id);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _ctrl[b.id],
                focusNode: _fn[b.id],
                maxLines: null,
                // Selection is fully enabled — the system handles it.
                enableInteractiveSelection: true,
                selectionControls: MaterialTextSelectionControls(),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textAlign: switch (b.align) {
                  NoteAlign.left => TextAlign.left,
                  NoteAlign.center => TextAlign.center,
                  NoteAlign.right => TextAlign.right,
                },
                style: baseStyle,
                onChanged: (t) {
                  final ctrl = _ctrl[b.id];
                  if (ctrl == null) return;
                  ctrl.handleTextChange(t);
                  b.segs = List.from(ctrl.segs);
                  if (!_dirty) setState(() => _dirty = true);
                },
                onSubmitted: (_) => _addTextBlockAfter(b.id),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText:
                      (_activeId == b.id && _blocks.length == 1)
                          ? 'Start typing…'
                          : null,
                  hintStyle: const TextStyle(
                      color: Colors.white12, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Checkbox block
  // ─────────────────────────────────────────────────────────────

  Widget _buildCheckboxBlock(NoteBlock b, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              b.checked = !b.checked;
              _dirty = true;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: b.checked ? const Color(0xFF34C759) : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: b.checked
                        ? const Color(0xFF34C759)
                        : Colors.white30,
                    width: 1.5),
              ),
              child: b.checked
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.black)
                  : null,
            ),
          ),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _ctrl[b.id]?.text.isEmpty == true) {
                  _removeBlock(b.id);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _ctrl[b.id],
                focusNode: _fn[b.id],
                maxLines: null,
                enableInteractiveSelection: true,
                selectionControls: MaterialTextSelectionControls(),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (t) {
                  final ctrl = _ctrl[b.id];
                  if (ctrl == null) return;
                  ctrl.handleTextChange(t);
                  b.segs = List.from(ctrl.segs);
                  if (!_dirty) setState(() => _dirty = true);
                },
                onSubmitted: (_) => _addTextBlockAfter(b.id),
                style: TextStyle(
                  color: b.checked
                      ? Colors.white30
                      : Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  height: 1.5,
                  decoration: b.checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'To-do item',
                  hintStyle:
                      TextStyle(color: Colors.white12, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Image block — tap → fullscreen; ✕ button to delete
  // ─────────────────────────────────────────────────────────────

  Widget _buildImageBlock(NoteBlock b) {
    return GestureDetector(
      onTap: () => setState(() => _fullscreenImage = b.imagePath),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.file(
              File(b.imagePath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white24, size: 40),
              ),
            ),
            // ✕ delete button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _confirmRemoveBlock(b),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
            // Expand hint
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_full_rounded,
                        size: 11, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('View',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Audio block — with inline ✕ delete
  // ─────────────────────────────────────────────────────────────

  Widget _buildAudioBlock(NoteBlock b) {
    final isPlaying = _playing[b.id] ?? false;
    final pos = _playPos[b.id] ?? Duration.zero;
    final dur = b.audioDuration;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isPlaying
                ? const Color(0xFF0A84FF).withValues(alpha: 0.5)
                : Colors.white10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _togglePlayback(b),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFF0A84FF)
                    : const Color(0xFF252525),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.toDouble(),
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${_fmtDur(pos)} / ${_fmtDur(dur)}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.mic_rounded, color: Colors.white24, size: 16),
          const SizedBox(width: 8),
          // ✕ delete button
          GestureDetector(
            onTap: () => _confirmRemoveBlock(b),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }


    Widget _buildPdfBlock(NoteBlock b) {
        final name      = b.pdfName ?? 'document.pdf';
        final sizeLabel = _fmtBytes(b.pdfSizeBytes);
        final pageLabel = b.pdfPageCount > 0
            ? '${b.pdfPageCount} page${b.pdfPageCount == 1 ? '' : 's'}'
            : 'PDF';

        return GestureDetector(
        onTap: () async {
        if (b.pdfPath != null) await OpenFilex.open(b.pdfPath!);
        },
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.25)),
        ),
        child: Row(
            children: [
            // PDF icon badge
            Container(
                width: 42,
                height: 50,
                decoration: BoxDecoration(
                color: const Color(0xFF2E0A18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFF6B9D).withValues(alpha: 0.4)),
                ),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                    Icon(Icons.picture_as_pdf_rounded,
                        color: Color(0xFFFF6B9D), size: 20),
                    SizedBox(height: 2),
                    Text('PDF',
                        style: TextStyle(
                            color: Color(0xFFFF6B9D),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                ],
                ),
            ),
            const SizedBox(width: 12),

            // File info
            Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                    children: [
                        Text(pageLabel,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        const Text(' · ',
                            style: TextStyle(color: Colors.white24, fontSize: 11)),
                        Text(sizeLabel,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                    ],
                    ),
                ],
                ),
            ),
            const SizedBox(width: 8),

            // Open hint
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFFF6B9D).withValues(alpha: 0.3)),
                ),
                child: const Text('Open',
                    style: TextStyle(
                        color: Color(0xFFFF6B9D),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),

            // Delete
            GestureDetector(
                onTap: () => _confirmRemoveBlock(b),
                child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white38),
                ),
            ),
            ],
        ),
        ),
    );
    }

    String _fmtBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }

  Future<void> _confirmRemoveBlock(NoteBlock b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Remove block?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
    if (ok == true) _removeBlock(b.id);
  }

  // ─────────────────────────────────────────────────────────────
  // Format bar
  // ─────────────────────────────────────────────────────────────

  Widget _buildFormatBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1E1E)),
          bottom: BorderSide(color: Color(0xFF1E1E1E)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1 — heading style chips
          _fmtRow([
            _TChip('H1', _fmtH1, const Color(0xFFFF6B9D),
                () => _applyParagraphFmt((b) {
                      b.isH1 = !b.isH1;
                      b.isH2 = b.isH3 = b.isH4 = false;
                    })),
            _TChip('H2', _fmtH2, const Color(0xFFFF9F0A),
                () => _applyParagraphFmt((b) {
                      b.isH2 = !b.isH2;
                      b.isH1 = b.isH3 = b.isH4 = false;
                    })),
            _TChip('H3', _fmtH3, const Color(0xFFFFD60A),
                () => _applyParagraphFmt((b) {
                      b.isH3 = !b.isH3;
                      b.isH1 = b.isH2 = b.isH4 = false;
                    })),
            _TChip('H4', _fmtH4, const Color(0xFF64D2FF),
                () => _applyParagraphFmt((b) {
                      b.isH4 = !b.isH4;
                      b.isH1 = b.isH2 = b.isH3 = false;
                    })),
            _TChip(
                'body',
                !_fmtH1 && !_fmtH2 && !_fmtH3 && !_fmtH4,
                Colors.white,
                () => _applyParagraphFmt(
                    (b) => b.isH1 = b.isH2 = b.isH3 = b.isH4 = false)),
          ]),

          // Row 2 — inline: B / I / U / S + alignment + lists
          _fmtRow([
            _FBtn('B',
                bold: true,
                active: _fmtBold,
                onTap: () => _applyInlineFmt((s) => s.bold = !s.bold)),
            _FBtn('I',
                italic: true,
                active: _fmtItalic,
                onTap: () => _applyInlineFmt((s) => s.italic = !s.italic)),
            _FBtn('U',
                under: true,
                active: _fmtUnder,
                onTap: () =>
                    _applyInlineFmt((s) => s.underline = !s.underline)),
            _FBtn('S',
                strike: true,
                active: _fmtStrike,
                onTap: () =>
                    _applyInlineFmt((s) => s.strikethrough = !s.strikethrough)),
            _Sep(),
            _IBtn(Icons.format_align_left_rounded,
                _fmtAlign == NoteAlign.left,
                () => _applyParagraphFmt((b) => b.align = NoteAlign.left)),
            _IBtn(Icons.format_align_center_rounded,
                _fmtAlign == NoteAlign.center,
                () => _applyParagraphFmt((b) => b.align = NoteAlign.center)),
            _IBtn(Icons.format_align_right_rounded,
                _fmtAlign == NoteAlign.right,
                () => _applyParagraphFmt((b) => b.align = NoteAlign.right)),
            _Sep(),
            _IBtn(Icons.format_list_numbered_rounded, _fmtOL,
                () => _applyParagraphFmt((b) {
                      b.orderedList = !b.orderedList;
                      b.bulletList = false;
                    })),
            _IBtn(Icons.format_list_bulleted_rounded, _fmtBL,
                () => _applyParagraphFmt((b) {
                      b.bulletList = !b.bulletList;
                      b.orderedList = false;
                    })),
          ]),

          // Row 3 — text colour (inline)
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(
                  child: Text('A',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))),
            ),
            ..._textColors.map((c) => _ColorDot(
                  color: c,
                  selected: c == _fmtColor,
                  onTap: () => _applyInlineFmt((s) {
                    s.color = c;
                  }),
                )),
          ]),

          // Row 4 — highlight colour (inline)
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(
                  child: Icon(Icons.highlight_rounded,
                      size: 14, color: Colors.white38)),
            ),
            ..._highlights.map((c) => _ColorDot(
                  color: c,
                  selected: c == _fmtHighlight,
                  onTap: () => _applyInlineFmt((s) {
                    s.highlight = c;
                  }),
                )),
          ]),
        ],
      ),
    );
  }

  Widget _fmtRow(List<Widget> children) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          children: children,
        ),
      );

  // ─────────────────────────────────────────────────────────────
  // Bottom bar
  // ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BarBtn( icon: Icons.image_outlined, onTap: _showImageOptions),
          _BarBtn(
            icon: Icons.picture_as_pdf_rounded,
            onTap: _pickPdf,
            ),
          _BarBtn(
            icon: Icons.text_fields_rounded,
            active: _showFormatBar,
            activeColor: const Color(0xFFFFD60A),
            onTap: () => setState(() => _showFormatBar = !_showFormatBar),
          ),
          _BarBtn(
            icon: _recording
                ? Icons.stop_circle_rounded
                : Icons.mic_none_rounded,
            active: _recording,
            activeColor: const Color(0xFFFF3B30),
            onTap: _toggleRecording,
          ),
          _BarBtn(
              icon: Icons.check_box_outlined, onTap: _addCheckboxBlock),
        //   _BarBtn(
        //     icon: Icons.keyboard_hide_rounded,
        //     onTap: () {
        //       FocusScope.of(context).unfocus();
        //       setState(() => _showFormatBar = false);
        //     },
        //   ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year},  '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')} '
        '${l.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen image viewer with pinch-to-zoom
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenImage extends StatelessWidget {
  final String path;
  final VoidCallback onClose;
  const _FullscreenImage({required this.path, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white24,
                    size: 60),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar atoms
// ─────────────────────────────────────────────────────────────────────────────

class _TChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _TChip(this.label, this.selected, this.accent, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.5)
                    : Colors.white12),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? accent : Colors.white38,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
}

class _FBtn extends StatelessWidget {
  final String label;
  final bool bold, italic, under, strike, active;
  final VoidCallback onTap;
  const _FBtn(this.label,
      {this.bold = false,
      this.italic = false,
      this.under = false,
      this.strike = false,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: active ? Colors.white30 : Colors.white10),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 14,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
                  fontStyle:
                      italic ? FontStyle.italic : FontStyle.normal,
                  decoration: TextDecoration.combine([
                    if (under) TextDecoration.underline,
                    if (strike) TextDecoration.lineThrough,
                  ]),
                )),
          ),
        ),
      );
}

class _IBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _IBtn(this.icon, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: active ? Colors.white30 : Colors.white10),
          ),
          child: Icon(icon,
              size: 16,
              color: active ? Colors.white : Colors.white38),
        ),
      );
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(
            color: color ?? const Color(0xFF2A2A2A),
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 2.5 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: (color ?? Colors.white)
                            .withValues(alpha: 0.4),
                        blurRadius: 6)
                  ]
                : null,
          ),
          child: color == null
              ? const Center(
                  child: Icon(Icons.close_rounded,
                      size: 12, color: Colors.white38))
              : null,
        ),
      );
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white12);
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
final double? size;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
 

  const _BarBtn(
      {required this.icon,
      this.label,
        this.size,
      this.active = false,
      this.activeColor = const Color(0xFF0A84FF),
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 22,
                  color: active ? activeColor : Colors.white38),
              if (label != null) ...[
                const SizedBox(height: 1),
                Text(label!,
                    style: TextStyle(
                        fontSize: 9,
                        color: active ? activeColor : Colors.white24,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

void showProjectNoteSheet(BuildContext context, {required Project project}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ProjectNoteSheet(project: project),
  ));
}