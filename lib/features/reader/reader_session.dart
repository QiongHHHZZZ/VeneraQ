import 'dart:async';

import 'package:venera_next/features/reader/history_writer.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/operation_failure.dart';

class ReaderSessionFailure implements FailureDetails {
  ReaderSessionFailure(
    Iterable<({String operation, Object error, StackTrace stackTrace})>
    failures,
  ) : failures = List.unmodifiable(failures);

  final List<({String operation, Object error, StackTrace stackTrace})>
  failures;

  @override
  FailureKind get kind => FailureKind.failed;
  @override
  String get message =>
      'Reader session failed: ${failures.map((failure) => failure.operation).join(', ')}';
  @override
  Object? get cause => failures.firstOrNull?.error;
  @override
  StackTrace? get stackTrace => failures.firstOrNull?.stackTrace;
  @override
  String toString() => message;
}

/// Owns progress lifetimes for one reader. Platform lifecycle
/// events are adapted to foreground state; content readiness is independent.
class ReaderSession {
  ReaderSession({
    required ReaderHistoryWriter progress,
    required void Function(bool paused) onPauseChanged,
    required FutureOr<void> Function() onClosed,
    required bool foreground,
    ImageWork? imageWork,
  }) : _progress = progress,
       _onPauseChanged = onPauseChanged,
       _onClosed = onClosed,
       _foreground = foreground,
       _imageWork = imageWork ?? ImageWork();

  final ReaderHistoryWriter _progress;
  final void Function(bool) _onPauseChanged;
  final FutureOr<void> Function() _onClosed;
  final ImageWork _imageWork;
  bool _foreground;
  bool _contentReady = false;
  bool _disposed = false;
  Future<void>? _closing;
  final Set<Object> _holds = {};
  Future<void Function()>? _preparing;
  int? _preparedRevision;
  int _revision = 0;
  int _notifiedRevision = -1;

  bool get contentReady => _contentReady;
  bool get isHeld => _holds.isNotEmpty;

  void setContentReady(bool ready) {
    if (_disposed) return;
    if (_contentReady != ready) _revision++;
    _contentReady = ready;
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    if (_foreground != foreground) _revision++;
    _foreground = foreground;
    _onPauseChanged(!foreground || _holds.isNotEmpty);
  }

  void scheduleProgress() {
    if (_disposed) return;
    _revision++;
    // Accepted content/animation completions can still arrive while held.
    // Retain their latest snapshot for the next drain instead of dropping it.
    _progress.schedule();
  }

  /// Synchronously stop accepted work before a host starts waiting on another
  /// owner's saves. Separate holds compose and each release is idempotent.
  void Function() holdForExit() {
    if (_disposed) return () {};
    final hold = Object();
    _holds.add(hold);
    final releaseImages = _imageWork.holdForExit();
    try {
      _onPauseChanged(true);
    } catch (error, stack) {
      _holds.remove(hold);
      final failures =
          <({String operation, Object error, StackTrace stackTrace})>[
            (operation: 'pause session', error: error, stackTrace: stack),
          ];
      _restoreAfterHold(
        releaseImages,
        failures,
        restorePause: _holds.isEmpty,
      );
      if (failures.length > 1) throw ReaderSessionFailure(failures);
      rethrow;
    }
    return () {
      if (!_holds.remove(hold)) return;
      final failures =
          <({String operation, Object error, StackTrace stackTrace})>[];
      _restoreAfterHold(releaseImages, failures);
      if (failures.length == 1) {
        Error.throwWithStackTrace(
          failures.single.error,
          failures.single.stackTrace,
        );
      }
      if (failures.isNotEmpty) throw ReaderSessionFailure(failures);
    };
  }

  void _restoreAfterHold(
    void Function() releaseImages,
    List<({String operation, Object error, StackTrace stackTrace})> failures, {
    bool restorePause = true,
  }) {
    void observe(String operation, void Function() restore) {
      try {
        restore();
      } catch (error, stackTrace) {
        failures.add((
          operation: operation,
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }

    observe('resume image operations', releaseImages);
    if (_disposed) return;
    if (restorePause) {
      observe(
        'resume session',
        () => _onPauseChanged(!_foreground || _holds.isNotEmpty),
      );
    }
  }

  /// Save without destroying a mounted reader. A later shutdown failure can
  /// release the hold and continue from the latest foreground/readiness state.
  /// A completed preparation remains reusable until new work arrives. A new
  /// drain then owns another hold without taking the earlier caller's release.
  Future<void Function()> prepareForExit() {
    if (_disposed) {
      return Future.error(StateError('Reader session is closed'));
    }
    if (_preparing != null &&
        (_preparedRevision == null || _preparedRevision == _revision)) {
      return _preparing!;
    }
    final releaseHold = holdForExit();
    final completion = Completer<void Function()>();
    _preparing = completion.future;
    _preparedRevision = null;
    void release() {
      if (identical(_preparing, completion.future)) {
        _preparing = null;
        _preparedRevision = null;
      }
      releaseHold();
    }

    _drain(finalize: false).then(
      (revision) {
        if (identical(_preparing, completion.future)) {
          _preparedRevision = revision;
        }
        completion.complete(release);
      },
      onError: (Object error, StackTrace stack) {
        try {
          release();
          completion.completeError(error, stack);
        } catch (resumeError, resumeStack) {
          completion.completeError(
            ReaderSessionFailure([
              if (error is ReaderSessionFailure)
                ...error.failures
              else
                (operation: 'prepare', error: error, stackTrace: stack),
              (
                operation: 'resume',
                error: resumeError,
                stackTrace: resumeStack,
              ),
            ]),
            stack,
          );
        }
      },
    );
    return completion.future;
  }

  Future<int> _drain({
    required bool finalize,
    List<({String operation, Object error, StackTrace stackTrace})>
        previousImageFailures =
        const [],
  }) async {
    final failures =
        <({String operation, Object error, StackTrace stackTrace})>[];
    Future<void> observe(String operation, Future<void> Function() run) async {
      try {
        await run();
      } catch (error, stackTrace) {
        failures.add((
          operation: operation,
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }

    // Save immediately while reads/platform deliveries finish independently.
    // Their errors survive newer save revisions; notification waits for both.
    final imageFailures =
        <({String operation, Object error, StackTrace stackTrace})>[
          ...previousImageFailures,
        ];
    final images = () async {
      try {
        if (finalize) {
          await _imageWork.dispose();
        } else {
          final release = await _imageWork.prepareForExit();
          release();
        }
      } catch (error, stackTrace) {
        if (!imageFailures.any((failure) => identical(failure.error, error))) {
          imageFailures.add((
            operation: 'image operations',
            error: error,
            stackTrace: stackTrace,
          ));
        }
      }
    }();

    while (true) {
      final revision = _revision;
      failures.clear();
      await Future.wait([
        images,
        observe('progress', finalize ? _progress.dispose : _progress.flush),
      ]);
      failures.addAll(imageFailures);
      // A content completion can schedule progress after its writer drained.
      if (_revision != revision) continue;
      // Some writes may have committed even when another failed. Mark those
      // changes for sync after draining, preserving save and notify errors.
      if (_notifiedRevision != revision) {
        await observe('notification', () async {
          await _onClosed();
          // A failed batch can commit more data when the same revision is
          // retried, even if the reader remains paused throughout.
          if (failures.isEmpty) _notifiedRevision = revision;
        });
      }
      if (_revision != revision) continue;
      if (failures.isNotEmpty) throw ReaderSessionFailure(failures);
      return revision;
    }
  }

  /// Submit pending progress immediately, then drain the writer before
  /// notifying the application once.
  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _disposed = true;
    // Freeze image operations synchronously even when a preparation is still
    // saving. _drain will join this same close once that preparation settles.
    final imageClosing = _imageWork.dispose();
    unawaited(imageClosing.then<void>((_) {}, onError: (Object _) {}));
    _contentReady = false;
    _holds.clear();
    final preparing = _preparing;
    if (preparing == null) {
      return _closing = _drain(finalize: true).then<void>((_) {});
    }
    // Writers re-report unresolved saves during finalization. Image errors
    // already taken by an in-flight preparation need explicit handoff, since
    // its UI may have detached before receiving that preparation's failure.
    final previousImageFailures =
        <({String operation, Object error, StackTrace stackTrace})>[];
    return _closing = preparing
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            if (error is ReaderSessionFailure) {
              previousImageFailures.addAll(
                error.failures.where(
                  (failure) => failure.operation == 'image operations',
                ),
              );
            }
          },
        )
        .then(
          (_) => _drain(
            finalize: true,
            previousImageFailures: previousImageFailures,
          ),
        )
        .then<void>((_) {});
  }
}
