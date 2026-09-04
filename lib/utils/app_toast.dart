import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Lightweight overlay toast — no third-party dependency.
class AppToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String msg,
    Color? backgroundColor,
    Color? textColor,
  }) {
    if (!context.mounted) return;

    final fb = Theme.of(context).fb;
    _showInternal(
      context,
      msg: msg,
      backgroundColor: backgroundColor ?? fb.surfaceVar,
      textColor: textColor ?? fb.onSurface,
      borderColor: fb.border,
    );
  }

  /// Positive/success toast — themed green tint in both modes.
  static void success(BuildContext context, String msg) {
    if (!context.mounted) return;
    final fb = Theme.of(context).fb;
    _showInternal(
      context,
      msg: msg,
      backgroundColor: fb.successBg,
      textColor: fb.success,
      borderColor: fb.border,
    );
  }

  /// Negative/error toast — themed red tint in both modes.
  static void error(BuildContext context, String msg) {
    if (!context.mounted) return;
    final fb = Theme.of(context).fb;
    _showInternal(
      context,
      msg: msg,
      backgroundColor: fb.dangerBg,
      textColor: fb.danger,
      borderColor: fb.border,
    );
  }

  /// Cautionary toast — themed amber tint in both modes.
  static void warning(BuildContext context, String msg) {
    if (!context.mounted) return;
    final fb = Theme.of(context).fb;
    _showInternal(
      context,
      msg: msg,
      backgroundColor: fb.warningBg,
      textColor: fb.warning,
      borderColor: fb.border,
    );
  }

  static void _showInternal(
    BuildContext context, {
    required String msg,
    required Color backgroundColor,
    required Color textColor,
    required Color borderColor,
  }) {
    // Remove any existing toast first
    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        msg: msg,
        backgroundColor: backgroundColor,
        textColor: textColor,
        borderColor: borderColor,
        onDone: () {
          if (_current == entry) {
            entry.remove();
            _current = null;
          }
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String msg;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;
  final VoidCallback onDone;

  const _ToastWidget({
    required this.msg,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
    required this.onDone,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    // Start fade-out after visible duration
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) {
        _ctrl.reverse().then((_) => widget.onDone());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 88,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fade,
        child: IgnorePointer(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: widget.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.msg,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}