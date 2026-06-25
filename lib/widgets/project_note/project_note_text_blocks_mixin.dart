// ─────────────────────────────────────────────────────────────────────────────
// project_note_text_blocks_mixin.dart
//
// UI builders for text-bearing content:
//   buildTopBar()        — compact icon-only top bar with ⋮ overflow menu
//   buildEditor()        — ReorderableListView containing all blocks
//   _buildTitleBlock()   — editable title field (always index 0)
//   _buildBlock()        — routes to the correct block builder
//   _buildTextBlock()    — edit mode (rich TextField) + preview (MarkdownBody)
//   _buildCheckboxBlock()— checkbox + rich text, with auto-total support
//   _buildReadOnlySpan() — inline TextSpan for checkbox preview mode
//   _segsToMarkdown()    — converts segs → Markdown string for preview
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
import 'package:url_launcher/url_launcher.dart';

import 'project_note_state_interface.dart';
import 'project_note_media_blocks_mixin.dart';
import 'project_note_actions_mixin.dart';

mixin ProjectNoteTextBlocksMixin
    on State<ProjectNoteSheet>,
       NoteStateInterface,
       ProjectNoteActionsMixin,
       ProjectNoteMediaBlocksMixin {

  // ─────────────────────────────────────────────────────────────────────────
  // Top bar — icon-only layout with ⋮ overflow menu
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Layout (left → right):
  //   ‹ back  •priority  date/time ... [🗑] [👁/✏] [💾] [⋮]
  //
  // All action buttons are icon-only to fit the overflow menu without
  // wrapping on narrow screens.

  Widget buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
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
                color: Colors.white.withValues(alpha: 0.7),
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
                  color: widget.project.priority.color.withValues(alpha: 0.5),
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
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      Text(
                        _fmtTimeOnly(widget.project.noteUpdatedAt!),
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  )
                : const Text(
                    'New note',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
          ),

          // ── Clear (icon-only, shown only when a note exists) ──
          if (widget.project.hasNote)
            _TopBarIconBtn(
              icon: Icons.delete_outline_rounded,
              color: const Color(0xFFFF3B30),
              tooltip: 'Clear note',
              onTap: clearNote,
            ),

          const SizedBox(width: 2),

          // ── Preview / Edit toggle (icon-only) ─────────────────
          _TopBarIconBtn(
            icon: readOnly ? Icons.edit_outlined : Icons.visibility_outlined,
            color: readOnly ? const Color(0xFF64D2FF) : Colors.white54,
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
          ),

          const SizedBox(width: 2),

          // ── Save (icon-only, glows green when dirty) ──────────
          _TopBarIconBtn(
            icon: Icons.save_rounded,
            color: dirty ? Colors.black : Colors.white30,
            tooltip: 'Save',
            active: dirty,
            activeBackground: const Color(0xFF34C759),
            activeBorder: const Color(0xFF34C759),
            onTap: saveNote,
          ),

          const SizedBox(width: 2),

          // ── ⋮ Overflow menu ───────────────────────────────────
          // Always read the live lock state from AppController.
          // widget.project is the snapshot from when the sheet was
          // pushed and never reflects subsequent lock/unlock changes.
          _NoteOverflowMenu(
            isLocked: AppController.instance.projects
                .where((p) => p.id == widget.project.id)
                .firstOrNull
                ?.isNoteLocked ??
                widget.project.isNoteLocked,
            onLockToggle: _handleLockToggle,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lock / Unlock handler (called from the ⋮ menu)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleLockToggle() async {
    final settings = AppController.instance.settings;

    if (!PinService.isSet(settings.pinHash) || !settings.pinEnabled) {
      _showNoPinDialog();
      return;
    }

    // Always read the LIVE state — widget.project is stale after the sheet opens.
    final liveProject = AppController.instance.projects
        .where((p) => p.id == widget.project.id)
        .firstOrNull;
    if (liveProject == null) return;

    if (liveProject.isNoteLocked) {
      // Unlock: verify PIN first.
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
        AppToast.show(
          context,
          msg: '🔓 Note unlocked',
          backgroundColor: const Color(0xFF1A2E1A),
          textColor: const Color(0xFF4CAF50),
        );
      }
    } else {
      // Lock: no PIN needed — user is already in the app.
      await AppController.instance.updateProjectLockState(
        widget.project.id,
        isNoteLocked: true,
      );

      if (mounted) {
        AppToast.show(
          context,
          msg: '🔒 Note locked',
          backgroundColor: const Color(0xFF1A1A2E),
          textColor: const Color(0xFF64D2FF),
        );
      }
    }

    // Rebuild so the ⋮ menu label and icon refresh immediately.
    if (mounted) setState(() {});
  }

  void _showNoPinDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'No PIN set',
          style: TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: const Text(
          'Go to Settings → Security to set a PIN before locking notes.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('OK', style: TextStyle(color: Color(0xFF4CAF50))),
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
            c.selection = TextSelection.collapsed(offset: c.text.length);
          }
        });
      },
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        onReorder: (oldIndex, newIndex) {
          final adjOld = oldIndex - 1;
          final adjNew = newIndex - 1;
          if (adjOld < 0 || adjNew < 0) return;
          setState(() {
            final block = blocks.removeAt(adjOld);
            blocks.insert(adjNew > adjOld ? adjNew - 1 : adjNew, block);
            dirty = true;
          });
        },
        buildDefaultDragHandles: false,
        itemCount: blocks.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return KeyedSubtree(
              key: const ValueKey('__title__'),
              child: _buildTitleBlock(),
            );
          }
          final b = blocks[i - 1];
          return KeyedSubtree(
            key: ValueKey(b.id),
            child: _buildBlock(b, i - 1),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Title block
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTitleBlock() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: titleCtrl,
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
        onChanged: (_) => setState(() => dirty = true),
      ),
    );
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
    final baseStyle = b.baseStyle;
    final prefix =
        b.orderedList ? '${index + 1}.  ' : b.bulletList ? '•  ' : '';

    // ── Preview mode ─────────────────────────────────────────────────────────
    if (readOnly) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: MarkdownBody(
          data: _segsToMarkdown(b),
          styleSheet: _markdownStyleSheet,
          onTapLink: (_, href, __) async {
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

    // ── Edit mode ─────────────────────────────────────────────────────────────
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
            child: GestureDetector(
              onTapUp: (details) => handleTextTap(b, details),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      ctrl[b.id]?.text.isEmpty == true) {
                    removeBlock(b.id);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: textKeys[b.id],
                  controller: ctrl[b.id],
                  focusNode: fn[b.id],
                  maxLines: null,
                  enableInteractiveSelection: true,
                  selectionControls: MaterialTextSelectionControls(),
                  keyboardType: TextInputType.multiline,
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
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: (activeId == b.id && blocks.length == 1)
                        ? 'Start typing…'
                        : null,
                    hintStyle: const TextStyle(
                        color: Colors.white54, fontSize: 14),
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
    final checkColor =
        b.checked ? Colors.white30 : Colors.white.withValues(alpha: 0.88);
    final checkStyle = TextStyle(
      color: checkColor,
      fontSize: 14,
      height: 1.5,
      decoration:
          b.checked ? TextDecoration.lineThrough : TextDecoration.none,
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
                  dirty = true;
                });
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color:
              b.checked ? const Color(0xFF34C759) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color:
                b.checked ? const Color(0xFF34C759) : Colors.white30,
            width: 1.5,
          ),
        ),
        child: b.checked
            ? const Icon(Icons.check_rounded,
                size: 13, color: Colors.black)
            : null,
      ),
    );

    // ── Preview mode ──────────────────────────────────────────────────────
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
                child: Text.rich(_buildReadOnlySpan(b, checkStyle)),
              ),
            ),
          ],
        ),
      );
    }

    // ── Edit mode ─────────────────────────────────────────────────────────
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
                      event.logicalKey == LogicalKeyboardKey.backspace &&
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
                  key: textKeys[b.id],
                  controller: ctrl[b.id],
                  focusNode: fn[b.id],
                  maxLines: null,
                  enableInteractiveSelection: true,
                  selectionControls: MaterialTextSelectionControls(),
                  keyboardType: TextInputType.multiline,
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
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'To-do item',
                    hintStyle: TextStyle(
                        color: Colors.white12, fontSize: 14),
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
    final buf = StringBuffer();
    for (final s in segs) {
      var text = s.text;
      if (s.bold) text = '**$text**';
      if (s.italic) text = '_${text}_';
      if (s.strikethrough) text = '~~$text~~';
      if (s.url != null && s.url!.isNotEmpty) text = '[$text](${s.url})';
      buf.write(text);
    }
    return buf.toString();
  }

  TextSpan _buildReadOnlySpan(NoteBlock b, TextStyle baseStyle) {
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
            color: isLink ? const Color(0xFF64D2FF) : s.color,
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

  static final _markdownStyleSheet = MarkdownStyleSheet(
    p:      const TextStyle(
        color: Colors.white70, fontSize: 14, height: 1.5),
    h1:     const TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.w700),
    h2:     const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700),
    h3:     const TextStyle(
        color: Color(0xFFFFD60A),
        fontSize: 18,
        fontWeight: FontWeight.w600),
    h4:     const TextStyle(
        color: Color(0xFF64D2FF),
        fontSize: 16,
        fontWeight: FontWeight.w600),
    strong: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.w700),
    em:     const TextStyle(
        color: Colors.white70, fontStyle: FontStyle.italic),
    code:   const TextStyle(
        color: Color(0xFF34C759),
        fontFamily: 'monospace',
        fontSize: 13),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white10),
    ),
    tableBody: const TextStyle(color: Colors.white70, fontSize: 13),
    tableHead: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13),
    tableBorder: TableBorder.all(color: Colors.white12, width: 1),
    blockquoteDecoration: const BoxDecoration(
      border:
          Border(left: BorderSide(color: Color(0xFF64D2FF), width: 3)),
      color: Color(0xFF0A1A2E),
    ),
    blockquote: const TextStyle(color: Colors.white54, fontSize: 14),
    listBullet: const TextStyle(color: Colors.white38),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.white12)),
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
//
// A small square icon button used in the top bar. Supports an optional
// active state that changes the background and border colour.
// ─────────────────────────────────────────────────────────────────────────────

class _TopBarIconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
  final VoidCallback onTap;
  final bool         active;
  final Color?       activeBackground;
  final Color?       activeBorder;

  const _TopBarIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.active          = false,
    this.activeBackground,
    this.activeBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active
                ? (activeBackground ?? const Color(0xFF1C1C1C))
                : const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? (activeBorder?.withValues(alpha: 0.5) ?? Colors.white10)
                  : Colors.white10,
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
//
// Three-dot (⋮) PopupMenuButton. Currently exposes Lock / Unlock.
// Extend [_NoteMenuAction] to add future items (share, export, etc.)
// without touching the call site.
// ─────────────────────────────────────────────────────────────────────────────

enum _NoteMenuAction { lock }

class _NoteOverflowMenu extends StatelessWidget {
  final bool         isLocked;
  final VoidCallback onLockToggle;

  const _NoteOverflowMenu({
    required this.isLocked,
    required this.onLockToggle,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NoteMenuAction>(
      onSelected: (action) {
        switch (action) {
          case _NoteMenuAction.lock:
            onLockToggle();
        }
      },
      // Render as a plain icon — no ink splash, matches the top-bar style.
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Icon(
            Icons.more_vert_rounded,
            size: 18,
            color: Colors.white54,
          ),
        ),
      ),
      // Popup card styling.
      color: const Color(0xFF1E1E1E),
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white10),
      ),
      itemBuilder: (_) => [
        PopupMenuItem<_NoteMenuAction>(
          value: _NoteMenuAction.lock,
          child: Row(
            children: [
              // Lock icon changes to reflect the current state.
              Icon(
                isLocked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                size: 18,
                color: isLocked
                    ? const Color(0xFFFF9F0A)  // amber = currently locked
                    : const Color(0xFF4CAF50), // green  = currently unlocked
              ),
              const SizedBox(width: 12),
              Text(
                isLocked ? 'Unlock note' : 'Lock note',
                style: TextStyle(
                  color: isLocked
                      ? const Color(0xFFFF9F0A)
                      : Colors.white,
                  fontSize: 14,
                ),
              ),
              // Small badge shown when note is currently locked.
              if (isLocked) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color:
                          const Color(0xFFFF9F0A).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'LOCKED',
                    style: TextStyle(
                      color: Color(0xFFFF9F0A),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Divider + placeholder for future actions ────────────
        // Uncomment and extend when more options are added:
        // const PopupMenuDivider(height: 1),
        // PopupMenuItem<_NoteMenuAction>(
        //   value: _NoteMenuAction.export,
        //   child: Row(children: [
        //     const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white54),
        //     const SizedBox(width: 12),
        //     const Text('Export note', style: TextStyle(color: Colors.white, fontSize: 14)),
        //   ]),
        // ),
      ],
    );
  }
}