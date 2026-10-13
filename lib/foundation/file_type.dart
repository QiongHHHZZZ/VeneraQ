import 'package:mime/mime.dart';

class FileType {
  final String ext;
  final String mime;

  const FileType(this.ext, this.mime);

  static FileType fromExtension(String ext) {
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    var mime = lookupMimeType('no-file.$ext') ?? 'application/octet-stream';
    // Android doesn't support some mime types
    mime = switch (mime) {
      'text/javascript' => 'application/octet-stream',
      'application/x-cbr' => 'application/octet-stream',
      _ => mime,
    };
    return FileType(".$ext", mime);
  }
}

final _resolver = MimeTypeResolver()
  // zip
  ..addMagicNumber([0x50, 0x4B], 'application/zip')
  // 7z
  ..addMagicNumber([
    0x37,
    0x7A,
    0xBC,
    0xAF,
    0x27,
    0x1C,
  ], 'application/x-7z-compressed')
  // rar
  ..addMagicNumber([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], 'application/vnd.rar');

int _uint32(List<int> data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

String _fourcc(List<int> data, int offset) =>
    String.fromCharCodes(data.getRange(offset, offset + 4));

bool _isAvif(List<int> data) {
  var offset = 0;
  // Inspect top-level file type metadata, never strings inside media payloads.
  while (offset + 8 <= data.length) {
    var size = _uint32(data, offset);
    final type = _fourcc(data, offset + 4);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > data.length) return false;
      final high = _uint32(data, offset + 8);
      if (high > 0x7fffffff) return false;
      size = high * 0x100000000 + _uint32(data, offset + 12);
      header = 16;
    } else if (size == 0) {
      size = data.length - offset;
    }
    if (size < header || size > data.length - offset) return false;
    if (type == 'ftyp') {
      if (size < header + 8 || (size - header) % 4 != 0) return false;
      bool avif(int at) => const ['avif', 'avis'].contains(_fourcc(data, at));
      if (avif(offset + header)) return true;
      for (var at = offset + header + 8; at + 4 <= offset + size; at += 4) {
        if (avif(at)) return true;
      }
      return false;
    }
    if (type != 'free' && type != 'skip' && type != 'wide') return false;
    offset += size;
  }
  return false;
}

FileType detectFileType(List<int> data, {String? fallbackExtension}) {
  var mime = _isAvif(data)
      ? 'image/avif'
      : _resolver.lookup('no-file', headerBytes: data);
  if ((mime == null || mime == 'application/octet-stream') &&
      fallbackExtension != null) {
    final fallback = FileType.fromExtension(fallbackExtension);
    if (fallback.mime.startsWith('image/')) return fallback;
  }
  var ext = mime == null ? '' : extensionFromMime(mime);
  if (ext == 'jpe') {
    ext = 'jpg';
  }
  return FileType(".$ext", mime ?? 'application/octet-stream');
}
