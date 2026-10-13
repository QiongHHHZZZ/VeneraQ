"""Measure production Image block copies in Dart AOT without loading codecs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--revision', help='Git revision to compare; defaults to working tree')
parser.add_argument('--runs', type=int, default=5)
args = parser.parse_args()
if args.runs < 1:
    parser.error('--runs must be positive')
repo = Path(__file__).resolve().parents[1]
path = 'lib/foundation/image_processing.dart'
if args.revision:
    source = subprocess.check_output(['git', 'show', f'{args.revision}:{path}'], cwd=repo).decode('utf-8')
else:
    source = (repo / path).read_text(encoding='utf-8')
image = source[source.index('class Image {'):source.index('  Uint8List encodePng()')]
image = image[:image.index('  static Future<Image> decodeImage(')] + image[image.index('  Image copyRange('):]
benchmark = r'''
void main() {
  const width = 1600, height = 2400, count = 16, stripHeight = height ~/ count;
  final pixels = Uint32List(width * height);
  for (var i = 0; i < pixels.length; i++) { pixels[i] = i * 13; }
  final original = Image(pixels, width, height);
  final destination = Image.empty(width, height);
  void unscramble() {
    for (var strip = 0; strip < count; strip++) {
      destination.fillImageRangeAt(0, strip * stripHeight, original,
        0, (count - strip - 1) * stripHeight, width, stripHeight);
    }
  }
  for (var i = 0; i < 5; i++) { unscramble(); }
  final clock = Stopwatch()..start();
  for (var i = 0; i < 100; i++) { unscramble(); }
  clock.stop();
  var checksum = 2166136261;
  for (var i = 0; i < pixels.length; i++) {
    final row = i ~/ width;
    final sourceRow = (count - 1 - row ~/ stripHeight) * stripHeight + row % stripHeight;
    final actual = destination._data[i];
    if (actual != pixels[sourceRow * width + i % width]) { throw StateError('wrong pixel $i'); }
    checksum = ((checksum ^ actual) * 16777619) & 0xFFFFFFFF;
  }
  print(jsonEncode({'millisecondsPerImage': clock.elapsedMicroseconds / 100000,
    'checksum': checksum}));
}
'''
dart = shutil.which('dart')
if not dart:
    raise SystemExit('dart executable not found')
with tempfile.TemporaryDirectory(prefix='venera-image-copy-') as folder:
    root = Path(folder).resolve()
    probe = root / 'copy.dart'
    executable = root / ('copy.exe' if os.name == 'nt' else 'copy')
    probe.write_text("import 'dart:typed_data';\nimport 'dart:convert';\n" + image + '}\n' + benchmark, encoding='utf-8')
    subprocess.run([dart, 'compile', 'exe', str(probe), '-o', str(executable)], check=True, cwd=repo, stdout=subprocess.DEVNULL)
    results = [json.loads(subprocess.check_output([str(executable)], cwd=repo)) for _ in range(args.runs)]
    if len({r['checksum'] for r in results}) != 1:
        raise SystemExit('inconsistent output pixels')
    print(json.dumps({'revision': args.revision or 'working-tree', 'width':1600, 'height':2400, 'strips':16,
        'runs':results, 'medianMillisecondsPerImage':statistics.median(r['millisecondsPerImage'] for r in results)}, indent=2))
