import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/favorites/favorites_repository.dart';
import 'package:venera_next/features/history/history_repository.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import 'legacy_pica_data.dart';

/// Writes an already decoded import to existing databases without notifications.
/// The caller serializes history writes and reconciles manager caches on success.
void commitLegacyPicaData(
  LegacyPicaData data, {
  required String favoritesPath,
  required String historyPath,
  required bool appendFavorites,
  required String Function(List<String>) translateTags,
  required void Function(Object, StackTrace) invalidLink,
}) {
  if (!File(historyPath).existsSync()) {
    throw StateError('History import target does not exist');
  }
  final db = sqlite3.open(favoritesPath, mode: OpenMode.readWrite);
  try {
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('ATTACH DATABASE ? AS imported_history;', [historyPath]);
    for (final schema in ['main', 'imported_history']) {
      final mode = db
          .select('PRAGMA $schema.journal_mode;')
          .first['journal_mode'];
      if (!['delete', 'truncate', 'persist'].contains(mode)) {
        throw StateError(
          'Pica import requires rollback journals: $schema=$mode',
        );
      }
      db.execute('PRAGMA $schema.synchronous = FULL;');
    }
    final favorites = FavoritesRepository(db);
    final history = HistoryRepository(db, schema: 'imported_history');
    // An older history.db has no read-mark table yet; create and backfill it
    // before importing so the marks land in both stores.
    history.initialize();
    runSqliteTransaction(db, () {
      for (final link in data.links) {
        if (favorites.findLinked(link.folder).$1 != null) continue;
        String folder;
        try {
          folder = link.networkFolder;
        } catch (error, stack) {
          invalidLink(error, stack);
          continue;
        }
        favorites.linkFolderToNetwork(link.folder, link.sourceKey, folder);
      }
      final existing = favorites.folderNames().toSet();
      for (final entry in data.folders.entries) {
        if (entry.key.isEmpty) {
          throw const FormatException('Empty favorite folder');
        }
        if (existing.add(entry.key)) favorites.createFolder(entry.key);
        for (final comic in entry.value) {
          favorites.addComic(
            entry.key,
            comic,
            translatedTags: translateTags(comic.tags),
            append: appendFavorites,
          );
        }
      }
      for (final item in data.history) {
        history.importHistory(item);
      }
    }, immediate: true);
  } finally {
    db.dispose();
  }
}
