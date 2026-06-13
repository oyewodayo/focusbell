import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _TChip — heading-style chip (H1 / H2 / H3 / H4 / body)
// ─────────────────────────────────────────────────────────────────────────────

class NoteTChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const NoteTChip(this.label, this.selected, this.accent, this.onTap,
      {super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? accent.withValues(alpha: 0.5) : Colors.white12),
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

// ─────────────────────────────────────────────────────────────────────────────
// NoteFBtn — inline format button (B / I / U / S)
// ─────────────────────────────────────────────────────────────────────────────

class NoteFBtn extends StatelessWidget {
  final String label;
  final bool bold, italic, under, strike, active;
  final VoidCallback onTap;
  const NoteFBtn(
    this.label, {
    super.key,
    this.bold = false,
    this.italic = false,
    this.under = false,
    this.strike = false,
    required this.active,
    required this.onTap,
  });

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

// ─────────────────────────────────────────────────────────────────────────────
// NoteIBtn — icon button for format bar
// ─────────────────────────────────────────────────────────────────────────────

class NoteIBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const NoteIBtn(this.icon, this.active, this.onTap, {super.key});

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

// ─────────────────────────────────────────────────────────────────────────────
// NoteColorDot — colour swatch for text / highlight palette
// ─────────────────────────────────────────────────────────────────────────────

class NoteColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;
  final Color? customPreview;

  const NoteColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
    this.customPreview = null,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCustom
              ? (customPreview ?? Colors.transparent)
              : (color ?? Colors.transparent),
          border: Border.all(
            color: selected
                ? Colors.white70
                : (color == null && !isCustom)
                    ? Colors.white30
                    : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        child: isCustom
            ? Icon(
                Icons.colorize_rounded,
                size: 14,
                color: customPreview != null ? Colors.white : Colors.white38,
              )
            : (color == null
                ? const Icon(Icons.block_rounded,
                    size: 14, color: Colors.white30)
                : (selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.black)
                    : null)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NoteToolbarSep — vertical separator between format-bar groups
// ─────────────────────────────────────────────────────────────────────────────

class NoteToolbarSep extends StatelessWidget {
  const NoteToolbarSep({super.key});

  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white12);
}

// ─────────────────────────────────────────────────────────────────────────────
// NoteBarBtn — bottom-bar icon button
// ─────────────────────────────────────────────────────────────────────────────

class NoteBarBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final double? size;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const NoteBarBtn({
    super.key,
    required this.icon,
    this.label,
    this.size,
    this.active = false,
    this.activeColor = const Color(0xFF0A84FF),
    required this.onTap,
  });

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

// Heading chip
class _HeadChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _HeadChip(this.label, this.active, this.activeColor, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              color: active ? activeColor : const Color(0xFF555555),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            )),
        ),
      ),
    );
  }
}

// Inline format button (B / I / U / S)
class _FmtBtn extends StatelessWidget {
  final String label;
  final bool bold, italic, under, strike, active;
  final VoidCallback onTap;
  const _FmtBtn({required this.label, this.bold = false, this.italic = false,
      this.under = false, this.strike = false, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF252525) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF666666),
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: under
                  ? TextDecoration.underline
                  : strike
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
              decorationColor: active ? Colors.white : const Color(0xFF666666),
            )),
        ),
      ),
    );
  }
}

// Icon button
class _FmtIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FmtIconBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF252525) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Icon(icon, size: 17,
              color: active ? Colors.white : const Color(0xFF666666)),
        ),
      ),
    );
  }
}

// Separator
class _FmtSep extends StatelessWidget {
  const _FmtSep();
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 13),
    color: const Color(0xFF2A2A2A),
  );
}

// Color toggle button (opens the color row)
class _ColorToggleBtn extends StatelessWidget {
  final Color? activeColor;
  final bool active;
  final bool isHighlight;
  final VoidCallback onTap;
  const _ColorToggleBtn({required this.activeColor, required this.active,
      required this.isHighlight, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF252525) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: isHighlight
              ? Icon(Icons.highlight_rounded, size: 17,
                  color: activeColor ?? const Color(0xFF666666))
              : Text('A',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF666666),
                    decoration: TextDecoration.underline,
                    decorationColor: activeColor ?? const Color(0xFF666666),
                    decorationThickness: 2.5,
                  )),
        ),
      ),
    );
  }
}

// Color dot
class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final bool isCustom;
  final Color? customPreview;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected,
      required this.onTap, this.isCustom = false, this.customPreview});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 22, height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCustom ? (customPreview ?? Colors.transparent) : (color ?? Colors.transparent),
          border: Border.all(
            color: selected ? Colors.white70 : (color == null && !isCustom ? const Color(0xFF333333) : Colors.transparent),
            width: selected ? 2 : 1,
          ),
        ),
        child: isCustom
            ? const Icon(Icons.colorize_rounded, size: 12, color: Colors.white38)
            : color == null
                ? const Icon(Icons.block_rounded, size: 12, color: Color(0xFF444444))
                : selected
                    ? const Icon(Icons.check_rounded, size: 12, color: Colors.black)
                    : null,
      ),
    );
  }
}