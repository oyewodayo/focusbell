import 'package:flutter/material.dart';
import 'package:focusbell/models/note_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NoteRichController
//
// Design: segs is the ONE source of truth for both text content and styling.
// The base TextEditingController.text is kept equal to segs.join() at all
// times via rebuildText().  The TextField's onChanged callback is the ONLY
// place where we reconcile a user edit back into segs; we never override
// set value because Flutter calls that for cursor moves, selection, composing
// etc. — not just text changes.
// ─────────────────────────────────────────────────────────────────────────────

class NoteRichController extends TextEditingController {
  List<NoteSeg> segs;

  NoteRichController({List<NoteSeg>? segs}) : segs = segs ?? [] {
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

    NoteSeg inherit = segs.isNotEmpty ? segs.last : NoteSeg(text: '');
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
      segs = [NoteSeg(text: newText)];
    }

    rebuildText();
  }

  // ── Pushes the current segs plain-text back into the base controller ──────
  void rebuildText() {
    final plain = segs.map((s) => s.text).join();
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

  static List<NoteSeg> _del(List<NoteSeg> segs, int from, int to) {
    final out = <NoteSeg>[];
    int pos = 0;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (end <= from || pos >= to) {
        out.add(s);
      } else {
        final bLen = (from - pos).clamp(0, s.text.length);
        final aStart = (to - pos).clamp(0, s.text.length);
        if (bLen > 0) out.add(s.copyWith(text: s.text.substring(0, bLen)));
        if (aStart < s.text.length) {
          out.add(s.copyWith(text: s.text.substring(aStart)));
        }
      }
      pos = end;
    }
    return out;
  }

  static List<NoteSeg> _ins(
      List<NoteSeg> segs, int at, String text, NoteSeg style) {
    if (segs.isEmpty) return [style.copyWith(text: text)];
    final out = <NoteSeg>[];
    int pos = 0;
    bool done = false;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (!done && at >= pos && at <= end) {
        final split = at - pos;
        if (split > 0) out.add(s.copyWith(text: s.text.substring(0, split)));
        final newSeg = s.sameStyle(style)
            ? s.copyWith(text: text)
            : style.copyWith(text: text);
        out.add(newSeg);
        if (split < s.text.length) {
          out.add(s.copyWith(text: s.text.substring(split)));
        }
        done = true;
      } else {
        out.add(s);
      }
      pos = end;
    }
    if (!done) out.add(style.copyWith(text: text));
    return out;
  }

  static List<NoteSeg> _merge(List<NoteSeg> segs) {
    final out = <NoteSeg>[];
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

  void applyToRange(int start, int end, void Function(NoteSeg s) fn) {
    if (start >= end) return;
    segs = _splitAt(_splitAt(segs, start), end);
    int pos = 0;
    for (final s in segs) {
      final sEnd = pos + s.text.length;
      if (pos >= start && sEnd <= end) fn(s);
      pos = sEnd;
    }
    segs = _merge(segs);
    if (segs.isEmpty) segs = [NoteSeg(text: '')];
  }

  static List<NoteSeg> _splitAt(List<NoteSeg> segs, int at) {
    final out = <NoteSeg>[];
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

  // ── Public helpers for inserting segments ────────────────────

  static List<NoteSeg> insSegs(
          List<NoteSeg> segs, int at, String text, NoteSeg style) =>
      _ins(segs, at, text, style);

  static List<NoteSeg> mergeSegs(List<NoteSeg> segs) => _merge(segs);

  /// Returns the URL of the segment at character [offset], or null.
  String? urlAt(int offset) {
    int pos = 0;
    for (final s in segs) {
      final end = pos + s.text.length;
      if (offset >= pos && offset < end) return s.url;
      pos = end;
    }
    return null;
  }

  // ── Formatting state at cursor / selection ────────────────────

  Map<String, dynamic> styleAt(TextSelection sel) {
    final start = sel.isCollapsed ? sel.baseOffset : sel.start;
    final end = sel.isCollapsed ? sel.baseOffset + 1 : sel.end;
    bool bold = false,
        italic = false,
        under = false,
        strike = false;
    Color? color, highlight;
    String? url;
    int pos = 0;
    for (final s in segs) {
      final sEnd = pos + s.text.length;
      if (sEnd > start && pos < end) {
        bold = bold || s.bold;
        italic = italic || s.italic;
        under = under || s.underline;
        strike = strike || s.strikethrough;
        color ??= s.color;
        highlight ??= s.highlight;
        url ??= s.url;
      }
      pos = sEnd;
    }
    return {
      'bold': bold,
      'italic': italic,
      'underline': under,
      'strikethrough': strike,
      'color': color,
      'highlight': highlight,
      'url': url,
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
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}