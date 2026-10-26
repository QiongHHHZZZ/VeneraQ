import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/app.dart';

/// Best-effort cache of comic details, used to paint the details page before
/// the source finishes loading. A broken cache must never block the page: all
/// IO and decode failures simply fall back to a source request.
class ComicDetailsCache {
  ComicDetailsCache._();

  static final instance = ComicDetailsCache._();

  static const _version = 1;

  final _memory = <String, _CacheEntry>{};

  String _key(String sourceKey, String comicId) => '$sourceKey\u0000$comicId';

  File _file(String key) {
    final name = sha256.convert(utf8.encode(key)).toString();
    return File(p.join(App.cachePath, 'comic_details', '$name.json'));
  }

  Future<ComicDetails?> read(String sourceKey, String comicId) async {
    final key = _key(sourceKey, comicId);
    final cached = _memory[key];
    if (cached != null) return cached.details;
    try {
      final file = _file(key);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != _version) return null;
      final savedAt = decoded['savedAt'];
      final details = decoded['details'];
      if (savedAt is! int || details is! Map) return null;
      final comic = ComicDetails.fromJson(Map<String, dynamic>.from(details));
      _memory[key] = _CacheEntry(
        comic,
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
      return comic;
    } catch (_) {
      return null;
    }
  }

  Duration? age(String sourceKey, String comicId) {
    final cached = _memory[_key(sourceKey, comicId)];
    if (cached == null) return null;
    return DateTime.now().difference(cached.savedAt);
  }

  Future<void> write(ComicDetails details) async {
    final key = _key(details.sourceKey, details.comicId);
    final savedAt = DateTime.now();
    _memory[key] = _CacheEntry(details, savedAt);
    try {
      final file = _file(key);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': _version,
          'savedAt': savedAt.millisecondsSinceEpoch,
          'details': _encode(details),
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // Cache writes are best-effort; the fresh result is already in memory.
    }
  }

  void clearMemory() => _memory.clear();

  /// Rebuilds [details] with a different chapter list. Used when a refresh
  /// succeeds without chapters (some sources swallow chapter errors) so a
  /// transient failure does not erase the cached list.
  ComicDetails withChapters(ComicDetails details, ComicChapters chapters) {
    final encoded = _encode(details);
    encoded['chapters'] = chapters.toJson();
    return ComicDetails.fromJson(encoded);
  }

  Map<String, dynamic> _encode(ComicDetails details) => {
    'title': details.title,
    'subtitle': details.subTitle,
    'cover': details.cover,
    'description': details.description,
    'tags': details.tags,
    'chapters': details.chapters?.toJson(),
    'thumbnails': details.thumbnails,
    'sourceKey': details.sourceKey,
    'comicId': details.comicId,
    'isFavorite': details.isFavorite,
    'subId': details.subId,
    'isLiked': details.isLiked,
    'likesCount': details.likesCount,
    'commentCount': details.commentCount,
    'uploader': details.uploader,
    'uploadTime': details.uploadTime,
    'updateTime': details.updateTime,
    'url': details.url,
    'stars': details.stars,
    'maxPage': details.maxPage,
  };
}

class _CacheEntry {
  const _CacheEntry(this.details, this.savedAt);

  final ComicDetails details;

  final DateTime savedAt;
}
