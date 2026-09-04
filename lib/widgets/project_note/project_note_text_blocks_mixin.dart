// ─────────────────────────────────────────────────────────────────────────────
// project_note_text_blocks_mixin.dart — FULL REPLACEMENT
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:focusbell/models/note_models.dart';
import 'package:focusbell/services/app_controller.dart';
import 'package:focusbell/services/pin_service.dart';
import 'package:focusbell/utils/app_toast.dart';
import 'package:focusbell/widgets/pin_entry_sheet.dart';
import 'package:focusbell/widgets/project_note_sheet.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import 'project_note_state_interface.dart';
import 'project_note_media_blocks_mixin.dart';
import 'project_note_actions_mixin.dart';

mixin ProjectNoteTextBlocksMixin
    on State<ProjectNoteSheet>,
       NoteStateInterface,
       ProjectNoteActionsMixin,
       ProjectNoteMediaBlocksMixin {

  // ─────────────────────────────────────────────────────────────────────────
  // Top bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget buildTopBar() {
    final fb = Theme.of(context).fb;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: fb.border)),
      ),
      child: Row(
        children: [
          // ── Back ──────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              if (dirty) await saveNote();
              if (mounted) Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: fb.onSurfaceDim,
                size: 20,
              ),
            ),
          ),

          // ── Priority dot ──────────────────────────────────────
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(left: 2, right: 10),
            decoration: BoxDecoration(
              color: widget.project.priority.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.project.priority.color
                      .withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
              ],
            ),
          ),

          // ── Date / time ───────────────────────────────────────
          Expanded(
            child: widget.project.noteUpdatedAt != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmtDateOnly(widget.project.noteUpdatedAt!),
                        style: TextStyle(
                            color: fb.onSurfaceDim, fontSize: 12),
                      ),
                      Text(
                        _fmtTimeOnly(widget.project.noteUpdatedAt!),
                        style: TextStyle(
                            color: fb.onSurfaceFaint, fontSize: 11),
                      ),
                    ],
                  )
                : Text(
                    'New note',
                    style: TextStyle(
                        color: fb.onSurfaceFaint, fontSize: 12),
                  ),
          ),

          // ── Clear ─────────────────────────────────────────────
          if (widget.project.hasNote)
            _TopBarIconBtn(
              icon: Icons.delete_outline_rounded,
              color: fb.danger,
              tooltip: 'Clear note',
              onTap: clearNote,
              fb: fb,
            ),

          const SizedBox(width: 2),

          // ── Preview / Edit toggle ─────────────────────────────
          _TopBarIconBtn(
            icon: readOnly
                ? Icons.edit_outlined
                : Icons.visibility_outlined,
            color: readOnly
                ? const Color(0xFF64D2FF)
                : fb.onSurfaceDim,
            tooltip: readOnly ? 'Edit' : 'Preview',
            active: readOnly,
            activeBackground: const Color(0xFF0A1A2E),
            activeBorder: const Color(0xFF64D2FF),
            onTap: () {
              setState(() {
                readOnly = !readOnly;
                if (readOnly) {
                  FocusScope.of(context).unfocus();
                  showFormatBar = false;
                }
              });
            },
            fb: fb,
          ),

          const SizedBox(width: 2),

          // ── Save ──────────────────────────────────────────────
          _TopBarIconBtn(
            icon: Icons.save_rounded,
            color: dirty ? Colors.black : fb.onSurfaceFaint,
            tooltip: 'Save',
            active: dirty,
            activeBackground: const Color(0xFF34C759),
            activeBorder: const Color(0xFF34C759),
            onTap: saveNote,
            fb: fb,
          ),

          const SizedBox(width: 2),

          // ── ⋮ Overflow menu ───────────────────────────────────
          _NoteOverflowMenu(
            isLocked: AppController.instance.projects
                    .where((p) => p.id == widget.project.id)
                    .firstOrNull
                    ?.isNoteLocked ??
                widget.project.isNoteLocked,
            hasReminder: noteReminder != null,
            onLockToggle: _handleLockToggle,
            onSetReminder: setNoteReminder,
            fb: fb,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lock / Unlock handler
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleLockToggle() async {
    final settings = AppController.instance.settings;

    if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
      _showNoPinDialog();
      return;
    }

    final liveProject = AppController.instance.projects
        .where((p) => p.id == widget.project.id)
        .firstOrNull;
    if (liveProject == null) return;

    if (liveProject.isNoteLocked) {
      final ok = await showPinEntry<bool>(
        context,
        mode:       PinEntryMode.verify,
        storedHash: settings.pinHash,
        title:      'Enter PIN to unlock note',
      );
      if (ok != true || !mounted) return;
      await AppController.instance.updateProjectLockState(
        widget.project.id,
        isNoteLocked: false,
      );
      if (mounted) {
        AppToast.success(context, '🔓 Note unlocked');
      }
    } else {
      await AppController.instance.updateProjectLockState(
        widget.project.id,
        isNoteLocked: true,
      );
      if (mounted) {
        AppToast.show(context,
            msg: '🔒 Note locked',
            backgroundColor: const Color(0xFF1A1A2E),
            textColor: const Color(0xFF64D2FF));
      }
    }
    if (mounted) setState(() {});
  }

  void _showNoPinDialog() {
    final fb = Theme.of(context).fb;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: fb.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('No PIN set',
            style: TextStyle(color: fb.onSurface, fontSize: 17)),
        content: Text(
          'Go to Settings → Security to set a PIN before locking notes.',
          style: TextStyle(color: fb.onSurfaceDim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: TextStyle(color: fb.primary)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Editor scaffold
  // ─────────────────────────────────────────────────────────────────────────

  Widget buildEditor() {
    return GestureDetector(
      onTap: () {
        ensureTrailingTextBlock();
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final last = blocks.lastWhere(
            (b) =>
                b.type == NoteBlockType.text ||
                b.type == NoteBlockType.checkbox,
            orElse: () => blocks.last,
          );
          fn[last.id]?.requestFocus();
          final c = ctrl[last.id];
          if (c != null) {
            c.selection =
                TextSelection.collapsed(offset: c.text.length);
          }
        });
      },
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        onReorder: (oldIndex, newIndex) {
          final offset = noteReminder != null ? 2 : 1;
          final adjOld = oldIndex - offset;
          final adjNew = newIndex - offset;
          if (adjOld < 0 || adjNew < 0) return;
          setState(() {
            final block = blocks.removeAt(adjOld);
            blocks.insert(
                adjNew > adjOld ? adjNew - 1 : adjNew, block);
            dirty = true;
          });
        },
        buildDefaultDragHandles: false,
        itemCount:
            blocks.length + 1 + (noteReminder != null ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return KeyedSubtree(
              key: const ValueKey('__title__'),
              child: _buildTitleBlock(),
            );
          }
          if (noteReminder != null && i == 1) {
            return KeyedSubtree(
              key: const ValueKey('__reminder__'),
              child: _buildReminderChip(),
            );
          }
          final offset = noteReminder != null ? 2 : 1;
          final b = blocks[i - offset];
          return KeyedSubtree(
            key: ValueKey(b.id),
            child: _buildBlock(b, i - offset),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Title block
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTitleBlock() {
    final fb = Theme.of(context).fb;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: titleCtrl,
        style: TextStyle(
          color:       fb.onSurface,
          fontSize:    26,
          fontWeight:  FontWeight.w700,
          letterSpacing: -0.5,
          height:      1.3,
        ),
        decoration: InputDecoration(
          hintText: 'Title',
          hintStyle: TextStyle(
            color:      fb.onSurfaceFaint,
            fontSize:   26,
            fontWeight: FontWeight.w700,
          ),
          border:         InputBorder.none,
          enabledBorder:  InputBorder.none,
          focusedBorder:  InputBorder.none,
          isDense:        true,
          contentPadding: EdgeInsets.zero,
        ),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        onChanged: (_) => setState(() => dirty = true),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reminder chip
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReminderChip() {
    if (noteReminder == null) return const SizedBox.shrink();
    final fb      = Theme.of(context).fb;
    final isPast  = noteReminder!.isBefore(DateTime.now());
    final label   = _fmtReminderLabel(noteReminder!);
    const amber   = Color(0xFFFF9F0A);
    final chipColor = isPast ? fb.onSurfaceFaint : amber;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: setNoteReminder,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: chipColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_rounded,
                      size: 13, color: chipColor),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                        color:      chipColor,
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: clearNoteReminder,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fb.onSurface.withValues(alpha: 0.06),
              ),
              child: Center(
                child: Icon(Icons.close_rounded,
                    size: 13, color: fb.onSurfaceFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtReminderLabel(DateTime dt) {
    final now      = DateTime.now();
    final local    = dt.toLocal();
    final today    = DateTime(now.year, now.month, now.day);
    final dDay     = DateTime(local.year, local.month, local.day);
    final timePart = DateFormat('hh:mm a').format(local);
    if (local.isBefore(now)) {
      return 'Passed · ${DateFormat('MM/dd').format(local)}';
    }
    if (dDay == today) return 'Today $timePart';
    if (dDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow $timePart';
    }
    return '${DateFormat('MM/dd').format(local)} $timePart';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Block router
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBlock(NoteBlock b, int index) => switch (b.type) {
        NoteBlockType.text     => _buildTextBlock(b, index),
        NoteBlockType.checkbox => _buildCheckboxBlock(b, index),
        NoteBlockType.image    => buildImageBlock(b),
        NoteBlockType.audio    => buildAudioBlock(b),
        NoteBlockType.pdf      => buildPdfBlock(b),
      };

  // ─────────────────────────────────────────────────────────────────────────
  // Text block
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTextBlock(NoteBlock b, int index) {
    final fb = Theme.of(context).fb;
  final baseStyle = b.baseStyle.copyWith(color: fb.onSurface);
  final prefix = b.orderedList ? '${index + 1}.  ' : b.bulletList ? '•  ' : '';

  if (readOnly) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prefix.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text(prefix, style: baseStyle.copyWith(color: fb.onSurfaceFaint)),
            ),
          Expanded(
            child: GestureDetector(
              onTapUp: (d) => handleTextTap(b, d),
              child: Text.rich(_buildReadOnlySpan(b, baseStyle, fb)),
            ),
          ),
        ],
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
              child: Text(prefix,
                  style:
                      baseStyle.copyWith(color: fb.onSurfaceFaint)),
            ),
          Expanded(
            child: GestureDetector(
              onTapUp: (details) => handleTextTap(b, details),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey ==
                          LogicalKeyboardKey.backspace &&
                      ctrl[b.id]?.text.isEmpty == true) {
                    removeBlock(b.id);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key:            textKeys[b.id],
                  controller:     ctrl[b.id],
                  focusNode:      fn[b.id],
                  maxLines:       null,
                  enableInteractiveSelection: true,
                  selectionControls:
                      MaterialTextSelectionControls(),
                  keyboardType:   TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlign: switch (b.align) {
                    NoteAlign.left   => TextAlign.left,
                    NoteAlign.center => TextAlign.center,
                    NoteAlign.right  => TextAlign.right,
                  },
                  style: baseStyle,
                  onChanged: (t) {
                    final c = ctrl[b.id];
                    if (c == null) return;
                    c.handleTextChange(t);
                    b.segs = List.from(c.segs);
                    if (!dirty) setState(() => dirty = true);
                  },
                  onSubmitted: (_) => addTextBlockAfter(b.id),
                  decoration: InputDecoration(
                    border:         InputBorder.none,
                    enabledBorder:  InputBorder.none,
                    focusedBorder:  InputBorder.none,
                    isDense:        true,
                    contentPadding: EdgeInsets.zero,
                    hintText: (activeId == b.id &&
                            blocks.length == 1)
                        ? 'Start typing…'
                        : null,
                    hintStyle: TextStyle(
                        color: fb.onSurfaceFaint, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Checkbox block
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCheckboxBlock(NoteBlock b, int index) {
    final fb = Theme.of(context).fb;

    final checkColor = b.checked
        ? fb.onSurfaceFaint
        : fb.onSurface;
    final checkStyle = TextStyle(
      color:      checkColor,
      fontSize:   14,
      height:     1.5,
      decoration: b.checked
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      decorationColor: fb.onSurfaceFaint,
    );

    final checkBox = GestureDetector(
      onTap: readOnly
          ? null
          : () {
              final isTotal = b.segs.isNotEmpty &&
                  b.segs.first.text
                      .trimLeft()
                      .startsWith('Checkbox Total:');
              if (isTotal) {
                suppressTotalRecompute = true;
                removeBlock(b.id);
                setState(() => dirty = true);
              } else {
                setState(() {
                  b.checked = !b.checked;
                  dirty     = true;
                });
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width:  20,
        height: 20,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: b.checked
              ? const Color(0xFF34C759)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: b.checked
                ? const Color(0xFF34C759)
                : fb.onSurfaceFaint,
            width: 1.5,
          ),
        ),
        child: b.checked
            ? const Icon(Icons.check_rounded,
                size: 13, color: Colors.black)
            : null,
      ),
    );

    if (readOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            checkBox,
            Expanded(
              child: GestureDetector(
                onTapUp: (d) => handleTextTap(b, d),
                child: Text.rich(
                    _buildReadOnlySpan(b, checkStyle, fb)),
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
              onTapUp: (d) => handleTextTap(b, d),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey ==
                          LogicalKeyboardKey.backspace &&
                      ctrl[b.id]?.text.isEmpty == true) {
                    final isTotal = b.segs.isNotEmpty &&
                        b.segs.first.text
                            .trimLeft()
                            .startsWith('Checkbox Total:');
                    if (!isTotal) removeBlock(b.id);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key:            textKeys[b.id],
                  controller:     ctrl[b.id],
                  focusNode:      fn[b.id],
                  maxLines:       null,
                  enableInteractiveSelection: true,
                  selectionControls:
                      MaterialTextSelectionControls(),
                  keyboardType:   TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: (t) {
                    final c = ctrl[b.id];
                    if (c == null) return;
                    c.handleTextChange(t);
                    b.segs = List.from(c.segs);
                    if (!dirty) setState(() => dirty = true);
                    totalDebounce?.cancel();
                    totalDebounce = Timer(
                      const Duration(milliseconds: 400),
                      recomputeCheckboxTotal,
                    );
                  },
                  onSubmitted: (_) => addTextBlockAfter(b.id),
                  style: checkStyle,
                  decoration: InputDecoration(
                    border:         InputBorder.none,
                    enabledBorder:  InputBorder.none,
                    focusedBorder:  InputBorder.none,
                    isDense:        true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'To-do item',
                    hintStyle: TextStyle(
                        color: fb.onSurfaceFaint, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Read-only helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _segsToMarkdown(NoteBlock b) {
    final segs = ctrl[b.id]?.segs ?? b.segs;
    final buf  = StringBuffer();
    for (final s in segs) {
      var text = s.text;
      if (s.bold) text = '**$text**';
      if (s.italic) text = '_${text}_';
      if (s.strikethrough) text = '~~$text~~';
      if (s.url != null && s.url!.isNotEmpty) {
        text = '[$text](${s.url})';
      }
      buf.write(text);
    }
    return buf.toString();
  }

  TextSpan _buildReadOnlySpan(
      NoteBlock b, TextStyle baseStyle, FocusBellColors fb) {
    final segs = ctrl[b.id]?.segs ?? b.segs;
    return TextSpan(
      style: baseStyle,
      children: segs.map((s) {
        final isLink = s.url != null && s.url!.isNotEmpty;
        return TextSpan(
          text: s.text,
          style: TextStyle(
            fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle:
                s.italic ? FontStyle.italic : FontStyle.normal,
            // Respect explicit seg color; fall back to theme onSurface
            color: isLink
                ? const Color(0xFF64D2FF)
                : (s.color ?? fb.onSurface),
            backgroundColor: s.highlight,
            decoration: TextDecoration.combine([
              if (s.underline || isLink) TextDecoration.underline,
              if (s.strikethrough) TextDecoration.lineThrough,
            ]),
            decorationColor:
                isLink ? const Color(0xFF64D2FF) : null,
          ),
          recognizer: isLink
              ? (TapGestureRecognizer()
                ..onTap = () async {
                    final urlStr = s.url!.startsWith('http')
                        ? s.url!
                        : 'https://${s.url}';
                    final uri = Uri.tryParse(urlStr);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  })
              : null,
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Markdown stylesheet — now theme-aware, built per-render
  // ─────────────────────────────────────────────────────────────────────────

  MarkdownStyleSheet _markdownStyleSheet(FocusBellColors fb) =>
      MarkdownStyleSheet(
        p: TextStyle(
            color: fb.onSurface, fontSize: 14, height: 1.5),
        h1: TextStyle(
            color:      fb.onSurface,
            fontSize:   26,
            fontWeight: FontWeight.w700),
        h2: TextStyle(
            color:      fb.onSurface,
            fontSize:   22,
            fontWeight: FontWeight.w700),
        h3: const TextStyle(
            color:      Color(0xFFFFD60A),
            fontSize:   18,
            fontWeight: FontWeight.w600),
        h4: const TextStyle(
            color:      Color(0xFF64D2FF),
            fontSize:   16,
            fontWeight: FontWeight.w600),
        strong: TextStyle(
            color:      fb.onSurface,
            fontWeight: FontWeight.w700),
        em: TextStyle(
            color:      fb.onSurfaceDim,
            fontStyle:  FontStyle.italic),
        code: const TextStyle(
            color:      Color(0xFF34C759),
            fontFamily: 'monospace',
            fontSize:   13),
        codeblockDecoration: BoxDecoration(
          color:        fb.surfaceVar,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: fb.border),
        ),
        tableBody: TextStyle(
            color: fb.onSurfaceDim, fontSize: 13),
        tableHead: TextStyle(
            color:      fb.onSurface,
            fontWeight: FontWeight.w700,
            fontSize:   13),
        tableBorder: TableBorder.all(color: fb.border, width: 1),
        blockquoteDecoration: BoxDecoration(
          border: const Border(
              left: BorderSide(
                  color: Color(0xFF64D2FF), width: 3)),
          color: fb.isDark
              ? const Color(0xFF0A1A2E)
              : const Color(0xFFE8F4FF),
        ),
        blockquote:
            TextStyle(color: fb.onSurfaceDim, fontSize: 14),
        listBullet: TextStyle(color: fb.onSurfaceFaint),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: fb.border)),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Date / time formatters
  // ─────────────────────────────────────────────────────────────────────────

  String _fmtDateOnly(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  String _fmtTimeOnly(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '${h.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')} '
        '${l.hour >= 12 ? 'PM' : 'AM'}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TopBarIconBtn
// ─────────────────────────────────────────────────────────────────────────────

class _TopBarIconBtn extends StatelessWidget {
  final IconData         icon;
  final Color            color;
  final String           tooltip;
  final VoidCallback     onTap;
  final bool             active;
  final Color?           activeBackground;
  final Color?           activeBorder;
  final FocusBellColors  fb;

  const _TopBarIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    required this.fb,
    this.active          = false,
    this.activeBackground,
    this.activeBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:    tooltip,
      preferBelow: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width:  34,
          height: 34,
          decoration: BoxDecoration(
            color: active
                ? (activeBackground ?? fb.surfaceVar)
                : fb.surfaceVar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? (activeBorder?.withValues(alpha: 0.5) ??
                      fb.border)
                  : fb.border,
            ),
          ),
          child: Center(
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NoteOverflowMenu
// ─────────────────────────────────────────────────────────────────────────────

enum _NoteMenuAction { lock, reminder }

class _NoteOverflowMenu extends StatelessWidget {
  final bool            isLocked;
  final bool            hasReminder;
  final VoidCallback    onLockToggle;
  final VoidCallback    onSetReminder;
  final FocusBellColors fb;

  const _NoteOverflowMenu({
    required this.isLocked,
    required this.hasReminder,
    required this.onLockToggle,
    required this.onSetReminder,
    required this.fb,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NoteMenuAction>(
      onSelected: (action) {
        switch (action) {
          case _NoteMenuAction.lock:
            onLockToggle();
          case _NoteMenuAction.reminder:
            onSetReminder();
        }
      },
      color:       fb.surfaceVar,
      elevation:   8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:         BorderSide(color: fb.border),
      ),
      child: Container(
        width:  34,
        height: 34,
        decoration: BoxDecoration(
          color:        fb.surfaceVar,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: fb.border),
        ),
        child: Center(
          child: Icon(Icons.more_vert_rounded,
              size: 18, color: fb.onSurfaceDim),
        ),
      ),
      itemBuilder: (_) => [
        // ── Lock / Unlock ──────────────────────────────────
        PopupMenuItem<_NoteMenuAction>(
          value: _NoteMenuAction.lock,
          child: Row(children: [
            Icon(
              isLocked
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              size:  18,
              color: isLocked
                  ? const Color(0xFFFF9F0A)
                  : fb.success,
            ),
            const SizedBox(width: 12),
            Text(
              isLocked ? 'Unlock note' : 'Lock note',
              style: TextStyle(
                color: isLocked
                    ? const Color(0xFFFF9F0A)
                    : fb.onSurface,
                fontSize: 14,
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFFFF9F0A)
                          .withValues(alpha: 0.4)),
                ),
                child: const Text('LOCKED',
                    style: TextStyle(
                      color:       Color(0xFFFF9F0A),
                      fontSize:    9,
                      fontWeight:  FontWeight.w800,
                      letterSpacing: 0.5,
                    )),
              ),
            ],
          ]),
        ),

        const PopupMenuDivider(height: 1),

        // ── Set / Edit reminder ────────────────────────────
        PopupMenuItem<_NoteMenuAction>(
          value: _NoteMenuAction.reminder,
          child: Row(children: [
            Icon(
              hasReminder
                  ? Icons.alarm_on_rounded
                  : Icons.alarm_add_rounded,
              size:  18,
              color: hasReminder
                  ? const Color(0xFFFF9F0A)
                  : fb.onSurfaceDim,
            ),
            const SizedBox(width: 12),
            Text(
              hasReminder ? 'Edit reminder' : 'Set reminder',
              style: TextStyle(
                color: hasReminder
                    ? const Color(0xFFFF9F0A)
                    : fb.onSurface,
                fontSize: 14,
              ),
            ),
            if (hasReminder) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFFFF9F0A)
                          .withValues(alpha: 0.35)),
                ),
                child: const Text('SET',
                    style: TextStyle(
                      color:       Color(0xFFFF9F0A),
                      fontSize:    9,
                      fontWeight:  FontWeight.w800,
                      letterSpacing: 0.5,
                    )),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}