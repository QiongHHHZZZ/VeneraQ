import 'dart:async';

import 'package:flutter/material.dart';

import 'package:venera_next/components/splash_animation.dart';
import 'package:venera_next/foundation/app.dart';

/// Covers the first moments of the application with [SplashAnimation].
///
/// The shell behind the overlay is already live: bootstrap runs in `main`
/// before the first frame, so this is staging, not a loading gate. The overlay
/// therefore waits on nothing - it plays a fixed sequence, then fades out and
/// hands the screen to the UI that was building underneath it.
///
/// Skipped when the platform asks for reduced motion, because a purely
/// decorative animation is exactly what that preference exists for.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child});

  final Widget child;

  /// Whether this build shows the sequence at all.
  ///
  /// Only the Android app ships it; the repository builds no other platform.
  static bool get isEnabled => App.isAndroid;

  /// Body of the sequence, before the hand-off fade.
  static const Duration body = SplashAnimation.duration;

  /// Cross-fade onto the live UI.
  static const Duration fade = Duration(milliseconds: 320);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _body = AnimationController(
    vsync: this,
    duration: SplashOverlay.body,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: SplashOverlay.fade,
  );

  bool _reducedMotion = false;
  Timer? _handOff;

  @override
  void initState() {
    super.initState();
    // A post-frame start keeps the opening panels from playing before the
    // window is on screen, which would skip them on a slow cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reducedMotion) return;
      _body.forward();
      _handOff = Timer(SplashOverlay.body, () {
        if (mounted) _fade.forward();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _reducedMotion = true;
      _handOff?.cancel();
      // Show the finished frame, then leave.
      _body.value = 1;
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _handOff?.cancel();
    _body.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reducedMotion) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _fade,
          builder: (context, child) {
            final faded = _fade.value;
            // Drop the overlay from the tree once it is transparent, so it can
            // neither keep a ticker alive nor intercept input.
            if (faded >= 1) return const SizedBox.shrink();
            return Opacity(
              opacity: 1 - Curves.easeInOut.transform(faded),
              child: IgnorePointer(ignoring: faded > 0.5, child: child),
            );
          },
          child: SplashAnimation(progress: _body),
        ),
      ],
    );
  }
}
