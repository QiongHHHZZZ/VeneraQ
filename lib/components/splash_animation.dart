import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The launch sequence for the app.
///
/// The visual language is manga's own, used without borrowing any artwork: a
/// field of focus lines (集中線) converges on the centre, tightening as the app
/// comes up, and the wordmark is struck into the space they leave. It is the
/// one mark that reads as "comics" at a glance, it carries its own motion, and
/// it belongs to no particular series - which matters for an app that ships no
/// content of its own.
///
/// The lines are drawn, not sampled: their angles are seeded from a fixed
/// number so every launch is identical, and their length and weight animate off
/// a single [progress] timeline through [_slice].
class SplashAnimation extends StatelessWidget {
  const SplashAnimation({super.key, required this.progress});

  final Animation<double> progress;

  /// On-screen time of the sequence, excluding the hand-off fade.
  static const Duration duration = Duration(milliseconds: 1500);

  /// Seed for the focus-line fan. Fixed so the composition never reshuffles.
  static const int lineSeed = 0x5EED;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark,
    );

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value.clamp(0.0, 1.0);
        final mark = _slice(t, 0.52, 0.80);
        final settle = _slice(t, 0.62, 1.0, Curves.easeOut);

        return LayoutBuilder(
          builder: (context, constraints) {
            final radius = constraints.biggest.longestSide;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.groundTop, palette.groundBottom],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _FocusLinePainter(
                      progress: t,
                      palette: palette,
                      radius: radius,
                      seed: SplashAnimation.lineSeed,
                    ),
                  ),
                  CustomPaint(
                    painter: _HalftonePainter(progress: t, palette: palette),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: mark,
                          child: Transform.scale(
                            // The mark lands a touch large and settles, which
                            // reads as being struck rather than faded in.
                            scale: lerpDouble(1.06, 1.0, settle),
                            child: Text(
                              'VeneraQ',
                              style: TextStyle(
                                fontSize: 30,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                color: palette.wordmark,
                                letterSpacing: lerpDouble(20, 1.6, mark),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        SizedBox(
                          height: 2,
                          width: 126 * settle,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(
                                alpha: 0.9 * settle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Fixed colours for the launch sequence.
///
/// Not theme-derived on purpose: the splash has to match the native window
/// background before the settings store is read, or the hand-off flashes a
/// different colour. The two variants mirror `values`/`values-night`.
class SplashPalette {
  const SplashPalette({
    required this.groundTop,
    required this.groundBottom,
    required this.line,
    required this.halftone,
    required this.accent,
    required this.wordmark,
  });

  final Color groundTop;
  final Color groundBottom;
  final Color line;
  final Color halftone;
  final Color accent;
  final Color wordmark;

  static SplashPalette of(Brightness brightness) =>
      brightness == Brightness.dark
      ? const SplashPalette(
          groundTop: Color(0xFF1B1228),
          groundBottom: Color(0xFF08050E),
          line: Color(0xCCE8DDF7),
          halftone: Color(0xFFCBB8E8),
          accent: Color(0xFFE85D8E),
          wordmark: Color(0xFFF7F2FE),
        )
      : const SplashPalette(
          // Deliberately not near-white: at #F2ECFB the ground measured 94% of
          // white's luminance, which reads as a white flash on a phone. This
          // sits in the launcher icon's own violet range instead.
          groundTop: Color(0xFFDCCEF2),
          groundBottom: Color(0xFFB79BD9),
          // Dark enough to read on the violet ground, and violet-black rather
          // than pure black so the fan looks printed instead of struck.
          line: Color(0xB32A1C3E),
          halftone: Color(0xFF3E2B52),
          accent: Color(0xFF9C1450),
          wordmark: Color(0xFF1B1226),
        );
}

/// Returns eased progress for one slice of the timeline.
double _slice(
  double t,
  double from,
  double to, [
  Curve curve = Curves.easeOutCubic,
]) {
  if (to <= from) return t >= to ? 1.0 : 0.0;
  return curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
}

/// Deterministic pseudo-random in [0,1) for a given seed and index.
///
/// The fan must look scattered but be identical on every launch, so a cheap
/// integer hash is used instead of [math.Random].
double _hash(int seed, int index) {
  final x = (seed * 1103515245 + index * 12345) & 0x7FFFFFFF;
  final y = (x ^ (x >> 13)) * 1274126177 & 0x7FFFFFFF;
  return (y & 0xFFFF) / 0xFFFF;
}

/// The focus-line fan: wedges converging on the centre of the screen.
///
/// Lines grow inward from beyond the frame as the sequence opens, hold while
/// the mark lands, then thin out and retract. Nothing here is a rectangle, so
/// it never reads as a UI skeleton.
class _FocusLinePainter extends CustomPainter {
  _FocusLinePainter({
    required this.progress,
    required this.palette,
    required this.radius,
    required this.seed,
  });

  final double progress;
  final SplashPalette palette;
  final double radius;
  final int seed;

  static const int lineCount = 96;

  @override
  void paint(Canvas canvas, Size size) {
    // The fan is present from the very first frame, short but not faint: the
    // opening paint has to read as a design, not as an empty background, or the
    // hand-off from the native splash looks like a white flash.
    final open = _slice(progress, 0.0, 0.34, Curves.easeOutCubic);
    final close = _slice(progress, 0.76, 1.0, Curves.easeInOut);
    final presence = lerpDouble(0.55, 1.0, open)! * (1 - close);

    final centre = size.center(Offset.zero);
    // Keep the centre clear: the mark lives there, so the fan stops well short
    // of the text even while it is still fading in.
    final inner = size.shortestSide * lerpDouble(0.38, 0.26, open)!;
    final outer = radius * lerpDouble(0.72, 1.05, open)! * lerpDouble(1.0, 0.81, close)!;

    final paint = Paint()..style = PaintingStyle.stroke;

    for (var i = 0; i < lineCount; i++) {
      final jitter = _hash(seed, i);
      // Spread slightly past a full turn so the fan has no visible seam.
      final angle = (i / lineCount) * math.pi * 2 + (jitter - 0.5) * 0.06;
      final width = lerpDouble(0.6, 2.6, _hash(seed, i + 1000))! * (1 - close * 0.6);
      // Every third line is a long one; the rest are short ticks.
      final reach = i % 3 == 0
          ? 1.0
          : lerpDouble(0.28, 0.62, _hash(seed, i + 2000))!;
      // Dots and dashes at the tail of each line, like drawn screentone.
      final fade = (0.35 + 0.65 * _hash(seed, i + 3000)) * presence;

      final startRadius = inner + (outer - inner) * (1 - reach) * (1 - open);
      final endRadius = lerpDouble(inner, outer, reach)!;

      paint
        ..color = palette.line.withValues(alpha: fade)
        ..strokeWidth = width;

      final start = centre +
          Offset(math.cos(angle), math.sin(angle)) * startRadius;
      final end =
          centre + Offset(math.cos(angle), math.sin(angle)) * endRadius;
      canvas.drawLine(start, end, paint);
    }

    // A few heavier spokes anchored to the corners for composition weight.
    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = i / 8 * math.pi * 2 + math.pi / 8;
      accentPaint
        ..color = palette.accent.withValues(alpha: 0.22 * presence)
        ..strokeWidth = 3.4 * (1 - close);
      canvas.drawLine(
        centre + Offset(math.cos(angle), math.sin(angle)) * (inner * 0.92),
        centre + Offset(math.cos(angle), math.sin(angle)) * outer,
        accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusLinePainter old) =>
      old.progress != progress ||
      old.palette != palette ||
      old.radius != radius;
}

/// Sparse halftone field over the ground, drifting so the frame is never
/// completely still even when the lines hold.
class _HalftonePainter extends CustomPainter {
  _HalftonePainter({required this.progress, required this.palette});

  final double progress;
  final SplashPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // Present from the first frame for the same reason as the fan: a field that
    // fades up from nothing leaves the opening paint looking empty.
    final reveal = lerpDouble(0.25, 1.0, _slice(progress, 0.0, 0.30, Curves.easeIn))!;

    final step = size.shortestSide / 15;
    final drift = Offset(
      math.cos(progress * math.pi * 0.7) * step * 0.3,
      math.sin(progress * math.pi * 0.5) * step * 0.4,
    );
    final paint = Paint();

    for (var row = -1; row <= (size.height / step).ceil(); row++) {
      for (var col = -1; col <= (size.width / step).ceil(); col++) {
        final point = Offset(
          col * step + (row.isEven ? 0 : step / 2) + drift.dx,
          row * step + drift.dy,
        );
        // Thin the field toward the middle so the mark stays legible.
        final distance =
            (point - size.center(Offset.zero)).distance / size.shortestSide;
        final density = ((distance - 0.18) * 2.2).clamp(0.0, 1.0);
        if (density <= 0) continue;
        paint.color = palette.halftone.withValues(
          alpha: 0.16 * reveal * density,
        );
        canvas.drawCircle(point, 1.25 * density, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) =>
      old.progress != progress || old.palette != palette;
}
