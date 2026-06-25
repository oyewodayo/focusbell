import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WaveformBars
//
// Animated audio waveform scrubber.
//
// Colour contract:
//   Blue  (#0A84FF) — bars whose LEFT edge is at or before the playhead.
//   Dim white       — bars whose left edge is past the playhead.
//
// Seek contract:
//   • Tap   → instant seek to that position.
//   • Drag  → live scrub while finger is down; seek fires on every update.
//   • The widget owns a local _displayProgress so the colour moves
//     immediately, independent of how fast the parent rebuilds.
// ─────────────────────────────────────────────────────────────────────────────

class WaveformBars extends StatefulWidget {
  /// Playback position in [0.0, 1.0] from the audio player.
  final double progress;

  /// Whether audio is currently playing (drives the ripple animation).
  final bool isPlaying;

  /// Called with a [0.0, 1.0] fraction whenever the user taps or drags.
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
  final GlobalKey _barKey = GlobalKey();

  // The progress value actually painted.  While the user is scrubbing this
  // leads widget.progress so the colour responds instantly; once the finger
  // lifts we stop overriding and let the player's own progress drive it.
  late double _displayProgress;
  bool _scrubbing = false;

  // ── Static bar height profile (48 values, normalised to [0, 1]) ──────────
  static const List<double> _heights = [
    0.30, 0.55, 0.80, 0.45, 0.95, 0.60, 0.35, 0.75,
    0.50, 0.90, 0.40, 0.65, 0.85, 0.30, 0.70, 0.55,
    0.95, 0.45, 0.60, 0.80, 0.35, 0.50, 0.90, 0.40,
    0.75, 0.65, 0.30, 0.85, 0.55, 0.70, 0.95, 0.45,
    0.60, 0.80, 0.35, 0.50, 0.90, 0.40, 0.75, 0.65,
    0.30, 0.85, 0.55, 0.70, 0.95, 0.45, 0.60, 0.40,
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _displayProgress = widget.progress;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isPlaying) _animCtrl.repeat();
  }

  @override
  void didUpdateWidget(WaveformBars old) {
    super.didUpdateWidget(old);

    // Sync animation state.
    if (widget.isPlaying && !_animCtrl.isAnimating) {
      _animCtrl.repeat();
    } else if (!widget.isPlaying && _animCtrl.isAnimating) {
      _animCtrl.stop();
      _animCtrl.value = 0;
    }

    // While the user is NOT scrubbing, keep _displayProgress in sync with
    // the player so the blue fill advances as audio plays.
    if (!_scrubbing) {
      _displayProgress = widget.progress;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Seek helpers ──────────────────────────────────────────────────────────

  /// Resolves a global touch position to a [0, 1] fraction using the
  /// RenderBox of the SizedBox that wraps the CustomPaint.
  double? _fractionFromGlobal(Offset globalPos) {
    final ro = _barKey.currentContext?.findRenderObject();
    if (ro == null || ro is! RenderBox) return null;
    final local = ro.globalToLocal(globalPos);
    return (local.dx / ro.size.width).clamp(0.0, 1.0);
  }

  void _onScrubStart(Offset globalPos) {
    final f = _fractionFromGlobal(globalPos);
    if (f == null) return;
    setState(() {
      _scrubbing = true;
      _displayProgress = f;
    });
    widget.onSeek(f);
  }

  void _onScrubUpdate(Offset globalPos) {
    final f = _fractionFromGlobal(globalPos);
    if (f == null) return;
    setState(() => _displayProgress = f);
    widget.onSeek(f);
  }

  void _onScrubEnd() {
    // Stop overriding; let widget.progress drive the display again.
    // We keep _displayProgress at the last scrubbed value for one frame so
    // there is no visual snap before the player position propagates back.
    setState(() => _scrubbing = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            // ── Horizontal drag (scrub forward / backward) ─────────────────
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer>(
              HorizontalDragGestureRecognizer.new,
              (inst) {
                inst.onStart  = (d) => _onScrubStart(d.globalPosition);
                inst.onUpdate = (d) => _onScrubUpdate(d.globalPosition);
                inst.onEnd    = (_) => _onScrubEnd();
                inst.onCancel = ()  => _onScrubEnd();
              },
            ),
            // ── Tap (single-point seek) ────────────────────────────────────
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (inst) {
                inst.onTapDown   = (d) => _onScrubStart(d.globalPosition);
                inst.onTapUp     = (d) {
                  _onScrubUpdate(d.globalPosition);
                  _onScrubEnd();
                };
                inst.onTapCancel = () => _onScrubEnd();
              },
            ),
          },
          child: SizedBox(
            key: _barKey,
            width: constraints.maxWidth,
            height: 32,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, __) => CustomPaint(
                painter: _WaveformPainter(
                  heights: _heights,
                  progress: _displayProgress,
                  isPlaying: widget.isPlaying,
                  isScrubbing: _scrubbing,
                  animValue: _animCtrl.value,
                ),
                // Only allocate a compositing layer when the bars are moving.
                willChange: widget.isPlaying || _scrubbing,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformPainter
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> heights;
  final double progress;   // [0, 1] — which fraction of bars to paint blue
  final bool isPlaying;
  final bool isScrubbing;
  final double animValue;  // [0, 1] from AnimationController for ripple

  static const int    _barCount = 48;
  static const double _gap      = 2.0;
  static const double _radius   = 2.0;

  const _WaveformPainter({
    required this.heights,
    required this.progress,
    required this.isPlaying,
    required this.isScrubbing,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Bar width derived from the total canvas width, gap count, and bar count.
    final double barW = (size.width - _gap * (_barCount - 1)) / _barCount;

    // ── Paints ─────────────────────────────────────────────────────────────

    final paintPlayed = Paint()
      ..color = const Color(0xFF0A84FF)
              .withValues(alpha: (isPlaying || isScrubbing) ? 1.0 : 0.80);

    final paintUnplayed = Paint()
      ..color = Colors.white
              .withValues(alpha: isPlaying ? 0.28 : 0.16);

    // Soft glow drawn on top of the boundary bar.
    final paintGlow = Paint()
      ..color = const Color(0xFF0A84FF).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // ── Bar loop ───────────────────────────────────────────────────────────

    // The playhead sits at pixel offset:  progress * (size.width - barW)
    // A bar at index i has its left edge at:  i * (barW + _gap)
    // We paint it blue when its LEFT EDGE is at or before the playhead pixel.
    final double headPx = progress * size.width;

    int? glowBarIndex;

    for (int i = 0; i < _barCount; i++) {
      final double barLeft = i * (barW + _gap);
      final bool played   = barLeft <= headPx;

      // ── Height ─────────────────────────────────────────────────────────
      double h = heights[i % heights.length];

      if (isPlaying) {
        // Sine ripple: played bars ripple gently; unplayed bars breathe more.
        final double phase     = (i / _barCount) * 2 * math.pi;
        final double wave      = math.sin(animValue * 2 * math.pi + phase);
        final double amplitude = played ? 0.08 : 0.28;
        h = (h + amplitude * wave).clamp(0.08, 1.0);
      }

      final double barH = size.height * h;
      final double top  = (size.height - barH) / 2;

      // Track the bar closest to the playhead boundary for the glow pass.
      if (played) glowBarIndex = i;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, top, barW, barH),
          const Radius.circular(_radius),
        ),
        played ? paintPlayed : paintUnplayed,
      );
    }

    // ── Playhead glow (second pass, on top of bars) ────────────────────────
    // Only render when something is actively happening so idle state stays clean.
    if (glowBarIndex != null && (isPlaying || isScrubbing) && progress > 0) {
      final int i        = glowBarIndex;
      final double h     = heights[i % heights.length].clamp(0.08, 1.0);
      final double barH  = size.height * h;
      final double barLeft = i * (barW + _gap);
      final double top   = (size.height - barH) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft - 1, top, barW + 2, barH),
          const Radius.circular(_radius + 1),
        ),
        paintGlow,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress    != progress    ||
      old.animValue   != animValue   ||
      old.isPlaying   != isPlaying   ||
      old.isScrubbing != isScrubbing;
}
