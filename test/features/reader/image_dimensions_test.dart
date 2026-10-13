import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/features/reader/comic_image.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/display_image_provider.dart';
import 'package:venera_next/features/reader/image_dimensions.dart';
import 'package:venera_next/foundation/image_provider/reader_image.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/reader_settings.dart';

class _Provider extends ReaderImageProvider {
  _Provider(this.bytes, {bool resize = false})
    : super(
        'dimensions-${_next++}',
        null,
        'comic',
        'chapter',
        1,
        enableResize: resize,
      );
  static int _next = 0;
  final Future<Uint8List> bytes;
  int loads = 0;
  @override
  Future<Uint8List> load(chunkEvents, checkStop) {
    loads++;
    return bytes;
  }
}

class _RetryProvider extends ReaderImageProvider {
  _RetryProvider() : super('retry-dimensions', null, 'comic', 'chapter', 1);
  int loads = 0;
  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    if (++loads == 1) throw Exception('Invalid Status Code: 404');
    return img.encodePng(img.Image(width: 24, height: 48));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dimension setting defaults off and follows scope precedence', () {
    expect(ReaderSettings.resolve(global: {}).showImageDimensions, isFalse);
    expect(
      ReaderSettings.resolve(
        global: {'showImageDimensions': true},
      ).showImageDimensions,
      isTrue,
    );
    expect(
      ReaderSettings.resolve(
        global: {'showImageDimensions': true},
        device: {'enabled': true, 'showImageDimensions': false},
      ).showImageDimensions,
      isFalse,
    );
    expect(
      ReaderSettings.resolve(
        global: {},
        device: {'enabled': true, 'showImageDimensions': false},
        comic: {'enabled': true, 'showImageDimensions': true},
      ).showImageDimensions,
      isTrue,
    );
  });

  testWidgets(
    'original dimensions survive resized decode, relay and cache hit',
    (tester) async {
      final bytes = img.encodePng(img.Image(width: 2000, height: 2000));
      final original = _Provider(Future.value(bytes), resize: true);
      final work = ImageWork();
      final image = ReaderDisplayImageProvider(original, work);
      Widget view() => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: ReaderImageDimensions(
              image: image,
              child: Image(image: image),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(view());
        for (
          var i = 0;
          i < 80 && find.text('2000 × 2000').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('2000 × 2000'), findsOneWidget);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image!.width, lessThan(2000));
        expect(original.loads, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pumpWidget(view());
        await tester.pump();
        expect(find.text('2000 × 2000'), findsOneWidget);
        expect(original.loads, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final closed = work.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.pump();
        await tester.runAsync(() => closed);
      }
    },
  );

  testWidgets(
    'split images show full dimensions and switching clears stale label',
    (tester) async {
      final first = _Provider(
        Future.value(img.encodePng(img.Image(width: 800, height: 400))),
      );
      final pending = Completer<Uint8List>();
      final second = _Provider(pending.future);
      Widget view(ImageProvider image, {bool enabled = true}) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: ComicImage(
              image: image,
              width: double.infinity,
              splitWideImage: true,
              showImageDimensions: enabled,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(first));
      for (
        var i = 0;
        i < 80 && find.text('800 × 400').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('800 × 400'), findsOneWidget);
      expect(find.text('400 × 800'), findsNothing);
      await tester.pumpWidget(view(first, enabled: false));
      expect(find.byType(ImageDimensionsOverlay), findsNothing);
      await tester.pumpWidget(view(second));
      expect(find.text('800 × 400'), findsNothing);
      pending.complete(img.encodePng(img.Image(width: 40, height: 90)));
      for (var i = 0; i < 80 && find.text('40 × 90').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('40 × 90'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
    },
  );

  testWidgets(
    'overlay preserves image bounds with large text and ignores gestures',
    (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(3)),
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ImageDimensionsOverlay(
                    size: Size(12345, 67890),
                    child: SizedBox(width: 72, height: 100),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(ImageDimensionsOverlay)),
          const Size(72, 100),
        );
        expect(
          find.bySemanticsLabel('Image dimensions: 12345 × 67890 pixels'),
          findsOneWidget,
        );
        await tester.tap(find.byType(ImageDimensionsOverlay));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('dimension observer joins the replacement stream after retry', (
    tester,
  ) async {
    final provider = _RetryProvider();
    final states = <AutoReadingImageState>[];
    final work = ImageWork();
    final image = ReaderDisplayImageProvider(provider, work);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 120,
            height: 120,
            child: ReaderImageDimensions(
              image: image,
              onLoadState: states.add,
              builder: (reload) =>
                  TextButton(onPressed: reload, child: const Text('Retry')),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('24 × 48'), findsNothing);
      expect(states, [
        AutoReadingImageState.loading,
        AutoReadingImageState.failed,
      ]);
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 80 && find.text('24 × 48').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('24 × 48'), findsOneWidget);
      expect(provider.loads, 2);
      expect(states, [
        AutoReadingImageState.loading,
        AutoReadingImageState.failed,
        AutoReadingImageState.loading,
        AutoReadingImageState.ready,
      ]);
    } finally {
      await tester.pumpWidget(const SizedBox());
      final closed = work.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pump();
      await tester.runAsync(() => closed);
    }
  });
}
