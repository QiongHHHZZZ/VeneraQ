import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/auto_reading.dart';

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('a loading visible image waits even alongside a failed image', () {
    expect(
      combineAutoReadingImageStates([
        AutoReadingImageState.ready,
        AutoReadingImageState.failed,
        AutoReadingImageState.loading,
      ]),
      AutoReadingImageState.loading,
    );
    expect(
      combineAutoReadingImageStates([
        AutoReadingImageState.ready,
        AutoReadingImageState.failed,
      ]),
      AutoReadingImageState.failed,
    );
    expect(combineAutoReadingImageStates([]), AutoReadingImageState.loading);
  });
  testWidgets('default waits for loading and failed images', (tester) async {
    var state = AutoReadingImageState.loading;
    var advances = 0;
    final reader = AutoReadingController(
      settings: () => const AutoReadingSettings(),
      canAdvance: () => true,
      imageReadiness: () => AutoReadingImageReadiness(state, 'image'),
      advance: (_) {
        advances++;
        return AutoReadingStep.advanced;
      },
    );
    addTearDown(reader.dispose);
    reader.start();
    await tester.pump();
    await frames(tester, 100);
    state = AutoReadingImageState.failed;
    await frames(tester, 100);
    expect(advances, 0);
    expect(reader.status, AutoReadingStatus.waiting);
    state = AutoReadingImageState.ready;
    await frames(tester, 5);
    expect(advances, 5);
    reader.stop();
  });

  testWidgets(
    'failed images skip at the normal interval and still respect input guards',
    (tester) async {
      var allowed = false;
      var state = AutoReadingImageState.failed;
      var advances = 0;
      final reader = AutoReadingController(
        settings: () => const AutoReadingSettings(
          gallery: true,
          pageInterval: 1,
          skipUnavailableImages: true,
        ),
        canAdvance: () => allowed,
        imageReadiness: () => AutoReadingImageReadiness(state, advances),
        advance: (_) {
          advances++;
          return advances == 2
              ? AutoReadingStep.finished
              : AutoReadingStep.advanced;
        },
      );
      addTearDown(reader.dispose);
      reader.start();
      await tester.pump();
      await frames(tester, 100);
      expect(advances, 0);
      allowed = true;
      state = AutoReadingImageState.blocked;
      await frames(tester, 100);
      expect(advances, 0);
      state = AutoReadingImageState.failed;
      await frames(tester, 51);
      expect(advances, 1);
      await frames(tester, 51);
      expect(advances, 2);
      expect(reader.isActive, isFalse);
    },
  );

  testWidgets(
    'loading timeout follows visible images and excludes pauses and stalled frames',
    (tester) async {
      var image = 'one';
      var state = AutoReadingImageState.loading;
      var distance = 0.0;
      var skip = true;
      final reader = AutoReadingController(
        settings: () => AutoReadingSettings(
          pixelsPerSecond: 100,
          skipUnavailableImages: skip,
          imageWaitSeconds: 1,
        ),
        canAdvance: () => true,
        imageReadiness: () => AutoReadingImageReadiness(state, <Object>{image}),
        advance: (delta) {
          distance += delta;
          return AutoReadingStep.advanced;
        },
      );
      addTearDown(reader.dispose);
      reader.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      await frames(tester, 20);
      expect(distance, 0);
      reader.pause('background', true);
      await tester.pump(const Duration(seconds: 20));
      reader.pause('background', false);
      await tester.pump();
      await frames(tester, 30);
      expect(distance, 0);
      await frames(tester, 30);
      expect(distance, greaterThan(0));
      final afterTimeout = distance;
      state = AutoReadingImageState.failed;
      await frames(tester, 5);
      state = AutoReadingImageState.loading;
      final retryStart = distance;
      await frames(tester, 30);
      expect(distance, retryStart);
      expect(retryStart, greaterThan(afterTimeout));
      final before = distance;
      image = 'two';
      await frames(tester, 30);
      expect(distance, before);
      state = AutoReadingImageState.ready;
      await frames(tester, 10);
      expect(distance, closeTo(before + 20, 0.001));
      state = AutoReadingImageState.loading;
      skip = false;
      final withoutSkip = distance;
      await frames(tester, 100);
      expect(distance, withoutSkip);
      reader.stop();
    },
  );
}
