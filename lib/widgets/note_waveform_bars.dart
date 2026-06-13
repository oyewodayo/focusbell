import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class WaveformBars extends StatefulWidget {
  final double progress;
  final bool isPlaying;
  final void Function(double fraction) onSeek;

  const WaveformBars({
    super.key,
    required this.progress,
    required this.isPlaying,
    required this.onSeek,
  });

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  final GlobalKey _sizedBoxKey = GlobalKey();
  double _totalWidth = 0;

  static const List<double> _heights = [
    0.30,
    0.55,
    0.80,
    0.45,
    0.95,
    0.60,
    0.35,
    0.75,
    0.50,
    0.90,
    0.40,
    0.65,
    0.85,
    0.30,
    0.70,
    0.55,
    0.95,
    0.45,
    0.60,
    0.80,
    0.35,
    0.50,
    0.90,
    0.40,
    0.75,
    0.65,
    0.30,
    0.85,
    0.55,
    0.70,
    0.95,
    0.45,
    0.60,
    0.80,
    0.35,
    0.50,
    0.90,
    0.40,
    0.75,
    0.65,
    0.30,
    0.85,
    0.55,
    0.70,
    0.95,
    0.45,
    0.60,
    0.40,
  ];

@override
void initState() {
  super.initState();
  _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  if (widget.isPlaying) _animCtrl.repeat();
}

@override
void didUpdateWidget(WaveformBars old) {
  super.didUpdateWidget(old);
  if (widget.isPlaying && !_animCtrl.isAnimating) {
    _animCtrl.repeat();
  } else if (!widget.isPlaying && _animCtrl.isAnimating) {
    _animCtrl.stop();
    _animCtrl.value = 0;
  }
  // Force repaint when progress changes (even if animation is stopped)
  if (widget.progress != old.progress) {
    setState(() {});
  }
}

@override
void dispose() {
  _animCtrl.dispose();
  super.dispose();
}

  void _handleSeek(Offset globalPosition) {
  final box = _sizedBoxKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  final local = box.globalToLocal(globalPosition);
  final f = (local.dx / box.size.width).clamp(0.0, 1.0);
  widget.onSeek(f);
}

  @override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(),
            (HorizontalDragGestureRecognizer instance) {
              instance.onStart = (d) => _handleSeek(d.globalPosition);  // ← global
              instance.onUpdate = (d) => _handleSeek(d.globalPosition); // ← global
            },
          ),
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(),
            (TapGestureRecognizer instance) {
              instance.onTapDown = (d) => _handleSeek(d.globalPosition); // ← global
            },
          ),
        },
        child: SizedBox(
          key: _sizedBoxKey,   // ← key on SizedBox for accurate bounds
          width: constraints.maxWidth,
          height: 32,
          child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _WaveformPainter(
                heights: _heights,
                progress: widget.progress,
                isPlaying: widget.isPlaying,
                animValue: _animCtrl.value,
                totalWidth: constraints.maxWidth,
              ),
              willChange: true,
            );
          },
        ),
        ),
      );
    },
  );
}
}

class _WaveformPainter extends CustomPainter {
  final List<double> heights;
  final double progress;
  final bool isPlaying;
  final double animValue;
  final double totalWidth;

  static const int barCount = 48;
  static const double gap = 2.0;
  static const double radius = 2.0;

  const _WaveformPainter({
    required this.heights,
    required this.progress,
    required this.isPlaying,
    required this.animValue,
    required this.totalWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barW = (size.width - gap * (barCount - 1)) / barCount;

    final paintPlayed = Paint()
      ..color = isPlaying
          ? const Color(0xFF0A84FF)
          : const Color(0xFF0A84FF).withValues(alpha: 0.6);
    final paintUnplayed = Paint()
      ..color = isPlaying
          ? Colors.white.withValues(alpha: 0.25)
          : Colors.white.withValues(alpha: 0.12);

    for (int i = 0; i < barCount; i++) {
      final frac = i / (barCount - 1);
      final played = frac <= progress;

      double h = heights[i % heights.length];

      if (isPlaying) {
        final phase = (i / barCount) * 2 * math.pi;
        final wave = math.sin((animValue * 2 * math.pi) + phase);
        final amplitude = played ? 0.15 : 0.35;
        h = (h + amplitude * wave).clamp(0.08, 1.0);
      }

      final barH = size.height * h;
      final left = i * (barW + gap);
      final top = (size.height - barH) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barW, barH),
          const Radius.circular(radius),
        ),
        played ? paintPlayed : paintUnplayed,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.animValue != animValue ||
      old.progress != progress ||
      old.isPlaying != isPlaying;
}
