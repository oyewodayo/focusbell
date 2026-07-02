// ─────────────────────────────────────────────────────────────────────────────
// project_note_actions_mixin.dart
//
// All "write" operations on the note document:
//   • ensureTrailingTextBlock, applyInlineFmt, applyParagraphFmt
//   • addTextBlockAfter, addCheckboxBlock, removeBlock
//   • recomputeCheckboxTotal
//   • handleTextTap  (URL hit-testing)
//   • showImageOptions / pickImage
//   • pickPdf
//   • showLinkDialog
//   • startRecording / stopRecording / cancelRecording / togglePlayback / seekAudio
//   • showMoveSheet  (move audio block to another project/note)
//   • autoDetectLinks
//   • saveNote / clearNote / confirmRemoveBlock
//   • showColorPicker
//   • setNoteReminder / clearNoteReminder   ← NEW
//
// Accesses shared state via NoteStateInterface abstract getters — no casting.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/services/app_controller.dart';
import 'package:focusbell/services/note_rich_controller.dart';
import 'package:focusbell/services/note_reminder_service.dart';
import 'package:focusbell/services/reminder_service.dart';
import 'package:focusbell/models/reminder_model.dart';
import 'package:focusbell/services/standalone_note_controller.dart';
import 'package:focusbell/utils/app_toast.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:focusbell/services/note_rich_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'project_note_state_interface.dart';

mixin ProjectNoteActionsMixin on State<ProjectNoteSheet>, NoteStateInterface {
  // ─────────────────────────────────────────────────────────────────────────
  // Formatting helpers
  // ─────────────────────────────────────────────────────────────────────────

  void applyInlineFmt(void Function(NoteSeg seg) apply) {
    final b = activeBlock;
    final c = activeCtrl;
    if (b == null || c == null) return;

    final sel = c.selection;
    final start = (sel.isValid && !sel.isCollapsed) ? sel.start : 0;
    final end = (sel.isValid && !sel.isCollapsed) ? sel.end : c.text.length;

    setState(() {
      c.applyToRange(start, end, apply);
      b.segs = List.from(c.segs);
      c.rebuildText();
      refreshFmtBar(b, c);
      dirty = true;
    });
  }

  void applyParagraphFmt(void Function(NoteBlock b) apply) {
    final b = activeBlock;
    if (b == null) return;
    setState(() {
      apply(b);
      final c = activeCtrl;
      if (c != null) refreshFmtBar(b, c);
      dirty = true;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Block management
  // ─────────────────────────────────────────────────────────────────────────

  void addTextBlockAfter(String afterId) {
    final idx = blocks.indexWhere((b) => b.id == afterId);
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    blocks.insert(idx + 1, nb);
    initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => fn[nb.id]?.requestFocus(),
    );
  }

  void addCheckboxBlock() {
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.checkbox);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;
    blocks.insert(idx, nb);
    initBlock(nb);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => fn[nb.id]?.requestFocus(),
    );
  }

  void removeBlock(String id) {
    final idx = blocks.indexWhere((b) => b.id == id);
    if (idx == -1) return;

    final block = blocks[idx];
    final textBlocks = blocks.where(
      (b) => b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox,
    );

    if (blocks.length <= 1 ||
        (textBlocks.length == 1 && textBlocks.first.id == id)) {
      final c = ctrl[id];
      if (c != null) {
        c.segs = [];
        c.text = '';
        blocks[idx].segs = [];
      }
      setState(() => dirty = true);
      return;
    }

    if (block.type == NoteBlockType.pdf && block.pdfPath != null) {
      File(block.pdfPath!).delete().catchError((_) {});
    }

    final ctrlToDispose = ctrl[id];
    final fnToDispose = fn[id];

    setState(() {
      ctrl.remove(id);
      fn.remove(id);
      textKeys.remove(id);
      blocks.removeAt(idx);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!suppressTotalRecompute) recomputeCheckboxTotal();
      suppressTotalRecompute = false;
      ctrlToDispose?.dispose();
      fnToDispose?.dispose();
    });

    final focusIdx = (idx - 1).clamp(0, blocks.length - 1);
    final targetId = blocks[focusIdx].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fn[targetId]?.requestFocus();
      final c = ctrl[targetId];
      if (c != null)
        c.selection = TextSelection.collapsed(offset: c.text.length);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Checkbox total auto-computation
  // ─────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  // Extracts the monetary/numeric amount from a checkbox block's text.
  // Uses the LAST number found in the flattened text, supporting:
  //   "1000"             → 1000
  //   "food: 5000"       → 5000
  //   "water – 2,000"    → 2000
  //   "1000\ncloth–3000" → 3000  (last number)
  // ─────────────────────────────────────────────────────────────────────────
  double? _extractBlockAmount(NoteBlock b) {
    // Prefer live controller text (includes unsaved edits)
    final raw = (ctrl[b.id]?.text.isNotEmpty == true)
        ? ctrl[b.id]!.text
        : b.segs.map((s) => s.text).join();

    // Match integers or decimals with optional comma-thousands separators
    final matches = RegExp(r'[\d,]+(?:\.\d+)?').allMatches(raw).toList();
    if (matches.isEmpty) return null;

    // Walk backwards — first parseable number from the end is the amount
    for (final m in matches.reversed) {
      final val = double.tryParse(m.group(0)!.replaceAll(',', ''));
      if (val != null && val > 0) return val;
    }
    return null;
  }

    void recomputeCheckboxTotal() {
  if (suppressTotalRecompute) {
    suppressTotalRecompute = false;
    return;
  }

  double sum = 0;
  bool anyAmount = false;

  for (final b in blocks) {
    if (b.type != NoteBlockType.checkbox) continue;
    // Skip the total row itself
    final plainText = (ctrl[b.id]?.text ?? b.segs.map((s) => s.text).join());
    if (plainText.trimLeft().startsWith('Checkbox Total:')) continue;

    final amount = _extractBlockAmount(b);
    if (amount != null) {
      sum += amount;
      anyAmount = true;
    }
  }

  if (!anyAmount) {
    final hadTotal = blocks.any((b) =>
        b.type == NoteBlockType.checkbox &&
        (ctrl[b.id]?.text ?? b.segs.map((s) => s.text).join())
            .trimLeft()
            .startsWith('Checkbox Total:'));
    if (hadTotal) {
      blocks.removeWhere((b) =>
          b.type == NoteBlockType.checkbox &&
          (ctrl[b.id]?.text ?? b.segs.map((s) => s.text).join())
              .trimLeft()
              .startsWith('Checkbox Total:'));
      if (mounted) setState(() => dirty = true);
    }
    return;
  }

  final totalText = 'Checkbox Total: ${_fmtTotal(sum)}';

  // Use controller text for the lookup — not segs — so it's always current
  final existingIndex = blocks.indexWhere((b) =>
      b.type == NoteBlockType.checkbox &&
      (ctrl[b.id]?.text ?? b.segs.map((s) => s.text).join())
          .trimLeft()
          .startsWith('Checkbox Total:'));

  if (existingIndex >= 0) {
    final tb = blocks[existingIndex];
    // Sync BOTH segs and controller
    tb.segs = [NoteSeg(text: totalText)];
    final c = ctrl[tb.id];
    if (c != null) {
      c.segs = [NoteSeg(text: totalText)];
      c.rebuildText();
    }
  } else {
    final tb = NoteBlock(
      id: noteUid(),
      type: NoteBlockType.checkbox,
      segs: [NoteSeg(text: totalText)],
    );
    final c = NoteRichController(segs: [NoteSeg(text: totalText)]);
    ctrl[tb.id] = c;
    fn[tb.id] = FocusNode();
    textKeys[tb.id] = GlobalKey();
    blocks.add(tb);
  }

  if (mounted) setState(() => dirty = true);
}


  /// Formats a double total with comma-grouping.
  /// 11000.0  → "11,000"
  /// 2500.5   → "2,500.5"
  String _fmtTotal(double v) {
    final isWhole = v == v.truncateToDouble();
    final raw = isWhole
        ? v.toInt().toString()
        : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');

    // Insert thousand-separators into the integer part
    final parts = raw.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '$buf$decPart';
  }

  String _commas(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // URL tap detection
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> handleTextTap(NoteBlock b, TapUpDetails details) async {
    final c = ctrl[b.id];
    if (c == null) return;
    final key = textKeys[b.id];
    if (key == null) return;

    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null) return;

    RenderEditable? re;
    void visit(RenderObject child) {
      if (child is RenderEditable) {
        re = child;
        return;
      }
      child.visitChildren(visit);
    }

    renderObject.visitChildren(visit);
    if (re == null) return;

    final localPos = re!.globalToLocal(details.globalPosition);
    final offset = re!.getPositionForPoint(localPos).offset;
    final url = c.urlAt(offset);
    if (url == null || url.isEmpty) return;

    final urlStr = url.startsWith('http') ? url : 'https://$url';
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image picker
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file == null) return;

    final imgBlock = NoteBlock(
      id: noteUid(),
      type: NoteBlockType.image,
      imagePath: file.path,
    );
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;

    setState(() {
      blocks.insert(idx, imgBlock);
      blocks.insert(idx + 1, textAfter);
      dirty = true;
    });
    initBlock(textAfter);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => fn[textAfter.id]?.requestFocus(),
    );
  }

  void showImageOptions() {
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
                _ImageOptionRow(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  onTap: () {
                    Navigator.pop(context);
                    pickImage(ImageSource.camera);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _ImageOptionRow(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose Photo',
                  onTap: () {
                    Navigator.pop(context);
                    pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PDF picker
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> pickPdf() async {
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
    final destPath =
        '${docsDir.path}/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
    await File(picked.path!).copy(destPath);

    int pageCount = 0;
    try {
      final bytes = await File(destPath).readAsBytes();
      pageCount = RegExp(
        r'/Type\s*/Page[^s]',
      ).allMatches(String.fromCharCodes(bytes)).length;
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
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;

    setState(() {
      blocks.insert(idx, pdfBlock);
      blocks.insert(idx + 1, textAfter);
      dirty = true;
    });
    initBlock(textAfter);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => fn[textAfter.id]?.requestFocus(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Link dialog
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showLinkDialog() async {
    final c = activeCtrl;
    if (c == null) return;

    final sel = c.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final existing = (c.styleAt(sel)['url'] as String?) ?? '';
    final selectedText = hasSelection
        ? c.text.substring(sel.start, sel.end).trim()
        : '';
    final looksLikeUrl =
        selectedText.startsWith('http://') ||
        selectedText.startsWith('https://') ||
        selectedText.startsWith('www.');

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

    final result = await showDialog<Map<String, String>>(
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
              _dialogField(textCtrl, 'Link text'),
              const SizedBox(height: 10),
            ],
            _dialogField(
              urlCtrl,
              'https://',
              keyboardType: TextInputType.url,
              autofocus: true,
              prefixIcon: const Icon(
                Icons.link_rounded,
                color: Color(0xFF64D2FF),
                size: 18,
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      urlCtrl.dispose();
      textCtrl.dispose();
    });

    if (result == null) return;
    final url = result['url']!;
    final linkText = result['text']!;
    final remove = url.isEmpty;

    if (hasSelection) {
      applyInlineFmt((seg) => remove ? seg.url = null : seg.url = url);
    } else if (!remove && linkText.isNotEmpty) {
      final b = activeBlock;
      final at = c.selection.baseOffset;
      final newSeg = NoteSeg(
        text: linkText,
        url: url,
        underline: true,
        color: const Color(0xFF64D2FF),
      );
      setState(() {
        c.segs = NoteRichController.insSegs(c.segs, at, linkText, newSeg);
        int pos = 0;
        for (final seg in c.segs) {
          if (pos >= at && pos < at + linkText.length) {
            seg.url = url;
            seg.color = const Color(0xFF64D2FF);
            seg.underline = true;
          }
          pos += seg.text.length;
        }
        c.segs = NoteRichController.mergeSegs(c.segs);
        b?.segs = List.from(c.segs);
        c.rebuildText();
        dirty = true;
      });
    }
  }

  Widget _dialogField(
    TextEditingController c,
    String hint, {
    TextInputType? keyboardType,
    bool autofocus = false,
    Widget? prefixIcon,
  }) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
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
        prefixIcon: prefixIcon,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
// Audio recording
// ─────────────────────────────────────────────────────────────────────────

Future<void> toggleRecording() async =>
    recording ? await stopRecording() : await startRecording();

Future<void> startRecording() async {
  if (!await recorder.hasPermission()) {
    if (mounted) {
      AppToast.show(context,
          msg: 'Microphone permission is required',
          backgroundColor: const Color(0xFF2A1A1A),
          textColor: const Color(0xFFFF3B30));
    }
    return;
  }

  final dir = await getApplicationDocumentsDirectory();
  final path =
      '${dir.path}/note_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

  try {
    // Keep the CPU/screen awake for the duration of the recording so the
    // OS doesn't suspend the mic session mid-capture on long recordings.
    await WakelockPlus.enable();

    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        // Bump this up if you're recording lectures/seminars, not quick notes —
        // higher bitrate = more reliable playback of speech over long durations.
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
  } catch (e) {
    await WakelockPlus.disable();
    if (mounted) {
      AppToast.show(context,
          msg: '⚠️ Could not start recording: $e',
          backgroundColor: const Color(0xFF2A1A1A),
          textColor: const Color(0xFFFF3B30));
    }
    return;
  }

  recStart = DateTime.now();
  recElapsed = Duration.zero;
  recTicker?.dispose();
  recTicker = createTicker((_) {
    if (recStart != null && mounted) {
      setState(() => recElapsed = DateTime.now().difference(recStart!));
    }
  })..start();

  if (mounted) setState(() => recording = true);
}

Future<void> stopRecording() async {
  recTicker?.stop();

  String? path;
  try {
    path = await recorder.stop();
  } catch (e) {
    await WakelockPlus.disable();
    if (mounted) {
      setState(() {
        recording = false;
        recElapsed = Duration.zero;
      });
      AppToast.show(context,
          msg: '⚠️ Recording failed to stop cleanly: $e',
          backgroundColor: const Color(0xFF2A1A1A),
          textColor: const Color(0xFFFF3B30));
    }
    return;
  }

  await WakelockPlus.disable();

  // Capture elapsed time BEFORE resetting it — this was the bug that made
  // saved recordings show up with a duration of 0.
  final capturedElapsed = recElapsed;

  setState(() {
    recording = false;
    recElapsed = Duration.zero;
  });

  if (path == null) {
    if (mounted) {
      AppToast.show(context,
          msg: '⚠️ Recording did not produce a file',
          backgroundColor: const Color(0xFF2A1A1A),
          textColor: const Color(0xFFFF3B30));
    }
    return;
  }

  // Verify the file actually has content before trusting it. An .m4a whose
  // container never got finalized (app killed / OS reclaimed mic mid-recording)
  // can leave a near-empty or missing file — better to know now than to
  // discover it later when the "note" turns out to hold nothing.
  final file = File(path);
  final exists = await file.exists();
  final sizeBytes = exists ? await file.length() : 0;
  const minPlausibleBytes = 2048; // a real recording is always well above this

  if (!exists || sizeBytes < minPlausibleBytes) {
    if (mounted) {
      AppToast.show(context,
          msg: '⚠️ Recording looks empty or corrupted (${sizeBytes}B). '
              'Check Settings → Storage for the raw file at:\n$path',
          backgroundColor: const Color(0xFF2A1A1A),
          textColor: const Color(0xFFFF3B30));
    }
    // Still fall through and attach the block below — you get the warning
    // immediately AND keep the file reference/path in case it's partially
    // recoverable, instead of silently losing the pointer to it.
  }

  final audioBlock = NoteBlock(
    id: noteUid(),
    type: NoteBlockType.audio,
    audioPath: path,
    audioDuration: capturedElapsed,
  );
  final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
  final idx = activeId == null
      ? blocks.length
      : blocks.indexWhere((b) => b.id == activeId) + 1;

  setState(() {
    blocks.insert(idx, audioBlock);
    blocks.insert(idx + 1, textAfter);
    dirty = true;
  });
  initBlock(textAfter);
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => fn[textAfter.id]?.requestFocus(),
  );

  // Save immediately after a successful recording — don't let a crash or
  // an accidental back-swipe lose 50 minutes of audio that's just sitting
  // dirty in memory.
  if (sizeBytes >= minPlausibleBytes) {
    await saveNote();
  }
}

Future<void> cancelRecording() async {
  recTicker?.stop();
  await WakelockPlus.disable();
  await recorder.cancel();
  setState(() {
    recording = false;
    recElapsed = Duration.zero;
  });
}

  // ─────────────────────────────────────────────────────────────────────────
  // Audio playback
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> togglePlayback(NoteBlock b) async {
    final isPlaying = playing[b.id] ?? false;
    if (isPlaying) {
      await player.pause();
      positionPoller?.cancel();
      setState(() {
        playing[b.id] = false;
        currentlyPlayingId = null;
      });
    } else {
      for (final k in playing.keys.toList()) playing[k] = false;
      positionPoller?.cancel();
      await player.play(DeviceFileSource(b.audioPath!));
      setState(() {
        playing[b.id] = true;
        currentlyPlayingId = b.id;
        activeId = b.id;
      });
      positionPoller = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (!mounted || currentlyPlayingId == null) return;
        final pos = await player.getCurrentPosition();
        if (pos != null) setState(() => playPos[currentlyPlayingId!] = pos);
      });
    }
  }

  Future<void> seekAudio(NoteBlock b, double fraction) async {
    final dur = playDur[b.id] ?? b.audioDuration;
    if (dur == Duration.zero) return;
    final target = Duration(
      milliseconds: (dur.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    );
    await player.seek(target);
    setState(() => playPos[b.id] = target);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Move audio block to another note / project
  // ─────────────────────────────────────────────────────────────────────────

  void showMoveSheet(NoteBlock audioBlock) {
    final isStandalone = widget.onSaveNote != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final List<Widget> items;

        if (isStandalone) {
          final notes = StandaloneNoteController.instance.notes
              .where((n) => n.id != widget.project.id)
              .toList();
          items = notes.map((note) {
            final title = note.title.isEmpty ? 'Untitled' : note.title;
            return ListTile(
              leading: const Icon(
                Icons.note_outlined,
                color: Colors.white38,
                size: 18,
              ),
              title: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() {
                  blocks.removeWhere((bl) => bl.id == audioBlock.id);
                  dirty = true;
                });
                await saveNote();
                final target = StandaloneNoteController.instance.find(note.id);
                if (target == null) return;
                final tBlocks = NoteBlock.decodeList(target.note)
                  ..add(audioBlock);
                await StandaloneNoteController.instance.saveNote(
                  note.id,
                  note.title,
                  NoteBlock.encodeList(tBlocks),
                );
                if (mounted)
                  AppToast.show(
                    context,
                    msg: 'Moved to "$title"',
                    backgroundColor: const Color(0xFF0A1F0A),
                    textColor: const Color(0xFF34C759),
                  );
              },
            );
          }).toList();
        } else {
          final projects = AppController.instance.projects
              .where((p) => p.id != widget.project.id)
              .toList();
          items = projects
              .map(
                (project) => ListTile(
                  leading: Container(
                    width: 8,
                    height: 8,
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
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() {
                      blocks.removeWhere((bl) => bl.id == audioBlock.id);
                      dirty = true;
                    });
                    await saveNote();
                    final tp = AppController.instance.projects.firstWhere(
                      (p) => p.id == project.id,
                    );
                    final tBlocks = NoteBlock.decodeList(tp.note)
                      ..add(audioBlock);
                    await AppController.instance.updateProjectNote(
                      project.id,
                      NoteBlock.encodeList(tBlocks),
                    );
                    if (mounted)
                      AppToast.show(
                        context,
                        msg: 'Moved to "${project.name}"',
                        backgroundColor: const Color(0xFF0A1F0A),
                        textColor: const Color(0xFF34C759),
                      );
                  },
                ),
              )
              .toList();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              isStandalone ? 'Move to note' : 'Move to project',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  isStandalone
                      ? 'No other notes available'
                      : 'No other projects available',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              Flexible(child: ListView(shrinkWrap: true, children: items)),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-link detection
  // ─────────────────────────────────────────────────────────────────────────

  static final _urlRegex = RegExp(
    r'(?:https?://|www\.)\S+',
    caseSensitive: false,
  );

  void autoDetectLinks() {
    for (final b in blocks) {
      if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox)
        continue;
      final c = ctrl[b.id];
      if (c == null) continue;

      bool changed = false;
      final newSegs = <NoteSeg>[];

      for (final seg in c.segs) {
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
          if (m.start > cursor) {
            newSegs.add(
              seg.copyWith(text: seg.text.substring(cursor, m.start)),
            );
          }
          final urlText = m.group(0)!;
          newSegs.add(
            seg.copyWith(
              text: urlText,
              url: urlText.startsWith('http') ? urlText : 'https://$urlText',
              underline: true,
              color: const Color(0xFF64D2FF),
            ),
          );
          cursor = m.end;
        }
        if (cursor < seg.text.length) {
          newSegs.add(seg.copyWith(text: seg.text.substring(cursor)));
        }
      }

      if (changed) {
        c.segs = NoteRichController.mergeSegs(newSegs);
        b.segs = List.from(c.segs);
        c.rebuildText();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Save / clear / remove
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveNote() async {
    autoDetectLinks();
    for (final b in blocks) {
      if (ctrl[b.id] != null) b.segs = List.from(ctrl[b.id]!.segs);
    }
    final trimmed = blocks.length > 1
        ? (blocks.toList()..removeWhere(
            (b) =>
                b == blocks.last &&
                b.type == NoteBlockType.text &&
                b.plainText.trim().isEmpty,
          ))
        : blocks;
    final encoded = NoteBlock.encodeList(trimmed);

    if (widget.onSaveNote != null) {
      await widget.onSaveNote!(titleCtrl.text.trim(), encoded);
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
        dirty = false;
        readOnly = true;
        FocusScope.of(context).unfocus();
      });
    }
  }

  Future<void> clearNote() async {
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

  Future<void> confirmRemoveBlock(NoteBlock b) async {
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
    if (ok == true) removeBlock(b.id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Note reminder — set / clear
  // ─────────────────────────────────────────────────────────────────────────

  /// Shows a date+time picker, then schedules a [Reminder] via [ReminderService]
  /// and persists the DateTime in [NoteReminderService].
  Future<void> setNoteReminder() async {
    final now = DateTime.now();

    // Step 1 — date picker.
    final date = await showDatePicker(
      context: context,
      initialDate: noteReminder ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9F0A),
            onPrimary: Colors.black,
            surface: Color(0xFF1E1E1E),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF1A1A1A),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    // Step 2 — time picker.
    final initialTime = noteReminder != null
        ? TimeOfDay.fromDateTime(noteReminder!)
        : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)));

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9F0A),
            onPrimary: Colors.black,
            surface: Color(0xFF1E1E1E),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF1A1A1A),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final remindAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (remindAt.isBefore(now)) {
      AppToast.show(
        context,
        msg: 'Choose a future time',
        backgroundColor: const Color(0xFF2A1A1A),
        textColor: const Color(0xFFFF3B30),
      );
      return;
    }

    // Cancel any existing reminder for this note before creating a new one.
    await _cancelExistingReminder();

    // Build the title used in the Reminders screen.
    final noteTitle = titleCtrl.text.trim();
    final reminderTitle = noteTitle.isEmpty
        ? 'Note reminder'
        : 'Reminder: $noteTitle';

    // Create a once-off Reminder via the shared ReminderService.
    final reminder = Reminder(
      id: 'note_${widget.project.id}',
      title: reminderTitle,
      dateTime: remindAt,
      repeat: RepeatDays.once(),
      priority: ReminderPriority.normal,
      notes: noteTitle.isEmpty ? null : noteTitle,
    );

    await ReminderService.instance.add(reminder);
    await NoteReminderService.instance.set(widget.project.id, remindAt);

    if (mounted) {
      setState(() => noteReminder = remindAt);
      AppToast.show(
        context,
        msg: '🔔 Reminder set',
        backgroundColor: const Color(0xFF1A1F0A),
        textColor: const Color(0xFFFF9F0A),
      );
    }
  }

  /// Clears the scheduled reminder for this note.
  Future<void> clearNoteReminder() async {
    await _cancelExistingReminder();
    await NoteReminderService.instance.clear(widget.project.id);
    if (mounted) {
      setState(() => noteReminder = null);
      AppToast.show(
        context,
        msg: 'Reminder removed',
        backgroundColor: const Color(0xFF1A1A1A),
        textColor: const Color(0xFFFF3B30),
      );
    }
  }

  Future<void> _cancelExistingReminder() async {
    final existingId = 'note_${widget.project.id}';
    try {
      await ReminderService.instance.remove(existingId);
    } catch (_) {
      // Not found — that's fine.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Custom HSV colour picker
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showColorPicker({required bool isHighlight}) async {
    Color current = isHighlight
        ? (fmtHighlight ?? const Color(0xFFFFD60A))
        : (fmtColor ?? Colors.white);
    if (isHighlight) current = current.withValues(alpha: 1.0);
    HSVColor hsv = HSVColor.fromColor(current);

    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
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
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                ),
                const SizedBox(height: 16),
                _hsvSlider(
                  ctx,
                  'Hue',
                  hsv.hue,
                  0,
                  360,
                  HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                  (v) => setLocal(() => hsv = hsv.withHue(v)),
                ),
                _hsvSlider(
                  ctx,
                  'Saturation',
                  hsv.saturation,
                  0,
                  1,
                  hsv.toColor(),
                  (v) => setLocal(() => hsv = hsv.withSaturation(v)),
                ),
                _hsvSlider(
                  ctx,
                  'Brightness',
                  hsv.value,
                  0,
                  1,
                  hsv.toColor(),
                  (v) => setLocal(() => hsv = hsv.withValue(v)),
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
      ),
    );

    if (picked == null) return;
    if (isHighlight)
      applyInlineFmt((seg) => seg.highlight = picked);
    else
      applyInlineFmt((seg) => seg.color = picked);
  }

  Widget _hsvSlider(
    BuildContext ctx,
    String label,
    double value,
    double min,
    double max,
    Color activeColor,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        SliderTheme(
          data: SliderTheme.of(ctx).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: activeColor,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ── Private helper used only within this mixin ────────────────────────────────
class _ImageOptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ImageOptionRow({
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
