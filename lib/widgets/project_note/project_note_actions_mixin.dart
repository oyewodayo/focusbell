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
import 'package:focusbell/services/standalone_note_controller.dart';
import 'package:focusbell/utils/app_toast.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';


import 'project_note_state_interface.dart';

mixin ProjectNoteActionsMixin on State<ProjectNoteSheet>, NoteStateInterface {

  // ─────────────────────────────────────────────────────────────────────────
  // Formatting helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Applies [apply] to every [NoteSeg] in the active selection, or the whole
  /// block when the cursor is collapsed.
  void applyInlineFmt(void Function(NoteSeg seg) apply) {
    final b = activeBlock;
    final c = activeCtrl;
    if (b == null || c == null) return;

    final sel = c.selection;
    final start = (sel.isValid && !sel.isCollapsed) ? sel.start : 0;
    final end   = (sel.isValid && !sel.isCollapsed) ? sel.end   : c.text.length;

    setState(() {
      c.applyToRange(start, end, apply);
      b.segs = List.from(c.segs);
      c.rebuildText();
      refreshFmtBar(b, c);
      dirty = true;
    });
  }

  /// Applies [apply] to the active [NoteBlock] for paragraph-level attributes
  /// (heading level, alignment, ordered / bullet list).
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

  /// Inserts a new empty text block immediately after [afterId] and focuses it.
  void addTextBlockAfter(String afterId) {
    final idx = blocks.indexWhere((b) => b.id == afterId);
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    blocks.insert(idx + 1, nb);
    initBlock(nb);
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => fn[nb.id]?.requestFocus());
  }

  /// Inserts a new checkbox block after the active block (or at the end).
  void addCheckboxBlock() {
    final nb = NoteBlock(id: noteUid(), type: NoteBlockType.checkbox);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;
    blocks.insert(idx, nb);
    initBlock(nb);
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => fn[nb.id]?.requestFocus());
  }

  /// Removes the block with [id].  If it is the only editable block, clears
  /// its content instead of deleting the block entirely.
  void removeBlock(String id) {
    final idx = blocks.indexWhere((b) => b.id == id);
    if (idx == -1) return;

    final block = blocks[idx];
    final textBlocks = blocks.where(
      (b) => b.type == NoteBlockType.text || b.type == NoteBlockType.checkbox,
    );

    // Wipe content instead of removing the last editable block.
    if (blocks.length <= 1 ||
        (textBlocks.length == 1 && textBlocks.first.id == id)) {
      final c = ctrl[id];
      if (c != null) { c.segs = []; c.text = ''; blocks[idx].segs = []; }
      setState(() => dirty = true);
      return;
    }

    // Delete associated temp PDF to avoid storage leaks.
    if (block.type == NoteBlockType.pdf && block.pdfPath != null) {
      File(block.pdfPath!).delete().catchError((_) {});
    }

    // Capture refs BEFORE removing from maps — deferred disposal avoids the
    // "_dependents.isEmpty" assertion while the TextField is still mounted.
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

    // Focus the block above (or first) after removal.
    final focusIdx = (idx - 1).clamp(0, blocks.length - 1);
    final targetId = blocks[focusIdx].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fn[targetId]?.requestFocus();
      final c = ctrl[targetId];
      if (c != null) c.selection = TextSelection.collapsed(offset: c.text.length);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Checkbox total auto-computation
  // ─────────────────────────────────────────────────────────────────────────

  /// Scans numeric-only checkbox blocks.  If ≥ 2 exist, inserts / updates a
  /// read-only "Checkbox Total:" block after the last numeric one.
  void recomputeCheckboxTotal() {
    final numericBlocks = <({NoteBlock block, int value})>[];

    for (final b in blocks) {
      if (b.type != NoteBlockType.checkbox) continue;
      // Skip any existing total block.
      if (b.segs.isNotEmpty &&
          b.segs.first.text.trimLeft().startsWith('Checkbox Total:')) continue;
      final raw = b.plainText.replaceAll(RegExp(r'[\s,_]'), '');
      final n = int.tryParse(raw);
      if (n != null) numericBlocks.add((block: b, value: n));
    }

    final totalIdx = blocks.indexWhere(
      (b) =>
          b.type == NoteBlockType.checkbox &&
          b.segs.isNotEmpty &&
          b.segs.first.text.trimLeft().startsWith('Checkbox Total:'),
    );

    if (numericBlocks.length < 2) {
      // Remove stale total if fewer than 2 numeric inputs remain.
      if (totalIdx != -1) setState(() { blocks.removeAt(totalIdx); dirty = true; });
      return;
    }

    final sum = numericBlocks.fold(0, (acc, e) => acc + e.value);
    final label = 'Checkbox Total: ${_commas(sum)}';

    if (totalIdx != -1) {
      // Update in-place.
      final tb = blocks[totalIdx];
      final c = ctrl[tb.id];
      setState(() {
        tb.segs = [NoteSeg(text: label)];
        tb.checked = false;
        if (c != null) { c.segs = List.from(tb.segs); c.rebuildText(); }
        dirty = true;
      });
    } else {
      // Insert after the last numeric checkbox.
      final insertAfterIdx =
          blocks.indexWhere((b) => b.id == numericBlocks.last.block.id);
      final tb = NoteBlock(id: noteUid(), type: NoteBlockType.checkbox)
        ..segs = [NoteSeg(text: label)];
      blocks.insert(insertAfterIdx + 1, tb);
      initBlock(tb);
      final c = ctrl[tb.id];
      if (c != null) { c.segs = List.from(tb.segs); c.rebuildText(); }
      setState(() => dirty = true);
    }
  }

  /// Formats [n] with thousands commas, e.g. 1234567 → "1,234,567".
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

  /// Hit-tests [details] inside a text block to find a URL segment and opens
  /// it in an external browser.
  Future<void> handleTextTap(NoteBlock b, TapUpDetails details) async {
    final c = ctrl[b.id];
    if (c == null) return;
    final key = textKeys[b.id];
    if (key == null) return;

    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null) return;

    RenderEditable? re;
    void visit(RenderObject child) {
      if (child is RenderEditable) { re = child; return; }
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
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;

    final imgBlock = NoteBlock(
        id: noteUid(), type: NoteBlockType.image, imagePath: file.path);
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;

    setState(() { blocks.insert(idx, imgBlock); blocks.insert(idx + 1, textAfter); dirty = true; });
    initBlock(textAfter);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => fn[textAfter.id]?.requestFocus());
  }

  /// Bottom sheet offering camera or gallery as image sources.
  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                _ImageOptionRow(icon: Icons.camera_alt_rounded, label: 'Take Photo',
                    onTap: () { Navigator.pop(context); pickImage(ImageSource.camera); }),
                const Divider(height: 1, color: Colors.white10),
                _ImageOptionRow(icon: Icons.photo_library_rounded, label: 'Choose Photo',
                    onTap: () { Navigator.pop(context); pickImage(ImageSource.gallery); }),
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

    // Copy to app documents so the file survives the picker's temp directory.
    final docsDir = await getApplicationDocumentsDirectory();
    final destPath =
        '${docsDir.path}/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
    await File(picked.path!).copy(destPath);

    // Estimate page count by scanning raw PDF bytes.
    int pageCount = 0;
    try {
      final bytes = await File(destPath).readAsBytes();
      pageCount = RegExp(r'/Type\s*/Page[^s]')
          .allMatches(String.fromCharCodes(bytes))
          .length;
    } catch (_) {}

    final pdfBlock = NoteBlock(
      id: noteUid(), type: NoteBlockType.pdf,
      pdfPath: destPath, pdfName: picked.name,
      pdfSizeBytes: picked.size, pdfPageCount: pageCount,
    );
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;

    setState(() { blocks.insert(idx, pdfBlock); blocks.insert(idx + 1, textAfter); dirty = true; });
    initBlock(textAfter);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => fn[textAfter.id]?.requestFocus());
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
    final selectedText =
        hasSelection ? c.text.substring(sel.start, sel.end).trim() : '';
    final looksLikeUrl = selectedText.startsWith('http://') ||
        selectedText.startsWith('https://') ||
        selectedText.startsWith('www.');

    // Create controllers here; dispose AFTER dialog closes to avoid the
    // "_dependents.isEmpty" assertion from inside the dialog's build.
    final urlCtrl = TextEditingController(
        text: existing.isNotEmpty ? existing : looksLikeUrl ? selectedText : '');
    final textCtrl = TextEditingController(
        text: looksLikeUrl ? '' : selectedText);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Insert Link',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasSelection) ...[
              _dialogField(textCtrl, 'Link text'),
              const SizedBox(height: 10),
            ],
            _dialogField(urlCtrl, 'https://',
                keyboardType: TextInputType.url,
                autofocus: true,
                prefixIcon: const Icon(Icons.link_rounded,
                    color: Color(0xFF64D2FF), size: 18)),
          ],
        ),
        actions: [
          if (existing.isNotEmpty)
            TextButton(
                onPressed: () => Navigator.pop(ctx, {'url': '', 'text': ''}),
                child: const Text('Remove', style: TextStyle(color: Color(0xFFFF3B30)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(
                  ctx, {'url': urlCtrl.text.trim(), 'text': textCtrl.text.trim()}),
              child: const Text('Insert',
                  style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w700))),
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
          text: linkText, url: url, underline: true, color: const Color(0xFF64D2FF));
      setState(() {
        c.segs = NoteRichController.insSegs(c.segs, at, linkText, newSeg);
        int pos = 0;
        for (final seg in c.segs) {
          if (pos >= at && pos < at + linkText.length) {
            seg.url = url; seg.color = const Color(0xFF64D2FF); seg.underline = true;
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

  Widget _dialogField(TextEditingController c, String hint,
      {TextInputType? keyboardType, bool autofocus = false, Widget? prefixIcon}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true, fillColor: const Color(0xFF252525),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    if (!await recorder.hasPermission()) return;
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/note_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(), path: path);
    recStart = DateTime.now();
    recElapsed = Duration.zero;
    recTicker?.dispose();
    recTicker = createTicker((_) {
      if (recStart != null && mounted) {
        setState(() => recElapsed = DateTime.now().difference(recStart!));
      }
    })..start();
    setState(() => recording = true);
  }

  Future<void> stopRecording() async {
    recTicker?.stop();
    final path = await recorder.stop();
    setState(() { recording = false; recElapsed = Duration.zero; });
    if (path == null) return;

    final audioBlock = NoteBlock(
        id: noteUid(), type: NoteBlockType.audio,
        audioPath: path, audioDuration: recElapsed);
    final textAfter = NoteBlock(id: noteUid(), type: NoteBlockType.text);
    final idx = activeId == null
        ? blocks.length
        : blocks.indexWhere((b) => b.id == activeId) + 1;

    setState(() { blocks.insert(idx, audioBlock); blocks.insert(idx + 1, textAfter); dirty = true; });
    initBlock(textAfter);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => fn[textAfter.id]?.requestFocus());
  }

  Future<void> cancelRecording() async {
    recTicker?.stop();
    await recorder.cancel();
    setState(() { recording = false; recElapsed = Duration.zero; });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Audio playback
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> togglePlayback(NoteBlock b) async {
    final isPlaying = playing[b.id] ?? false;
    if (isPlaying) {
      await player.pause();
      positionPoller?.cancel();
      setState(() { playing[b.id] = false; currentlyPlayingId = null; });
    } else {
      for (final k in playing.keys.toList()) playing[k] = false;
      positionPoller?.cancel();
      await player.play(DeviceFileSource(b.audioPath!));
      setState(() { playing[b.id] = true; currentlyPlayingId = b.id; activeId = b.id; });
      // Poll every 100 ms — reliable even when the stream stalls.
      positionPoller = Timer.periodic(const Duration(milliseconds: 100), (_) async {
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
        milliseconds: (dur.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final List<Widget> items;

        if (isStandalone) {
          final notes = StandaloneNoteController.instance.notes
              .where((n) => n.id != widget.project.id)
              .toList();
          items = notes.map((note) {
            final title = note.title.isEmpty ? 'Untitled' : note.title;
            return ListTile(
              leading: const Icon(Icons.note_outlined, color: Colors.white38, size: 18),
              title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() { blocks.removeWhere((bl) => bl.id == audioBlock.id); dirty = true; });
                await saveNote();
                final target = StandaloneNoteController.instance.find(note.id);
                if (target == null) return;
                final tBlocks = NoteBlock.decodeList(target.note)..add(audioBlock);
                await StandaloneNoteController.instance
                    .saveNote(note.id, note.title, NoteBlock.encodeList(tBlocks));
                if (mounted) AppToast.show(context, msg: 'Moved to "$title"',
                    backgroundColor: const Color(0xFF0A1F0A), textColor: const Color(0xFF34C759));
              },
            );
          }).toList();
        } else {
          final projects = AppController.instance.projects
              .where((p) => p.id != widget.project.id)
              .toList();
          items = projects.map((project) => ListTile(
            leading: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: project.priority.color, shape: BoxShape.circle)),
            title: Text(project.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: project.description.isNotEmpty
                ? Text(project.description, style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            onTap: () async {
              Navigator.pop(ctx);
              setState(() { blocks.removeWhere((bl) => bl.id == audioBlock.id); dirty = true; });
              await saveNote();
              final tp = AppController.instance.projects.firstWhere((p) => p.id == project.id);
              final tBlocks = NoteBlock.decodeList(tp.note)..add(audioBlock);
              await AppController.instance.updateProjectNote(project.id, NoteBlock.encodeList(tBlocks));
              if (mounted) AppToast.show(context, msg: 'Moved to "${project.name}"',
                  backgroundColor: const Color(0xFF0A1F0A), textColor: const Color(0xFF34C759));
            },
          )).toList();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 14),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Text(isStandalone ? 'Move to note' : 'Move to project',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(isStandalone ? 'No other notes available' : 'No other projects available',
                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
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

  static final _urlRegex = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);

  /// Promotes bare URL text in all blocks to linked, underlined, blue segments.
  void autoDetectLinks() {
    for (final b in blocks) {
      if (b.type != NoteBlockType.text && b.type != NoteBlockType.checkbox) continue;
      final c = ctrl[b.id];
      if (c == null) continue;

      bool changed = false;
      final newSegs = <NoteSeg>[];

      for (final seg in c.segs) {
        if (seg.url != null && seg.url!.isNotEmpty) { newSegs.add(seg); continue; }
        final matches = _urlRegex.allMatches(seg.text).toList();
        if (matches.isEmpty) { newSegs.add(seg); continue; }
        changed = true;
        int cursor = 0;
        for (final m in matches) {
          if (m.start > cursor) {
            newSegs.add(seg.copyWith(text: seg.text.substring(cursor, m.start)));
          }
          final urlText = m.group(0)!;
          newSegs.add(seg.copyWith(
            text: urlText,
            url: urlText.startsWith('http') ? urlText : 'https://$urlText',
            underline: true, color: const Color(0xFF64D2FF),
          ));
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
    // Trim trailing empty text block before encoding.
    final trimmed = blocks.length > 1
        ? (blocks.toList()
          ..removeWhere((b) =>
              b == blocks.last &&
              b.type == NoteBlockType.text &&
              b.plainText.trim().isEmpty))
        : blocks;
    final encoded = NoteBlock.encodeList(trimmed);

    if (widget.onSaveNote != null) {
      await widget.onSaveNote!(titleCtrl.text.trim(), encoded);
    } else {
      await AppController.instance.updateProjectNote(widget.project.id, encoded);
    }

    if (mounted) {
      AppToast.show(context, msg: 'Note saved',
          backgroundColor: const Color(0xFF0A1F0A), textColor: const Color(0xFF34C759));
      setState(() { dirty = false; readOnly = true; FocusScope.of(context).unfocus(); });
    }
  }

  Future<void> clearNote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Clear note?', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text('All note content will be removed.',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: Color(0xFFFF3B30)))),
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
        title: const Text('Remove block?', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: Color(0xFFFF3B30)))),
        ],
      ),
    );
    if (ok == true) removeBlock(b.id);
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
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final preview =
            isHighlight ? hsv.toColor().withValues(alpha: 0.4) : hsv.toColor();
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(isHighlight ? 'Highlight color' : 'Text color',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 36,
                  decoration: BoxDecoration(color: preview,
                      borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12))),
              const SizedBox(height: 16),
              _hsvSlider(ctx, 'Hue', hsv.hue, 0, 360,
                  HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                  (v) => setLocal(() => hsv = hsv.withHue(v))),
              _hsvSlider(ctx, 'Saturation', hsv.saturation, 0, 1, hsv.toColor(),
                  (v) => setLocal(() => hsv = hsv.withSaturation(v))),
              _hsvSlider(ctx, 'Brightness', hsv.value, 0, 1, hsv.toColor(),
                  (v) => setLocal(() => hsv = hsv.withValue(v))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () => Navigator.pop(ctx,
                    isHighlight ? hsv.toColor().withValues(alpha: 0.4) : hsv.toColor()),
                child: const Text('Apply',
                    style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.w700))),
          ],
        );
      }),
    );

    if (picked == null) return;
    if (isHighlight) applyInlineFmt((seg) => seg.highlight = picked);
    else applyInlineFmt((seg) => seg.color = picked);
  }

  Widget _hsvSlider(BuildContext ctx, String label, double value, double min,
      double max, Color activeColor, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        SliderTheme(
          data: SliderTheme.of(ctx).copyWith(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
          child: Slider(value: value, min: min, max: max,
              activeColor: activeColor, inactiveColor: Colors.white12, onChanged: onChanged),
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
  const _ImageOptionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}