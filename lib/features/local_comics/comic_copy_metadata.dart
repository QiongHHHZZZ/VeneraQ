import 'dart:convert';

import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/comic_type.dart';

import 'local_comic_model.dart';

// SQLite persists milliseconds, while the source may carry microseconds or a
// different timezone. Compare persisted values, retaining chapter/tag order.
String _storedMetadata(LocalComic comic) => jsonEncode({
  'title': comic.title,
  'subtitle': comic.subtitle,
  'tags': comic.tags,
  'chapters': comic.chapters?.toJson(),
  'cover': comic.cover,
  'type': comic.comicType.value,
  'downloadedChapters': comic.downloadedChapters,
  'createdAt': comic.createdAt.millisecondsSinceEpoch,
});

bool matchesComicCopyMetadata(LocalComic intended, LocalComic registered) =>
    _storedMetadata(intended) == _storedMetadata(registered);

/// Bind cleanup to the current row, not title or a guessed folder association.
String comicCopyRegistration(LocalComic comic) => jsonEncode({
  'id': comic.id,
  'directory': comic.directory,
  'metadata': _storedMetadata(comic),
});

/// Rebuild the comic an interrupted import meant to register.
///
/// Only a library relocation reads this now: it decodes the intent to compare
/// it against the row that is about to move. The folder the import would have
/// filed it into is not part of that comparison and is no longer returned.
LocalComic decodeComicCopyMetadata(String encoded, String directory) {
  final data = jsonDecode(encoded);
  if (data is! Map<String, dynamic> ||
      data['version'] != 1 ||
      data['title'] is! String ||
      data['subtitle'] is! String ||
      data['cover'] is! String ||
      data['type'] is! int ||
      data['createdAt'] is! String) {
    throw const FormatException('Invalid comic copy metadata');
  }
  final tags = List<String>.from(data['tags'] as List);
  final downloaded = List<String>.from(data['downloadedChapters'] as List);
  final chapters = data['chapters'];
  if (chapters != null) {
    if (chapters is! Map<String, dynamic> ||
        !chapters.values.every((value) => value is String) &&
            !chapters.values.every(
              (value) =>
                  value is Map<String, dynamic> &&
                  value.values.every((title) => title is String),
            )) {
      throw const FormatException('Invalid comic copy chapters');
    }
  }
  final parsedChapters = ComicChapters.fromJsonOrNull(chapters);
  // Recovery must never turn metadata into an absolute/traversing file path.
  void relativePath(String value) {
    final segments = value.replaceAll('\\', '/').split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..') ||
        value.contains(':')) {
      throw const FormatException('Invalid copied comic relative path');
    }
  }

  relativePath(data['cover'] as String);
  for (final chapter in [...?parsedChapters?.ids, ...downloaded]) {
    relativePath(chapter);
  }
  return LocalComic(
    id: '0',
    title: data['title'] as String,
    subtitle: data['subtitle'] as String,
    tags: tags,
    directory: directory,
    chapters: parsedChapters,
    cover: data['cover'] as String,
    comicType: ComicType(data['type'] as int),
    downloadedChapters: downloaded,
    createdAt: DateTime.parse(data['createdAt'] as String),
  );
}
