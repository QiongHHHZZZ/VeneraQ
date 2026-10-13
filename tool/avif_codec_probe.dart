// Run with: flutter test --no-pub tool/avif_codec_probe.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('report host AVIF codec capabilities', () async {
    for (final name in [
      'white_1x1.avif',
      'abc_color_irot_alpha_irot.avif',
      'colors-animated-8bpc.avif',
      'colors-animated-8bpc-alpha-exif-xmp.avif',
    ]) {
      ui.Codec? codec;
      final result = <String, Object?>{
        'sample': name,
        'platform': Platform.operatingSystem,
        'supported': false,
      };
      try {
        codec = await ui.instantiateImageCodec(
          await File('test/fixtures/avif/$name').readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        try {
          result.addAll({
            'supported': true,
            'width': frame.image.width,
            'height': frame.image.height,
            'frameCount': codec.frameCount,
          });
        } finally {
          frame.image.dispose();
        }
      } catch (error) {
        result['error'] = error.toString();
      } finally {
        codec?.dispose();
      }
      // Decode failures are probe results, not regression test failures.
      // ignore: avoid_print
      print(jsonEncode(result));
    }
  });
}
