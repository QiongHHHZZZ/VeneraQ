import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/file_type.dart';

List<int> uint32(int n) => [
  (n >> 24) & 255,
  (n >> 16) & 255,
  (n >> 8) & 255,
  n & 255,
];
List<int> ftyp(
  String major,
  List<String> brands, {
  bool wide = false,
  bool toEnd = false,
}) {
  final payload = [
    ...major.codeUnits,
    ...uint32(0),
    for (final brand in brands) ...brand.codeUnits,
  ];
  final size = payload.length + (wide ? 16 : 8);
  return [
    ...uint32(
      wide
          ? 1
          : toEnd
          ? 0
          : size,
    ),
    ...'ftyp'.codeUnits,
    if (wide) ...[...uint32(0), ...uint32(size)],
    ...payload,
  ];
}

void main() {
  test('AVIF major and compatible brands work with variable box sizes', () {
    for (final header in [
      ftyp('avif', []),
      ftyp('avif', ['mif1', 'miaf', 'MA1B']),
      ftyp('mif1', ['miaf', 'avif']),
      ftyp('avis', ['msf1', 'iso8']),
      ftyp('msf1', ['iso8', 'avis']),
      ftyp('mif1', ['avif'], wide: true),
      ftyp('avif', [], toEnd: true),
      [...uint32(8), ...'free'.codeUnits, ...ftyp('avif', [])],
    ]) {
      final type = detectFileType(header);
      expect((type.ext, type.mime), ('.avif', 'image/avif'));
    }
  });

  test(
    'truncated boxes, minor versions and payload strings do not claim AVIF',
    () {
      final minorVersion = ftyp('mif1', []);
      minorVersion.setRange(12, 16, 'avif'.codeUnits);
      for (final header in [
        [0, 0, 0, 24, ...'ftypavif'.codeUnits],
        [0, 0, 0, 7, ...'ftypavif'.codeUnits],
        [0, 0, 0, 1, ...'ftyp'.codeUnits],
        [...uint32(17), ...'ftypavif'.codeUnits, ...uint32(0), 1],
        [
          ...ftyp('isom', ['mp41']),
          ...'avif'.codeUnits,
        ],
        minorVersion,
        [
          ...uint32(12),
          ...'mdat'.codeUnits,
          ...'avif'.codeUnits,
          ...ftyp('avif', []),
        ],
      ]) {
        expect(detectFileType(header).mime, isNot('image/avif'));
      }
    },
  );

  test(
    'actual AVIF still, sequence, alpha and rotation fixtures identify correctly',
    () {
      for (final name in [
        'white_1x1.avif',
        'colors-animated-8bpc.avif',
        'colors-animated-8bpc-alpha-exif-xmp.avif',
        'abc_color_irot_alpha_irot.avif',
      ]) {
        expect(
          detectFileType(
            File('test/fixtures/avif/$name').readAsBytesSync(),
          ).mime,
          'image/avif',
          reason: name,
        );
      }
    },
  );

  test('known image headers take precedence over a URL extension fallback', () {
    final type = detectFileType([
      0xff,
      0xd8,
      0xff,
      0xe0,
    ], fallbackExtension: '.avif');
    expect((type.ext, type.mime), ('.jpg', 'image/jpeg'));
  });
}
