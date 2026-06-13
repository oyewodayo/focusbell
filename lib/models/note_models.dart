import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unique-ID generator
// ─────────────────────────────────────────────────────────────────────────────

int _c = 0;
String noteUid() => '${DateTime.now().millisecondsSinceEpoch}_${_c++}';

// ─────────────────────────────────────────────────────────────────────────────
// Inline segment — one contiguous run of text with uniform formatting
// ─────────────────────────────────────────────────────────────────────────────

class NoteSeg {
  String text;
  bool bold;
  bool italic;
  bool underline;
  bool strikethrough;
  Color? color;
  Color? highlight;
  String? url;

  NoteSeg({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
    this.highlight,
    this.url,
  });

  bool sameStyle(NoteSeg o) =>
      bold == o.bold &&
      italic == o.italic &&
      underline == o.underline &&
      strikethrough == o.strikethrough &&
      color == o.color &&
      highlight == o.highlight &&
      url == o.url;

  NoteSeg copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    Color? color,
    bool clearColor = false,
    Color? highlight,
    bool clearHighlight = false,
    String? url,
    bool clearUrl = false,
  }) =>
      NoteSeg(
        text: text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        color: clearColor ? null : (color ?? this.color),
        highlight: clearHighlight ? null : (highlight ?? this.highlight),
        url: clearUrl ? null : (url ?? this.url),
      );

  Map<String, dynamic> toJson() => {
        'tx': text,
        if (bold) 'b': true,
        if (italic) 'i': true,
        if (underline) 'u': true,
        if (strikethrough) 's': true,
        if (color != null) 'c': color!.value,
        if (highlight != null) 'hl': highlight!.value,
        if (url != null) 'url': url,
      };

  factory NoteSeg.fromJson(Map<String, dynamic> j) => NoteSeg(
        text: j['tx'] as String? ?? '',
        bold: j['b'] as bool? ?? false,
        italic: j['i'] as bool? ?? false,
        underline: j['u'] as bool? ?? false,
        strikethrough: j['s'] as bool? ?? false,
        color: j['c'] != null ? Color(j['c'] as int) : null,
        highlight: j['hl'] != null ? Color(j['hl'] as int) : null,
        url: j['url'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Block types & alignment
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
  List<NoteSeg> segs;
  NoteAlign align;
  bool orderedList;
  bool bulletList;
  bool isH1, isH2, isH3, isH4;

  // image
  String? imagePath;

  // audio
  String? audioPath;
  Duration audioDuration;

  // pdf
  String? pdfPath;
  String? pdfName;
  int pdfSizeBytes;
  int pdfPageCount;

  // checkbox
  bool checked;

  NoteBlock({
    required this.id,
    this.type = NoteBlockType.text,
    List<NoteSeg>? segs,
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
    if (isH1) return 28;
    if (isH2) return 24;
    if (isH3) return 20;
    if (isH4) return 17;
    return 16;
  }

  TextStyle get baseStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.80),
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
        'tx': plainText, // legacy plain-text field for backward compat
      };

  factory NoteBlock.fromJson(Map<String, dynamic> j) {
    final segsRaw = j['segs'] as List<dynamic>?;

    List<NoteSeg> segs;
    if (segsRaw != null && segsRaw.isNotEmpty) {
      segs = segsRaw
          .map((e) => NoteSeg.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Migrate from old NoteSpan format.
      final spansRaw = j['sp'] as List<dynamic>?;
      if (spansRaw != null && spansRaw.isNotEmpty) {
        segs = spansRaw.map((e) {
          final m = e as Map<String, dynamic>;
          return NoteSeg(
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
        segs = plain.isNotEmpty ? [NoteSeg(text: plain)] : [];
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
      pdfPath: j['pdf'] as String?,
      pdfName: j['pdfn'] as String?,
      pdfSizeBytes: j['pdfsz'] as int? ?? 0,
      pdfPageCount: j['pdfpg'] as int? ?? 0,
    );
  }

  static String encodeList(List<NoteBlock> blocks) =>
      jsonEncode(blocks.map((b) => b.toJson()).toList());

  static List<NoteBlock> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [NoteBlock(id: noteUid())];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [NoteBlock(id: noteUid())];
    }
  }
}