import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'favorite_models.dart';

/// Decode legacy persisted fields without normalizing their timestamp or tags.
FavoriteItem favoriteItemFromRow(Row row) => FavoriteItem.withTime(
  name: row['name'],
  author: row['author'],
  type: ComicType(row['type']),
  tags: (row['tags'] as String).split(',')..remove(''),
  id: row['id'],
  coverPath: row['cover_path'],
  time: row['time'],
);

FavoriteItemWithUpdateInfo favoriteItemWithUpdateInfoFromRow(Row row) =>
    FavoriteItemWithUpdateInfo(
      favoriteItemFromRow(row),
      row['last_update_time'],
        row['last_check_time'],
      // Older folders may predate the column; SELECT * omits it there.
      chapterCount: _optionalInt(row, 'chapter_count'),
    );

int? _optionalInt(Row row, String column) {
  if (!row.keys.contains(column)) return null;
  final value = row[column];
  return value is int ? value : null;
}
