import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/services/note_rich_controller.dart';
import 'package:focusbell/services/standalone_note_controller.dart';
import 'package:focusbell/widgets/note_waveform_bars.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/cupertino.dart';
import '../models/project.dart';
import '../services/app_controller.dart';
import '../utils/app_toast.dart';

import 'note_fullscreen_image.dart';
import 'note_toolbar_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProjectNoteSheet
// ─────────────────────────────────────────────────────────────────────────────

class ProjectNoteSheet extends StatefulWidget {
  final Project project;
  final Future<void> Function(String title, String? note)? onSaveNote;
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

class _ProjectNoteSheetState extends State<ProjectNoteSheet>
    with TickerProviderStateMixin {
    final Map<String, GlobalKey> _textKeys = {};
    // ── Checkbox total guard ──────────────────────────────────────
    bool _suppressTotalRecompute = false;
    Timer? _totalDebounce;
    // ── Document ─────────────────────────────────────────────────
    late List<NoteBlock> _blocks;
    final Map<String, NoteRichController> _ctrl = {};
    final Map<String, FocusNode> _fn = {};
    String? _activeId;
    bool _dirty = false;
    String? _fmtUrl;
    bool _readOnly = false;

  static final _urlRegex = RegExp(
    r'(?:https?://|www\.)\S+',
    caseSensitive: false,
  );

  // ── Title ────────────────────────────────────────────────────
  late TextEditingController _titleCtrl;
  late FocusNode _titleFn;

  // ── Format bar state ─────────────────────────────────────────
  bool _showFormatBar = false;

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
  static const _kCustomColor = Color(0x00000001); // sentinel for "pick custom"

  static const _textColors = <Color?>[
    null, // clear / default
    Color(0xFFFFFFFF), // pure white
    Color(0xFFE8E8E8), // soft white
    Color(0xFFCCCCCC), // light gray
    Color(0xFFAAAAAA), // mid gray
    Color(0xFF888888), // dim gray
    Color(0xFFFF3B30), // red
    Color(0xFFFF9F0A), // orange
    Color(0xFFFFD60A), // yellow
    Color(0xFF34C759), // green
    Color(0xFF0A84FF), // blue
    Color(0xFFBF5AF2), // purple
    Color(0xFFFF6B9D), // pink
    Color(0xFF64D2FF), // sky
    _kCustomColor, // custom picker
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
  String? _currentlyPlayingId;  // ← here
    Timer? _positionPoller;
  final Map<String, bool> _playing = {};
  final Map<String, Duration> _playPos = {};
  final Map<String, Duration> _playDur = {}; // runtime duration (from player)

  // Recording elapsed timer
  Ticker? _recTicker;
  Duration _recElapsed = Duration.zero;
  DateTime? _recStart;

  // Pulse animation for recording indicator
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

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
    _ensureTrailingTextBlock();

    _titleCtrl = TextEditingController(text: widget.project.name);
    _titleFn = FocusNode();

    // Pulse animation for recording dot
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _player.onPlayerStateChanged.listen((s) {
    if (!mounted) return;
    if (s == PlayerState.completed) {
        setState(() {
        if (_currentlyPlayingId != null) {
            _playing[_currentlyPlayingId!] = false;
            _playPos[_currentlyPlayingId!] = Duration.zero;
            _currentlyPlayingId = null;
        }
        });
    }
    });

    _player.onPositionChanged.listen((pos) {
    if (!mounted || _currentlyPlayingId == null) return;
    // Only rebuild if position actually moved by at least 100ms
    final prev = _playPos[_currentlyPlayingId!] ?? Duration.zero;
    if ((pos - prev).abs() >= const Duration(milliseconds: 100)) {
        setState(() => _playPos[_currentlyPlayingId!] = pos);
    }
    });

    _player.onDurationChanged.listen((dur) {
    if (!mounted || _currentlyPlayingId == null) return;
    setState(() => _playDur[_currentlyPlayingId!] = dur);
    });

    _player.onPlayerStateChanged.listen((s) {
    if (s == PlayerState.completed && mounted) {
        setState(() {
        if (_currentlyPlayingId != null) {
            _playing[_currentlyPlayingId!] = false;
            _playPos[_currentlyPlayingId!] = Duration.zero;
            _currentlyPlayingId = null;
        }
        });
    }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_blocks.isNotEmpty) _fn[_blocks.first.id]?.requestFocus();
    });
  }


    String _segsToMarkdown(NoteBlock b) {
        final ctrl = _ctrl[b.id];
        final segs = ctrl?.segs ?? b.segs;
        final buf = StringBuffer();
        for (final s in segs) {
            var text = s.text;
            // Wrap in markdown inline styles
            if (s.bold) text = '**$text**';
            if (s.italic) text = '_${text}_';
            if (s.strikethrough) text = '~~$text~~';
            // Link takes priority over underline
            if (s.url != null && s.url!.isNotEmpty) {
            text = '[$text](${s.url})';
            }
            buf.write(text);
        }
        return buf.toString();
    }


  Future<void> _showColorPicker({required bool isHighlight}) async {
    Color current = isHighlight
        ? (_fmtHighlight ?? const Color(0xFFFFD60A))
        : (_fmtColor ?? Colors.white);

    // Strip alpha for the picker if it's a highlight (semi-transparent)
    if (isHighlight) current = current.withValues(alpha: 1.0);

    HSVColor hsv = HSVColor.fromColor(current);

    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final preview = isHighlight
                ? hsv.toColor().withValues(alpha: 0.4)
                : hsv.toColor();
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                isHighlight ? 'Highlight color' : 'Text color',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Preview swatch
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: preview,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Hue
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Hue',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                    ),
                    child: Slider(
                      value: hsv.hue,
                      min: 0,
                      max: 360,
                      activeColor: HSVColor.fromAHSV(
                        1,
                        hsv.hue,
                        1,
                        1,
                      ).toColor(),
                      inactiveColor: Colors.white12,
                      onChanged: (v) => setLocal(() => hsv = hsv.withHue(v)),
                    ),
                  ),
                  // Saturation
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Saturation',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                    ),
                    child: Slider(
                      value: hsv.saturation,
                      min: 0,
                      max: 1,
                      activeColor: hsv.toColor(),
                      inactiveColor: Colors.white12,
                      onChanged: (v) =>
                          setLocal(() => hsv = hsv.withSaturation(v)),
                    ),
                  ),
                  // Brightness
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Brightness',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 10,
                      ),
                    ),
                    child: Slider(
                      value: hsv.value,
                      min: 0,
                      max: 1,
                      activeColor: hsv.toColor(),
                      inactiveColor: Colors.white12,
                      onChanged: (v) => setLocal(() => hsv = hsv.withValue(v)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    isHighlight
                        ? hsv.toColor().withValues(alpha: 0.4)
                        : hsv.toColor(),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(
                      color: Color(0xFF64D2FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    if (isHighlight) {
      _applyInlineFmt((s) => s.highlight = picked);
    } else {
      _applyInlineFmt((s) => s.color = picked);
    }
  }

  void _initBlock(NoteBlock b) {
    if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox)
      return;

    final ctrl = NoteRichController(segs: List.from(b.segs));
    ctrl.addListener(() {
      if (_activeId == b.id && mounted) setState(() => _refreshFmtBar(b, ctrl));
    });

    _ctrl[b.id] = ctrl;
    _textKeys[b.id] = GlobalKey();

    final fn = FocusNode();
    // In the FocusNode listener inside _initBlock:
    fn.addListener(() {
      if (fn.hasFocus && mounted) {
        final isTotal =
            b.segs.isNotEmpty &&
            b.segs.first.text.trimLeft().startsWith('Checkbox Total:');
        setState(() {
          _activeId = b.id;
          if (!isTotal) {
            _refreshFmtBar(b, ctrl);
          } else {
            _showFormatBar = false;
          }
        });
      }
    });
    _fn[b.id] = fn;
  }

  void _refreshFmtBar(NoteBlock b, NoteRichController ctrl) {
    final sel = ctrl.selection;
    final style = ctrl.styleAt(sel);
    _fmtBold = style['bold'] as bool;
    _fmtItalic = style['italic'] as bool;
    _fmtUnder = style['underline'] as bool;
    _fmtStrike = style['strikethrough'] as bool;
    _fmtColor = style['color'] as Color?;
    _fmtHighlight = style['highlight'] as Color?;
    _fmtUrl = style['url'] as String?;
    _fmtAlign = b.align;
    _fmtH1 = b.isH1;
    _fmtH2 = b.isH2;
    _fmtH3 = b.isH3;
    _fmtH4 = b.isH4;
    _fmtOL = b.orderedList;
    _fmtBL = b.bulletList;
  }

  NoteBlock? get _active => _blocks.where((b) => b.id == _activeId).firstOrNull;
  NoteRichController? get _activeCtrl =>
      _activeId != null ? _ctrl[_activeId] : null;

  // ─────────────────────────────────────────────────────────────
  // Inline / paragraph formatting
  // ─────────────────────────────────────────────────────────────
  void _ensureTrailingTextBlock() {
    if (_blocks.isEmpty || _blocks.last.type != NoteBlockType.text) {
      final nb = NoteBlock(id: noteUid(), type: NoteBlockType.text);
      _blocks.add(nb);
      _initBlock(nb);
    }
  }

  void _applyInlineFmt(void Function(NoteSeg s) fn) {
    final b = _active;
    final ctrl = _activeCtrl;
    if (b == null || ctrl == null) return;

    final sel = ctrl.selection;
    final start = (sel.isValid && !sel.isCollapsed) ? sel.start : 0;
    final end = (sel.isValid && !sel.isCollapsed) ? sel.end : ctrl.text.length;

    setState(() {
      ctrl.applyToRange(start, end, fn);
      b.segs = List.from(ctrl.segs);
      ctrl.rebuildText();
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
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    _blocks.insert(idx + 1, nb);
    _initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fn[nb.id]?.requestFocus(),
    );
  }

  void _addCheckboxBlock() {
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.checkbox);
    final idx = _activeId == null
        ? _blocks.length
        : _blocks.indexWhere((b) => b.id == _activeId) + 1;
    _blocks.insert(idx, nb);
    _initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fn[nb.id]?.requestFocus(),
    );
  }

  void _recomputeCheckboxTotal() {
    // Collect all checkbox blocks with purely-numeric plain text
    final numericBlocks = <({NoteBlock block, int value})>[];

    for (final b in _blocks) {
      if (b.type != NoteBlockType.checkbox) continue;
      // Skip any existing total block
      if (b.segs.isNotEmpty &&
          b.segs.first.text.trimLeft().startsWith('Checkbox Total:'))
        continue;

      final raw = (b.plainText).replaceAll(RegExp(r'[\s,_]'), '');
      final n = int.tryParse(raw);
      if (n != null) numericBlocks.add((block: b, value: n));
    }

    // Find existing total block (if any)
    final totalIdx = _blocks.indexWhere(
      (b) =>
          b.type == NoteBlockType.checkbox &&
          b.segs.isNotEmpty &&
          b.segs.first.text.trimLeft().startsWith('Checkbox Total:'),
    );

    if (numericBlocks.length < 2) {
      // Remove stale total block if numeric inputs dropped below 2
      if (totalIdx != -1) {
        setState(() {
          _blocks.removeAt(totalIdx);
          _dirty = true;
        });
      }
      return;
    }

    final sum = numericBlocks.fold(0, (acc, e) => acc + e.value);
    // Format with thousands separator
    final formatted = _formatWithCommas(sum);
    final label = 'Checkbox Total: $formatted';

    if (totalIdx != -1) {
      // Update existing total block in-place
      final tb = _blocks[totalIdx];
      final ctrl = _ctrl[tb.id];
      setState(() {
        tb.segs = [NoteSeg(text: label)];
        tb.checked = false;
        if (ctrl != null) {
          ctrl.segs = List.from(tb.segs);
          ctrl.rebuildText();
        }
        _dirty = true;
      });
    } else {
      // Insert new total block after the last numeric checkbox
      final lastNumericBlock = numericBlocks.last.block;
      final insertAfterIdx = _blocks.indexWhere(
        (b) => b.id == lastNumericBlock.id,
      );

      final tb = NoteBlock(id: noteUid(), type: NoteBlockType.checkbox)
        ..segs = [NoteSeg(text: label)];

      _blocks.insert(insertAfterIdx + 1, tb);
      _initBlock(tb);

      // Sync the controller text immediately
      final ctrl = _ctrl[tb.id];
      if (ctrl != null) {
        ctrl.segs = List.from(tb.segs);
        ctrl.rebuildText();
      }
      setState(() => _dirty = true);
    }
  }

  String _formatWithCommas(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _removeBlock(String id) {
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx == -1) return;

    final block = _blocks[idx];

    final textBlocks = _blocks.where(
      (b) => b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox,
    );
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

    if (block.type == NoteBlockType.pdf && block.pdfPath != null) {
      File(block.pdfPath!).delete().catchError((_) {});
    }

    // Capture references BEFORE removing from maps so we can safely
    // defer dispose until after the frame — avoids "_dependents.isEmpty"
    // assertion when the TextField is still mounted during setState.
    final ctrlToDispose = _ctrl[id];
    final fnToDispose = _fn[id];

    setState(() {
      _ctrl.remove(id);
      _fn.remove(id);
      _textKeys.remove(id);
      _blocks.removeAt(idx);
    });

    // Defer disposal until the widgets using these objects are gone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_suppressTotalRecompute) _recomputeCheckboxTotal();
      _suppressTotalRecompute = false;
      ctrlToDispose?.dispose();
      fnToDispose?.dispose();
    });

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

  Future<void> _handleTextTap(NoteBlock b, TapUpDetails details) async {
    final ctrl = _ctrl[b.id];
    if (ctrl == null) return;

    final key = _textKeys[b.id];
    if (key == null) return;

    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null) return;

    RenderEditable? renderEditable;
    void visitor(RenderObject child) {
      if (child is RenderEditable) {
        renderEditable = child;
        return;
      }
      child.visitChildren(visitor);
    }

    renderObject.visitChildren(visitor);
    if (renderEditable == null) return;

    final localPos = renderEditable!.globalToLocal(details.globalPosition);
    final textPosition = renderEditable!.getPositionForPoint(localPos);
    final offset = textPosition.offset;

    final url = ctrl.urlAt(offset);
    if (url == null || url.isEmpty) return;

    var urlStr = url;
    if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
      urlStr = 'https://$urlStr';
    }
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Image picker
  // ─────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;

    final imgBlock = NoteBlock(
      id: noteUid(),
      type: NoteBlockType.image,
      imagePath: file.path,
    );
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
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
      (_) => _fn[textAfter.id]?.requestFocus(),
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ImageOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                Divider(height: 1, color: Colors.white10),
                _ImageOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose Photo',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PDF picker
  // ─────────────────────────────────────────────────────────────

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

    final docsDir = await getApplicationDocumentsDirectory();
    final destName = '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
    final destPath = '${docsDir.path}/$destName';
    await File(picked.path!).copy(destPath);

    int pageCount = 0;
    try {
      final bytes = await File(destPath).readAsBytes();
      final content = String.fromCharCodes(bytes);
      final matches = RegExp(r'/Type\s*/Page[^s]').allMatches(content);
      pageCount = matches.length;
    } catch (_) {}

    final pdfBlock = NoteBlock(
      id: noteUid(),
      type: NoteBlockType.pdf,
      pdfPath: destPath,
      pdfName: picked.name,
      pdfSizeBytes: picked.size,
      pdfPageCount: pageCount,
    );
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);

    final idx = _activeId == null
        ? _blocks.length
        : _blocks.indexWhere((b) => b.id == _activeId) + 1;

    setState(() {
      _blocks.insert(idx, pdfBlock);
      _blocks.insert(idx + 1, textAfter);
      _dirty = true;
    });
    _initBlock(textAfter);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fn[textAfter.id]?.requestFocus(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Link dialog
  // ─────────────────────────────────────────────────────────────

  Future<void> _showLinkDialog() async {
    final ctrl = _activeCtrl;
    if (ctrl == null) return;

    final sel = ctrl.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final existing = (ctrl.styleAt(sel)['url'] as String?) ?? '';

    final selectedText = hasSelection
        ? ctrl.text.substring(sel.start, sel.end).trim()
        : '';
    final looksLikeUrl =
        selectedText.startsWith('http://') ||
        selectedText.startsWith('https://') ||
        selectedText.startsWith('www.');

    // Controllers are created here and disposed AFTER the dialog closes —
    // never inside the dialog's build (which would cause _dependents assertion).
    final urlCtrl = TextEditingController(
      text: existing.isNotEmpty
          ? existing
          : looksLikeUrl
          ? selectedText
          : '',
    );
    final textCtrl = TextEditingController(
      text: looksLikeUrl ? '' : selectedText,
    );

    Map<String, String>? result;
    result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Insert Link',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasSelection) ...[
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Link text',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF252525),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                prefixIcon: const Icon(
                  Icons.link_rounded,
                  color: Color(0xFF64D2FF),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (existing.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'url': '', 'text': ''}),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFFF3B30)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'url': urlCtrl.text.trim(),
              'text': textCtrl.text.trim(),
            }),
            child: const Text(
              'Insert',
              style: TextStyle(
                color: Color(0xFF64D2FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    // Defer disposal to the next frame — by then the dialog's TextFields
    // have been unmounted and no longer hold references to these controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      urlCtrl.dispose();
      textCtrl.dispose();
    });

    if (result == null) return;

    final url = result['url']!;
    final linkText = result['text']!;
    final remove = url.isEmpty;

    if (hasSelection) {
      _applyInlineFmt((s) {
        if (remove) {
          s.url = null;
        } else {
          s.url = url;
        }
      });
    } else if (!remove && linkText.isNotEmpty) {
      final b = _active;
      final at = ctrl.selection.baseOffset;
      final newSeg = NoteSeg(
        text: linkText,
        url: url,
        underline: true,
        color: const Color(0xFF64D2FF),
      );
      setState(() {
        ctrl.segs = NoteRichController.insSegs(ctrl.segs, at, linkText, newSeg);
        int pos = 0;
        for (final s in ctrl.segs) {
          if (pos >= at && pos < at + linkText.length) {
            s.url = url;
            s.color = const Color(0xFF64D2FF);
            s.underline = true;
          }
          pos += s.text.length;
        }
        ctrl.segs = NoteRichController.mergeSegs(ctrl.segs);
        b?.segs = List.from(ctrl.segs);
        ctrl.rebuildText();
        _dirty = true;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Audio
  // ─────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      _stopRecording();
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/note_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      _recStart = DateTime.now();
      _recElapsed = Duration.zero;
      _recTicker?.dispose();
      _recTicker = createTicker((_) {
        if (_recStart != null && mounted) {
          setState(() => _recElapsed = DateTime.now().difference(_recStart!));
        }
      })..start();
      setState(() => _recording = true);
    }
  }

  Future<void> _stopRecording() async {
    _recTicker?.stop();
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _recElapsed = Duration.zero;
    });
    if (path == null) return;

    final audioBlock = NoteBlock(
      id: noteUid(),
      type: NoteBlockType.audio,
      audioPath: path,
      audioDuration: _recElapsed,
    );
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
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
      (_) => _fn[textAfter.id]?.requestFocus(),
    );
  }

  Future<void> _cancelRecording() async {
    _recTicker?.stop();
    await _recorder.cancel();
    setState(() {
      _recording = false;
      _recElapsed = Duration.zero;
    });
  }

    Future<void> _togglePlayback(NoteBlock b) async {
        final isPlaying = _playing[b.id] ?? false;
        if (isPlaying) {
            await _player.pause();
            _positionPoller?.cancel();
            setState(() {
            _playing[b.id] = false;
            _currentlyPlayingId = null;
            });
        } else {
            for (final k in _playing.keys.toList()) _playing[k] = false;
            _positionPoller?.cancel();
            await _player.play(DeviceFileSource(b.audioPath!));
            setState(() {
            _playing[b.id] = true;
            _currentlyPlayingId = b.id;
            _activeId = b.id;
            });
            // Poll position every 100ms — guaranteed to work regardless of stream
            _positionPoller = Timer.periodic(const Duration(milliseconds: 100), (_) async {
            if (!mounted || _currentlyPlayingId == null) return;
            final pos = await _player.getCurrentPosition();
            if (pos != null) {
                setState(() => _playPos[_currentlyPlayingId!] = pos);
            }
            });
        }
    }

    Future<void> _seekAudio(NoteBlock b, double fraction) async {
        final dur = _playDur[b.id] ?? b.audioDuration;
        if (dur == Duration.zero) return;
        final target = Duration(
            milliseconds: (dur.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
        );
        await _player.seek(target);
        setState(() => _playPos[b.id] = target); 
    }

  // ─────────────────────────────────────────────────────────────
  // Auto-link detection
  // ─────────────────────────────────────────────────────────────

    /// Scans all text/checkbox blocks and promotes any bare URL runs that
    /// don't already have a [url] attribute into linked segments.
    void _autoDetectLinks() {
    for (final b in _blocks) {
        if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox) {
            continue;
        }
        final ctrl = _ctrl[b.id];
        if (ctrl == null) continue;

        bool changed = false;

        // Rebuild segs: for each seg without a URL, scan its text for URLs.
        final newSegs = <NoteSeg>[];
      for (final seg in ctrl.segs) {
        if (seg.url != null && seg.url!.isNotEmpty) {
          newSegs.add(seg);
          continue;
        }

        final matches = _urlRegex.allMatches(seg.text).toList();
        if (matches.isEmpty) {
          newSegs.add(seg);
          continue;
        }

        changed = true;
        int cursor = 0;
        for (final m in matches) {
          // Text before the URL.
          if (m.start > cursor) {
            newSegs.add(
              seg.copyWith(text: seg.text.substring(cursor, m.start)),
            );
          }
          // The URL span.
          final urlText = m.group(0)!;
          final urlTarget = urlText.startsWith('http')
              ? urlText
              : 'https://$urlText';
          newSegs.add(
            seg.copyWith(
              text: urlText,
              url: urlTarget,
              underline: true,
              color: const Color(0xFF64D2FF),
            ),
          );
          cursor = m.end;
        }
        // Trailing text after last URL.
        if (cursor < seg.text.length) {
          newSegs.add(seg.copyWith(text: seg.text.substring(cursor)));
        }
      }

      if (changed) {
        ctrl.segs = NoteRichController.mergeSegs(newSegs);
        b.segs = List.from(ctrl.segs);
        ctrl.rebuildText();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Save / clear
  // ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Auto-detect bare URLs and promote them to linked segments.
    _autoDetectLinks();

    for (final b in _blocks) {
      if (_ctrl[b.id] != null) b.segs = List.from(_ctrl[b.id]!.segs);
    }
    final trimmed = _blocks.length > 1
        ? (_blocks.toList()..removeWhere(
            (b) =>
                b == _blocks.last &&
                b.type == NoteBlockType.text &&
                b.plainText.trim().isEmpty,
          ))
        : _blocks;
    final encoded = NoteBlock.encodeList(trimmed);

    if (widget.onSaveNote != null) {
      await widget.onSaveNote!(_titleCtrl.text.trim(), encoded);
    } else {
      await AppController.instance.updateProjectNote(
        widget.project.id,
        encoded,
      );
    }

    if (mounted) {
      AppToast.show(
        context,
        msg: 'Note saved',
        backgroundColor: const Color(0xFF0A1F0A),
        textColor: const Color(0xFF34C759),
      );
      setState(() {
        _dirty = false;
        _readOnly = true;
        FocusScope.of(context).unfocus();
      });
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Clear note?',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: const Text(
          'All note content will be removed.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppController.instance.updateProjectNote(widget.project.id, null);
      if (mounted) Navigator.pop(context);
    }
  }

  String _fmtDateOnly(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year}';
  }

  String _fmtTimeOnly(DateTime dt) {
    final l = dt.toLocal();
    final hour12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '${hour12.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')} '
        '${l.hour >= 12 ? 'PM' : 'AM'}';
  }

    void _showMoveSheet(NoteBlock audioBlock) {
  final isStandalone = widget.onSaveNote != null;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      // ── Build the list items based on note type ──
      final List<Widget> items;

      if (isStandalone) {
        // Standalone notes list
        final notes = StandaloneNoteController.instance.notes
            .where((n) => n.id != widget.project.id)
            .toList();

        items = notes.map((note) => ListTile(
          leading: const Icon(Icons.note_outlined, color: Colors.white38, size: 18),
          title: Text(
            note.title.isEmpty ? 'Untitled' : note.title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          onTap: () async {
            Navigator.pop(ctx);
            setState(() {
              _blocks.removeWhere((bl) => bl.id == audioBlock.id);
              _dirty = true;
            });
            await _save();

            final target = StandaloneNoteController.instance.find(note.id);
            if (target == null) return;
            final targetBlocks = NoteBlock.decodeList(target.note);
            targetBlocks.add(audioBlock);
            await StandaloneNoteController.instance.saveNote(
              note.id,
              note.title,
              NoteBlock.encodeList(targetBlocks),
            );

            if (mounted) {
              AppToast.show(
                context,
                msg: 'Moved to "${note.title.isEmpty ? 'Untitled' : note.title}"',
                backgroundColor: const Color(0xFF0A1F0A),
                textColor: const Color(0xFF34C759),
              );
            }
          },
        )).toList();
      } else {
        // Project notes list
        final projects = AppController.instance.projects
            .where((p) => p.id != widget.project.id)
            .toList();

        items = projects.map((project) => ListTile(
          leading: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: project.priority.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            project.name,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: project.description.isNotEmpty
              ? Text(
                  project.description,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () async {
            Navigator.pop(ctx);
            setState(() {
              _blocks.removeWhere((bl) => bl.id == audioBlock.id);
              _dirty = true;
            });
            await _save();

            // Load target project's existing note blocks and append
            final targetProject = AppController.instance.projects
                .firstWhere((p) => p.id == project.id);
            final targetBlocks = NoteBlock.decodeList(targetProject.note);
            targetBlocks.add(audioBlock);
            await AppController.instance.updateProjectNote(
              project.id,
              NoteBlock.encodeList(targetBlocks),
            );

            if (mounted) {
              AppToast.show(
                context,
                msg: 'Moved to "${project.name}"',
                backgroundColor: const Color(0xFF0A1F0A),
                textColor: const Color(0xFF34C759),
              );
            }
          },
        )).toList();
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              isStandalone ? 'Move to note' : 'Move to project',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                isStandalone ? 'No other notes available' : 'No other projects available',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: items,
              ),
            ),
          const SizedBox(height: 20),
        ],
      );
    },
  );
}

  @override
  void dispose() {
    _positionPoller?.cancel();
    for (final c in _ctrl.values) c.dispose();
    for (final f in _fn.values) f.dispose();
    
    _titleCtrl.dispose();
    _titleFn.dispose();
    _pulseCtrl.dispose();
    _recTicker?.dispose();
    _recorder.dispose();
    _player.dispose();
    _totalDebounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_fullscreenImage != null) {
      return NoteFullscreenImage(
        path: _fullscreenImage!,
        onClose: () => setState(() => _fullscreenImage = null),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildEditor()),
            if (_recording) _buildRecordingPanel(),
            if (_showFormatBar && !_readOnly) _buildFormatBar(),
            if (!_readOnly) _buildBottomBar(),
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
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_dirty) await _save();
              if (mounted) Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 20,
              ),
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
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.project.noteUpdatedAt != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmtDateOnly(widget.project.noteUpdatedAt!),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _fmtTimeOnly(widget.project.noteUpdatedAt!),
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'New note',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
          ),
          if (widget.project.hasNote)
            GestureDetector(
              onTap: _clear,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E0A0A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // Edit / Preview toggle
          GestureDetector(
            onTap: () {
              setState(() {
                _readOnly = !_readOnly;
                if (_readOnly) {
                  FocusScope.of(context).unfocus();
                  _showFormatBar = false;
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _readOnly
                    ? const Color(0xFF0A1A2E)
                    : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _readOnly
                      ? const Color(0xFF64D2FF).withValues(alpha: 0.4)
                      : Colors.white10,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _readOnly ? Icons.edit_outlined : Icons.visibility_outlined,
                    size: 12,
                    color: _readOnly ? const Color(0xFF64D2FF) : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _readOnly ? 'Edit' : 'Preview',
                    style: TextStyle(
                      color: _readOnly
                          ? const Color(0xFF64D2FF)
                          : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _dirty
                    ? const Color(0xFF34C759)
                    : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: _dirty
                      ? const Color(0xFF34C759).withValues(alpha: 0.5)
                      : Colors.white10,
                ),
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  color: _dirty ? Colors.black : Colors.white30,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
      _ensureTrailingTextBlock();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final last = _blocks.lastWhere(
          (b) => b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox,
          orElse: () => _blocks.last,
        );
        _fn[last.id]?.requestFocus();
        final c = _ctrl[last.id];
        if (c != null) c.selection = TextSelection.collapsed(offset: c.text.length);
      });
    },
    child: ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
      onReorder: (oldIndex, newIndex) {
        // index 0 is the title block (not in _blocks), so shift by -1
        final adjustedOld = oldIndex - 1;
        final adjustedNew = newIndex - 1;
        if (adjustedOld < 0 || adjustedNew < 0) return;
        setState(() {
          if (adjustedNew > adjustedOld) {
            final newAdj = adjustedNew - 1;
            final block = _blocks.removeAt(adjustedOld);
            _blocks.insert(newAdj, block);
          } else {
            final block = _blocks.removeAt(adjustedOld);
            _blocks.insert(adjustedNew, block);
          }
          _dirty = true;
        });
      },
      buildDefaultDragHandles: false,
      itemCount: _blocks.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return KeyedSubtree(
            key: const ValueKey('__title__'),
            child: _buildTitleBlock(),
          );
        }
        final b = _blocks[i - 1];
        return KeyedSubtree(
          key: ValueKey(b.id),
          child: _buildBlock(b, i - 1),
        );
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
          color: Colors.white70,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.3,
        ),
        decoration: const InputDecoration(
          hintText: 'Title',
          hintStyle: TextStyle(
            color: Colors.white24,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
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
      NoteBlockType.pdf => _buildPdfBlock(b),
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Text block
  // ─────────────────────────────────────────────────────────────

  Widget _buildTextBlock(NoteBlock b, int index) {
    final baseStyle = b.baseStyle;
    final prefix = b.orderedList
        ? '${index + 1}.  '
        : b.bulletList
        ? '•  '
        : '';

    // In read-only/preview mode, render as tappable rich text (no TextField).
    if (_readOnly) {
        final ctrl = _ctrl[b.id];
        final plainText = _segsToMarkdown(b);

  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: MarkdownBody(
      data: plainText,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        h1: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
        h2: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        h3: const TextStyle(color: Color(0xFFFFD60A), fontSize: 18, fontWeight: FontWeight.w600),
        h4: const TextStyle(color: Color(0xFF64D2FF), fontSize: 16, fontWeight: FontWeight.w600),
        strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        em: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
        code: const TextStyle(color: Color(0xFF34C759), fontFamily: 'monospace', fontSize: 13),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        tableBody: const TextStyle(color: Colors.white70, fontSize: 13),
        tableHead: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        tableBorder: TableBorder.all(color: Colors.white12, width: 1),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: const Color(0xFF64D2FF), width: 3)),
          color: const Color(0xFF0A1A2E),
        ),
        blockquote: const TextStyle(color: Colors.white54, fontSize: 14),
        listBullet: const TextStyle(color: Colors.white38),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
      ),
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      selectable: true,
    ),
  );
}
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prefix.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text(
                prefix,
                style: baseStyle.copyWith(color: Colors.white38),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTapUp: (details) => _handleTextTap(b, details),
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
                  key: _textKeys[b.id],
                  controller: _ctrl[b.id],
                  focusNode: _fn[b.id],
                  maxLines: null,
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
                    hintText: (_activeId == b.id && _blocks.length == 1)
                        ? 'Start typing…'
                        : null,
                    hintStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds an inline [TextSpan] from segs for read-only rendering.
  /// URL segments get a TapGestureRecognizer wired to [launchUrl].
  TextSpan _buildReadOnlySpan(NoteBlock b, TextStyle baseStyle) {
    final ctrl = _ctrl[b.id];
    final segs = ctrl?.segs ?? b.segs;
    return TextSpan(
      style: baseStyle,
      children: segs.map((s) {
        final isLink = s.url != null && s.url!.isNotEmpty;
        return TextSpan(
          text: s.text,
          style: TextStyle(
            fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
            color: isLink ? const Color(0xFF64D2FF) : s.color,
            backgroundColor: s.highlight,
            decoration: TextDecoration.combine([
              if (s.underline || isLink) TextDecoration.underline,
              if (s.strikethrough) TextDecoration.lineThrough,
            ]),
            decorationColor: isLink ? const Color(0xFF64D2FF) : null,
          ),
          recognizer: isLink
              ? (TapGestureRecognizer()
                  ..onTap = () async {
                    var urlStr = s.url!;
                    if (!urlStr.startsWith('http://') &&
                        !urlStr.startsWith('https://')) {
                      urlStr = 'https://$urlStr';
                    }
                    final uri = Uri.tryParse(urlStr);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  })
              : null,
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Checkbox block
  // ─────────────────────────────────────────────────────────────

  Widget _buildCheckboxBlock(NoteBlock b, int index) {
    final checkColor = b.checked
        ? Colors.white30
        : Colors.white.withValues(alpha: 0.88);
    final checkStyle = TextStyle(
      color: checkColor,
      fontSize: 14,
      height: 1.5,
      decoration: b.checked ? TextDecoration.lineThrough : TextDecoration.none,
    );

    final checkBox = GestureDetector(
      onTap: _readOnly
          ? null
          : () {
              final isTotal =
                  b.segs.isNotEmpty &&
                  b.segs.first.text.trimLeft().startsWith('Checkbox Total:');
              if (isTotal) {
                _suppressTotalRecompute = true; // ← guard BEFORE remove
                _removeBlock(b.id);
                setState(() => _dirty = true);
              } else {
                setState(() {
                  b.checked = !b.checked;
                  _dirty = true;
                });
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: b.checked ? const Color(0xFF34C759) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: b.checked ? const Color(0xFF34C759) : Colors.white30,
            width: 1.5,
          ),
        ),
        child: b.checked
            ? const Icon(Icons.check_rounded, size: 13, color: Colors.black)
            : null,
      ),
    );

    if (_readOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            checkBox,
            Expanded(
              child: GestureDetector(
                onTapUp: (details) => _handleTextTap(b, details),
                child: Text.rich(_buildReadOnlySpan(b, checkStyle)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          checkBox,
          Expanded(
            child: GestureDetector(
              onTapUp: (details) => _handleTextTap(b, details),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      _ctrl[b.id]?.text.isEmpty == true) {
                    final isTotal =
                        b.segs.isNotEmpty &&
                        b.segs.first.text.trimLeft().startsWith(
                          'Checkbox Total:',
                        );
                    if (!isTotal) _removeBlock(b.id); // ← guard
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: _textKeys[b.id],
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
                    // Replace _recomputeCheckboxTotal(); with:
                    _totalDebounce?.cancel();
                    _totalDebounce = Timer(
                      const Duration(milliseconds: 400),
                      _recomputeCheckboxTotal,
                    );
                  },
                  onSubmitted: (_) => _addTextBlockAfter(b.id),
                  style: checkStyle,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'To-do item',
                    hintStyle: TextStyle(color: Colors.white12, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Image block
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
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white24,
                  size: 40,
                ),
              ),
            ),
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
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_full_rounded,
                      size: 11,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'View',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  // ─────────────────────────────────────────────────────────────
  // Recording panel — slides up from bottom while recording
  // ─────────────────────────────────────────────────────────────

  Widget _buildRecordingPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF130A0A),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Pulsing red dot
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromRGBO(
                  255,
                  59,
                  48,
                  _pulseAnim.value,
                ), // FF3B30 with animated opacity
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFFFF3B30,
                    ).withValues(alpha: _pulseAnim.value * 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // REC label + elapsed
          const Text(
            'REC',
            style: TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmtDur(_recElapsed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 1,
            ),
          ),

          const Spacer(),

          // Cancel button
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Stop / save button
          GestureDetector(
            onTap: _stopRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'Stop',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Audio block — modern waveform-style player
  // ─────────────────────────────────────────────────────────────

  Widget _buildAudioBlock(NoteBlock b) {
    final isPlaying = _playing[b.id] ?? false;
    final pos = _playPos[b.id] ?? Duration.zero;
    final dur = _playDur[b.id] ?? b.audioDuration;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = dur > pos ? dur - pos : Duration.zero;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
              ? const Color(0xFF0A84FF).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.07),
        ),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // ── Top row: play button + waveform bars + time ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Play / Pause button
                GestureDetector(
                  onTap: () => _togglePlayback(b),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying
                          ? const Color(0xFF0A84FF)
                          : const Color(0xFF0A84FF).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(
                          0xFF0A84FF,
                        ).withValues(alpha: isPlaying ? 0.0 : 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isPlaying ? Colors.white : const Color(0xFF0A84FF),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Fake waveform bars (decorative, animated when playing)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Waveform
                      WaveformBars(
                        progress: progress.toDouble(),
                        isPlaying: isPlaying,
                        onSeek: (f) => _seekAudio(b, f),
                      ),
                      const SizedBox(height: 6),

                      // Time row
                      Row(
                        children: [
                          Text(
                            _fmtDur(pos),
                            style: TextStyle(
                              color: isPlaying
                                  ? const Color(0xFF0A84FF)
                                  : Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '-${_fmtDur(remaining)}',
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
               const SizedBox(width: 6),

                // Drag handle
                ReorderableDragStartListener(
                index: _blocks.indexWhere((bl) => bl.id == b.id) + 1,
                child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                    ),
                    child: const Icon(
                    Icons.drag_handle_rounded,
                    size: 14,
                    color: Colors.white24,
                    ),
                ),
                ),
                const SizedBox(width: 6),

                // Delete button (unchanged)
                GestureDetector(
                onTap: () => _confirmRemoveBlock(b),
                child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white30),
                ),
                ),
              ],
            ),
          ),

          // ── Bottom mic label strip ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Row(
                children: [
                    Icon(
                    Icons.mic_rounded,
                    size: 12,
                    color: isPlaying
                        ? const Color(0xFF0A84FF).withValues(alpha: 0.7)
                        : Colors.white24,
                    ),
                    const SizedBox(width: 5),
                    Text(
                    'Voice note',
                    style: TextStyle(
                        color: isPlaying
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.7)
                            : Colors.white24,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                    ),
                    ),
                    const Spacer(),
                    if (dur != Duration.zero)
                    Text(
                        _fmtDur(dur),
                        style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                        ),
                    ),
                    if (dur != Duration.zero) const SizedBox(width: 8),
                    // Move button
                    GestureDetector(
                    onTap: () => _showMoveSheet(b),
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                        color: const Color(0xFF64D2FF).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF64D2FF).withValues(alpha: 0.25),
                        ),
                        ),
                        child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Icon(Icons.drive_file_move_outline, size: 11, color: Color(0xFF64D2FF)),
                            SizedBox(width: 4),
                            Text(
                            'Move',
                            style: TextStyle(
                                color: Color(0xFF64D2FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                            ),
                            ),
                        ],
                        ),
                    ),
                    ),
                ],
                ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PDF block
  // ─────────────────────────────────────────────────────────────

  Widget _buildPdfBlock(NoteBlock b) {
    final name = b.pdfName ?? 'document.pdf';
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
          border: Border.all(
            color: const Color(0xFFFF6B9D).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF2E0A18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF6B9D).withValues(alpha: 0.4),
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFFFF6B9D),
                    size: 20,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'PDF',
                    style: TextStyle(
                      color: Color(0xFFFF6B9D),
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        pageLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      const Text(
                        ' · ',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                      Text(
                        sizeLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFF6B9D).withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'Open',
                style: TextStyle(
                  color: Color(0xFFFF6B9D),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmRemoveBlock(b),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveBlock(NoteBlock b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Remove block?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
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
          // Row 1 — heading style chips
          _fmtRow([
            NoteTChip(
              'H1',
              _fmtH1,
              const Color(0xFFFF6B9D),
              () => _applyParagraphFmt((b) {
                b.isH1 = !b.isH1;
                b.isH2 = b.isH3 = b.isH4 = false;
              }),
            ),
            NoteTChip(
              'H2',
              _fmtH2,
              const Color(0xFFFF9F0A),
              () => _applyParagraphFmt((b) {
                b.isH2 = !b.isH2;
                b.isH1 = b.isH3 = b.isH4 = false;
              }),
            ),
            NoteTChip(
              'H3',
              _fmtH3,
              const Color(0xFFFFD60A),
              () => _applyParagraphFmt((b) {
                b.isH3 = !b.isH3;
                b.isH1 = b.isH2 = b.isH4 = false;
              }),
            ),
            NoteTChip(
              'H4',
              _fmtH4,
              const Color(0xFF64D2FF),
              () => _applyParagraphFmt((b) {
                b.isH4 = !b.isH4;
                b.isH1 = b.isH2 = b.isH3 = false;
              }),
            ),
            NoteTChip(
              'body',
              !_fmtH1 && !_fmtH2 && !_fmtH3 && !_fmtH4,
              Colors.white,
              () => _applyParagraphFmt(
                (b) => b.isH1 = b.isH2 = b.isH3 = b.isH4 = false,
              ),
            ),
          ]),

          // Row 2 — inline: B / I / U / S + alignment + lists
          _fmtRow([
            NoteFBtn(
              'B',
              bold: true,
              active: _fmtBold,
              onTap: () => _applyInlineFmt((s) => s.bold = !s.bold),
            ),
            NoteFBtn(
              'I',
              italic: true,
              active: _fmtItalic,
              onTap: () => _applyInlineFmt((s) => s.italic = !s.italic),
            ),
            NoteFBtn(
              'U',
              under: true,
              active: _fmtUnder,
              onTap: () => _applyInlineFmt((s) => s.underline = !s.underline),
            ),
            NoteFBtn(
              'S',
              strike: true,
              active: _fmtStrike,
              onTap: () =>
                  _applyInlineFmt((s) => s.strikethrough = !s.strikethrough),
            ),
            NoteIBtn(
              Icons.link_rounded,
              _fmtUrl != null && _fmtUrl!.isNotEmpty,
              _showLinkDialog,
            ),
            const NoteToolbarSep(),
            NoteIBtn(
              Icons.format_align_left_rounded,
              _fmtAlign == NoteAlign.left,
              () => _applyParagraphFmt((b) => b.align = NoteAlign.left),
            ),
            NoteIBtn(
              Icons.format_align_center_rounded,
              _fmtAlign == NoteAlign.center,
              () => _applyParagraphFmt((b) => b.align = NoteAlign.center),
            ),
            NoteIBtn(
              Icons.format_align_right_rounded,
              _fmtAlign == NoteAlign.right,
              () => _applyParagraphFmt((b) => b.align = NoteAlign.right),
            ),
            const NoteToolbarSep(),
            NoteIBtn(
              Icons.format_list_numbered_rounded,
              _fmtOL,
              () => _applyParagraphFmt((b) {
                b.orderedList = !b.orderedList;
                b.bulletList = false;
              }),
            ),
            NoteIBtn(
              Icons.format_list_bulleted_rounded,
              _fmtBL,
              () => _applyParagraphFmt((b) {
                b.bulletList = !b.bulletList;
                b.orderedList = false;
              }),
            ),
          ]),

          // Row 3 — text colour
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ..._textColors.map(
              (c) => NoteColorDot(
                color: c == _kCustomColor ? null : c,
                selected: c == _kCustomColor
                    ? (_fmtColor != null && !_textColors.contains(_fmtColor))
                    : c == _fmtColor,
                isCustom: c == _kCustomColor,
                customPreview:
                    (_fmtColor != null && !_textColors.contains(_fmtColor))
                    ? _fmtColor
                    : null,
                onTap: () => c == _kCustomColor
                    ? _showColorPicker(isHighlight: false)
                    : _applyInlineFmt((s) => s.color = c),
              ),
            ),
          ]),

          // Row 4 — highlight colour
          _fmtRow([
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Center(
                child: Icon(
                  Icons.highlight_rounded,
                  size: 14,
                  color: Colors.white38,
                ),
              ),
            ),
            ..._highlights.map(
              (c) => NoteColorDot(
                color: c,
                selected: c == _fmtHighlight,
                onTap: () => _applyInlineFmt((s) => s.highlight = c),
              ),
            ),
            // Custom highlight dot
            NoteColorDot(
              color: null,
              isCustom: true,
              selected:
                  _fmtHighlight != null && !_highlights.contains(_fmtHighlight),
              customPreview:
                  (_fmtHighlight != null &&
                      !_highlights.contains(_fmtHighlight))
                  ? _fmtHighlight
                  : null,
              onTap: () => _showColorPicker(isHighlight: true),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _fmtRow(List<Widget> children) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      children: children,
    ),
  );

  // ─────────────────────────────────────────────────────────────
  // Bottom bar
  // ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0F),
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BarIcon(
            icon: CupertinoIcons.photo_fill_on_rectangle_fill,
            onTap: _showImageOptions,
          ),
          _BarIcon(icon: Icons.picture_as_pdf_rounded, onTap: _pickPdf),
          _BarIcon(
            icon: CupertinoIcons.textformat,
            active: _showFormatBar,
            activeColor: const Color(0xFFFFD60A),
            onTap: () => setState(() => _showFormatBar = !_showFormatBar),
          ),
          _BarIcon(
            icon: CupertinoIcons.mic_solid,
            active: _recording,
            activeColor: const Color(0xFFFF3B30),
            onTap: _recording ? _stopRecording : _toggleRecording,
          ),
          _BarIcon(
            icon: CupertinoIcons.checkmark_square,
            onTap: _addCheckboxBlock,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    final hour12 = l.hour % 12 == 0 ? 12 : l.hour % 12; // ← fix
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year},  '
        '${hour12.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')} '
        '${l.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _ImageOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
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
        width: 52,
        height: 56,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 24,
              color: active ? activeColor : Colors.white60,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

void showProjectNoteSheet(
  BuildContext context, {
  required Project project,
  Future<void> Function(String title, String? note)? onSaveNote,
  Future<void> Function()? onClearNote,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProjectNoteSheet(
        project: project,
        onSaveNote: onSaveNote,
        onClearNote: onClearNote,
      ),
    ),
  );
}
