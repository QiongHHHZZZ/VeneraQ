import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/comic_image.dart';
import 'package:venera_next/features/reader/image_dimensions.dart';

class _PendingImage extends ImageProvider<_PendingImage> {
  final result = Completer<ImageInfo>();

  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _PendingImage key,
    ImageErrorListener handleError,
  ) => stream.setCompleter(OneFrameImageStreamCompleter(result.future));
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final photo in [true, false]) {
    testWidgets(
      '${photo ? 'PhotoView' : 'ComicImage'} loading waits for active time',
      (tester) async {
        final provider = _PendingImage();
        final key = GlobalKey<ComicImageState>();
        var observed = AutoReadingImageState.loading;
        var advances = 0;
        final reader = AutoReadingController(
          settings: () => const AutoReadingSettings(
            gallery: true,
            pageInterval: 1,
            imageWaitSeconds: 1,
            skipUnavailableImages: true,
          ),
          canAdvance: () => true,
          imageReadiness: () => AutoReadingImageReadiness(
            photo ? observed : key.currentState!.autoReadingImageState,
            provider,
          ),
          advance: (_) {
            advances++;
            return AutoReadingStep.finished;
          },
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: SizedBox(
                width: 400,
                height: 500,
                child: photo
                    ? ReaderImageDimensions(
                        image: provider,
                        showDimensions: false,
                        onLoadState: (state) => observed = state,
                        child: PhotoView(imageProvider: provider),
                      )
                    : ComicImage(key: key, image: provider),
              ),
            ),
          );
          reader.start();
          await tester.pump();
          await _frames(tester, 45);
          expect(advances, 0);
          reader.pause('background', true);
          await tester.pump(const Duration(seconds: 20));
          reader.pause('background', false);
          await tester.pump();
          await _frames(tester, 45);
          expect(advances, 0);
          await _frames(tester, 60);
          expect(advances, 1);
          expect(reader.status, AutoReadingStatus.stopped);
          expect(observed, AutoReadingImageState.loading);
          expect(tester.takeException(), isNull);
        } finally {
          reader.stop();
          reader.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('replacing a failed ComicImage starts a fresh loading state', (
    tester,
  ) async {
    final failed = _PendingImage();
    final pending = _PendingImage();
    final key = GlobalKey<ComicImageState>();
    Widget view(ImageProvider image) => MaterialApp(
      home: ComicImage(key: key, image: image),
    );
    await tester.pumpWidget(view(failed));
    failed.result.completeError(StateError('failed image'));
    await tester.pump();
    expect(
      key.currentState!.autoReadingImageState,
      AutoReadingImageState.failed,
    );
    await tester.pumpWidget(view(pending));
    expect(
      key.currentState!.autoReadingImageState,
      AutoReadingImageState.loading,
    );
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
