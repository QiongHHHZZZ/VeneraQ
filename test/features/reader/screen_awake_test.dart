import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/platform_effects_controller.dart';

void main() {
  test(
    'screen ownership follows holds, settings, and the latest reader',
    () async {
      final calls = <bool>[];
      final coordinator = ReaderPlatformEffectsCoordinator(
        applyOrientation: (_) async {},
        applySystemBars: (_) async {},
        applyScreenAwake: (value) async => calls.add(value),
        onError: (error, _) => fail('$error'),
      );
      final old = coordinator.createOwner(orientationEnabled: true);
      await old.attach();
      await old.setScreenAwake(true);
      await old.cycleOrientation();
      expect(calls, [true]);
      final pause = Object();
      await old.hold(pause, true);
      await old.hold(pause, false);
      expect(calls, [true, false, true]);
      final next = coordinator.createOwner(orientationEnabled: true);
      await next.attach();
      await next.setScreenAwake(true);
      await old.closeAndWait();
      expect(calls, [true, false, true, false, true]);
      await next.setScreenAwake(false);
      await next.setScreenAwake(true);
      await next.closeAndWait();
      expect(calls.takeLast(3), [false, true, false]);
    },
  );

  test(
    'a delayed enable is followed by disable before exit completes',
    () async {
      final enable = Completer<void>();
      final calls = <bool>[];
      final coordinator = ReaderPlatformEffectsCoordinator(
        applyOrientation: (_) async {},
        applySystemBars: (_) async {},
        applyScreenAwake: (value) async {
          calls.add(value);
          if (value) await enable.future;
        },
        onError: (error, _) => fail('$error'),
      );
      final owner = coordinator.createOwner(orientationEnabled: false);
      await owner.attach();
      final turningOn = owner.setScreenAwake(true);
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = owner.closeAndWait().then((_) => closed = true);
      expect(closed, isFalse);
      enable.complete();
      await turningOn;
      await closing;
      expect(calls, [true, false]);
    },
  );

  test('failed disable remains retryable', () async {
    var reject = true;
    final calls = <bool>[];
    final coordinator = ReaderPlatformEffectsCoordinator(
      applyOrientation: (_) async {},
      applySystemBars: (_) async {},
      applyScreenAwake: (value) async {
        calls.add(value);
        if (!value && reject) throw StateError('platform unavailable');
      },
      onError: (_, _) {},
    );
    final owner = coordinator.createOwner(orientationEnabled: false);
    await owner.attach();
    await owner.setScreenAwake(true);
    await expectLater(owner.closeAndWait(), throwsStateError);
    reject = false;
    await owner.closeAndWait();
    expect(calls, [true, false, false]);
  });
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
