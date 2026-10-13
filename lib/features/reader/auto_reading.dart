import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum AutoReadingStatus { stopped, running, paused, waiting }

enum AutoReadingStep { advanced, waiting, finished }

enum AutoReadingImageState { ready, loading, failed, blocked }

class AutoReadingImageReadiness {
  const AutoReadingImageReadiness(this.state, this.identity);
  final AutoReadingImageState state;
  final Object identity;
}

AutoReadingImageState combineAutoReadingImageStates(
  Iterable<AutoReadingImageState> images,
) {
  final states = images.toSet();
  if (states.contains(AutoReadingImageState.blocked)) {
    return AutoReadingImageState.blocked;
  }
  if (states.isEmpty || states.contains(AutoReadingImageState.loading)) {
    return AutoReadingImageState.loading;
  }
  return states.contains(AutoReadingImageState.failed)
      ? AutoReadingImageState.failed
      : AutoReadingImageState.ready;
}

abstract interface class AutoReadingImageViewport {
  AutoReadingImageReadiness get autoReadingImages;
}

class AutoReadingSettings {
  const AutoReadingSettings({
    this.gallery = false,
    this.pageInterval = 5,
    this.pixelsPerSecond = 80,
    this.stepped = false,
    this.stepsPerSecond = 2,
    this.pixelsPerStep = 40,
    this.skipUnavailableImages = false,
    this.imageWaitSeconds = 10,
  });

  final bool gallery, stepped;
  final bool skipUnavailableImages;
  final double imageWaitSeconds;
  final double pageInterval, pixelsPerSecond, stepsPerSecond, pixelsPerStep;
}

/// Drives reading from frame timestamps, without accumulating work while paused.
class AutoReadingController extends ChangeNotifier {
  AutoReadingController({
    required this.settings,
    required this.advance,
    required this.canAdvance,
    this.imageReadiness,
  }) {
    _ticker = Ticker(_tick);
  }

  final AutoReadingSettings Function() settings;
  final AutoReadingStep Function(double distance) advance;
  final bool Function() canAdvance;
  final AutoReadingImageReadiness Function()? imageReadiness;
  late final Ticker _ticker;
  final _pauses = <Object>{};
  AutoReadingStatus _status = AutoReadingStatus.stopped;
  Duration? _previous;
  double _accumulated = 0;
  double _imageWait = 0;
  Object? _imageIdentity;
  AutoReadingImageState? _imageState;

  AutoReadingStatus get status => _status;
  bool get isActive => status != AutoReadingStatus.stopped;

  void _setStatus(AutoReadingStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  void start() {
    if (isActive) return;
    _previous = null;
    _accumulated = 0;
    _resetImageWait();
    _setStatus(
      _pauses.isEmpty ? AutoReadingStatus.running : AutoReadingStatus.paused,
    );
    if (_pauses.isEmpty) _ticker.start();
  }

  void stop() {
    _ticker.stop();
    _previous = null;
    _accumulated = 0;
    _resetImageWait();
    _setStatus(AutoReadingStatus.stopped);
  }

  void toggle() => isActive ? stop() : start();

  void pause(Object reason, bool paused) {
    if (paused) {
      _pauses.add(reason);
    } else {
      _pauses.remove(reason);
    }
    _previous = null;
    _accumulated = 0;
    _resetImageWait();
    if (isActive) {
      if (_pauses.isEmpty && !_ticker.isActive) {
        _ticker.start();
      } else if (_pauses.isNotEmpty) {
        _ticker.stop();
      }
      _setStatus(
        _pauses.isEmpty ? AutoReadingStatus.running : AutoReadingStatus.paused,
      );
    }
  }

  void _resetImageWait() {
    _imageWait = 0;
    _imageIdentity = null;
    _imageState = null;
  }

  bool _imagesReady(AutoReadingSettings config, double delta) {
    final images =
        imageReadiness?.call() ??
        const AutoReadingImageReadiness(AutoReadingImageState.ready, 0);
    if (images.state == AutoReadingImageState.blocked) {
      _resetImageWait();
      return false;
    }
    final identity = images.identity;
    final previous = _imageIdentity;
    final same = previous is Set<Object> && identity is Set<Object>
        ? setEquals(previous, identity)
        : previous == identity;
    if (!same ||
        (images.state == AutoReadingImageState.loading &&
            _imageState != AutoReadingImageState.loading) ||
        images.state == AutoReadingImageState.ready ||
        !config.skipUnavailableImages) {
      _imageWait = 0;
      _imageIdentity = identity;
    }
    _imageState = images.state;
    switch (images.state) {
      case AutoReadingImageState.ready:
        return true;
      case AutoReadingImageState.failed:
        return config.skipUnavailableImages;
      case AutoReadingImageState.loading:
        if (!config.skipUnavailableImages) return false;
        _imageWait += delta;
        return _imageWait + 0.000001 >=
            config.imageWaitSeconds.clamp(1.0, 60.0);
      case AutoReadingImageState.blocked:
        return false;
    }
  }

  void _tick(Duration elapsed) {
    final previous = _previous;
    _previous = elapsed;
    if (_pauses.isNotEmpty) return;
    final seconds = previous == null
        ? 0.0
        : (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    // A stalled frame must not jump over content or exhaust an image timeout.
    final delta = seconds.clamp(0.0, 0.1);
    final config = settings();
    final allowed = canAdvance();
    if (!allowed || !_imagesReady(config, delta)) {
      if (!allowed) _resetImageWait();
      _accumulated = 0;
      _setStatus(AutoReadingStatus.waiting);
      return;
    }
    if (previous == null) return;
    _accumulated += delta;
    double distance;
    if (config.gallery || config.stepped) {
      final interval = config.gallery
          ? config.pageInterval.clamp(1.0, 60.0)
          : 1 / config.stepsPerSecond.clamp(1.0, 10.0);
      if (_accumulated + 0.000001 < interval) {
        _setStatus(AutoReadingStatus.running);
        return;
      }
      _accumulated = (_accumulated - interval).clamp(0.0, interval);
      distance = config.gallery ? 0 : config.pixelsPerStep.clamp(1.0, 500.0);
    } else {
      distance = config.pixelsPerSecond.clamp(10.0, 1000.0) * delta;
    }
    switch (advance(distance)) {
      case AutoReadingStep.advanced:
        _setStatus(AutoReadingStatus.running);
      case AutoReadingStep.waiting:
        _accumulated = 0;
        _setStatus(AutoReadingStatus.waiting);
      case AutoReadingStep.finished:
        stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

abstract interface class AutoReadingViewport {
  bool get autoReadingReady;
  AutoReadingStep autoScroll(
    double distance, {
    required bool acrossChapters,
    bool skipUnavailableImages = false,
  });
}
