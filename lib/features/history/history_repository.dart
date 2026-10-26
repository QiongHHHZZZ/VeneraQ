import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import 'history_row.dart';
import 'package:sqlite3/sqlite3.dart';
import 'history_model.dart';

/// History schema, queries and writes on a caller-owned connection.
/// The manager owns scheduling, connection lifetime, caching and notifications.
class HistoryRepository {
  HistoryRepository(this.db, {String schema = 'main'})
    : _schema = '"${schema.replaceAll('"', '""')}"';
  final Database db;
  final String _schema;
  String get _table => '$_schema."history"';
  String get _readTable => '$_schema."read_chapters"';
  String get _progressTable => '$_schema."reading_progress"';

  void initialize() {
    db.execute("""
        create table if not exists $_table  (
          id text primary key,
          title text,
          subtitle text,
          cover text,
          time int,
          type int,
          ep int,
          page int,
          readEpisode text,
          max_page int,
          chapter_group int,
          chapter_title text,
          group_title text,
          read_duration_ms integer not null default 0
        );
      """);

    // Read marks used to exist only on the history row, so clearing history
    // erased them. They now live independently and survive both an explicit
    // clear and the retention sweep.
    db.execute("""
        create table if not exists $_readTable (
          id text not null,
          type int not null,
          chapter text not null,
          primary key (id, type, chapter)
        );
      """);

    // The reading position is durable state in its own right: clearing history
    // answers "what did I read recently", not "where was I". Keeping it here
    // means "continue" and the detail page still resume after a clear, and a
    // cleared comic reappears in the list as soon as it is read again.
    db.execute("""
        create table if not exists $_progressTable (
          id text not null,
          type int not null,
          ep int not null default 0,
          page int not null default 0,
          max_page int,
          chapter_group int,
          chapter_title text,
          group_title text,
          time int not null default 0,
          primary key (id, type)
        );
      """);

    var columns = db.select('PRAGMA $_schema.table_info("history");');
    if (!columns.any((element) => element["name"] == "chapter_group")) {
      db.execute("alter table $_table add column chapter_group int;");
    }
    if (!columns.any((element) => element["name"] == "read_duration_ms")) {
      db.execute(
        "alter table $_table add column read_duration_ms integer not null default 0;",
      );
    }
    for (final name in ['chapter_title', 'group_title']) {
      if (!columns.any((element) => element['name'] == name)) {
        db.execute('alter table $_table add column $name text;');
      }
    }
    _migrateReadMarks();
    _migrateProgress();
  }

  /// Copies any position still recorded only on a history row into its own
  /// table. Idempotent, so an interrupted migration simply finishes next start.
  void _migrateProgress() {
    final rows = db.select('''
      select id, type, ep, page, max_page, chapter_group, chapter_title,
             group_title, time from $_table;
    ''');
    if (rows.isEmpty) return;
    runSqliteTransaction(db, () {
      for (final row in rows) {
        db.execute(
          'insert or ignore into $_progressTable '
          '(id, type, ep, page, max_page, chapter_group, chapter_title, '
          'group_title, time) values (?, ?, ?, ?, ?, ?, ?, ?, ?);',
          [
            row['id'],
            row['type'],
            row['ep'],
            row['page'],
            row['max_page'],
            row['chapter_group'],
            row['chapter_title'],
            row['group_title'],
            row['time'],
          ],
        );
      }
    });
  }

  /// Copies any mark still recorded only on a history row into its own table.
  ///
  /// Existing installations carry their marks in `history.readEpisode`. The
  /// copy is additive and idempotent, so a partially migrated database simply
  /// finishes on the next start instead of losing the rows already moved.
  void _migrateReadMarks() {
    final rows = db.select('''
      select id, type, readEpisode from $_table
      where readEpisode is not null and readEpisode != '';
    ''');
    if (rows.isEmpty) return;
    runSqliteTransaction(db, () {
      for (final row in rows) {
        final id = row['id'] as String;
        final type = row['type'] as int;
        for (final key in (row['readEpisode'] as String).split(',')) {
          if (key.isEmpty) continue;
          db.execute(
            'insert or ignore into $_readTable (id, type, chapter) values (?, ?, ?);',
            [id, type, key],
          );
        }
      }
    });
  }

  List<History> getAll() {
    var res = db.select("""
      select * from $_table
      order by time DESC;
    """);
    return res.map((element) => historyFromRow(element)).toList();
  }

  /// 获取最近阅读的漫画
  List<History> getRecent() {
    var res = db.select("""
      select * from $_table
      order by time DESC
      limit 20;
    """);
    return res.map((element) => historyFromRow(element)).toList();
  }

  /// 获取历史记录的数量
  int count() {
    var res = db.select("""
      select count(*) AS total from $_table;
    """);
    return res.first['total'] as int;
  }

  /// Where the reader left off, whether or not a history row still exists.
  ///
  /// The position lives in its own table, so this keeps answering after the
  /// history list was cleared. Metadata (title, cover) is only available while
  /// the history row survives; callers that need it check [findListed].
  ReadingProgress? findProgress(String id, int type) {
    final rows = db.select(
      'select * from $_progressTable where id = ? and type = ?;',
      [id, type],
    );
    if (rows.isEmpty) return null;
    return progressFromRow(rows.first);
  }

  /// Everything the reader needs to resume: the durable position, plus the
  /// metadata copy when a history row still exists.
  ///
  /// Returns null only when neither record knows this comic, which is why a
  /// cleared comic still resumes at the saved page instead of starting over.
  History? find(String id, int type) {
    var res = db.select(
      """
      select * from $_table
      where id == ? and type == ?;
    """,
      [id, type],
    );
    final progress = findProgress(id, type);
    if (res.isEmpty) {
      return progress == null
          ? null
          : historyFromProgress(progress, ComicType(type));
    }
    final listed = historyFromRow(res.first);
    if (progress == null) return listed;
    // The progress table is the source of truth for position; the row above
    // may predate the last write if they ever disagree.
    return applyProgress(listed, progress);
  }

  /// The history row only, used by the list that shows title and cover.
  History? findListed(String id, int type) {
    final res = db.select(
      'select * from $_table where id == ? and type == ?;',
      [id, type],
    );
    return res.isEmpty ? null : historyFromRow(res.first);
  }

  /// Read marks for one comic, independent of whether a history row exists.
  Set<String> readChapters(String id, int type) => db
      .select(
        'select chapter from $_readTable where id = ? and type = ?;',
        [id, type],
      )
      .map((row) => row['chapter'] as String)
      .toSet();

  /// Every stored mark, so the reader can answer without a per-comic query.
  Map<(String, int), Set<String>> allReadChapters() {
    final result = <(String, int), Set<String>>{};
    for (final row in db.select('select id, type, chapter from $_readTable;')) {
      final key = (row['id'] as String, row['type'] as int);
      (result[key] ??= <String>{}).add(row['chapter'] as String);
    }
    return result;
  }

  /// Replaces the stored marks for one comic with [chapters].
  void writeReadChapters(String id, int type, Set<String> chapters) =>
      runSqliteTransaction(db, () {
        db.execute(
          'delete from $_readTable where id = ? and type = ?;',
          [id, type],
        );
        for (final chapter in chapters) {
          db.execute(
            'insert or ignore into $_readTable (id, type, chapter) values (?, ?, ?);',
            [id, type, chapter],
          );
        }
        // The history row keeps a copy so older builds still show read marks
        // after an export/import round trip; it is a mirror, not the source.
        db.execute(
          'update $_table set readEpisode = ? where id = ? and type = ?;',
          [chapters.join(','), id, type],
        );
      }, immediate: true);

  void removeReadChapters(String id, int type) => db.execute(
    'delete from $_readTable where id = ? and type = ?;',
    [id, type],
  );

  /// Removes the history rows matching [shouldDelete], like [clear]: this backs
  /// the "clear unfavorited" action, so the durable position and read marks are
  /// kept. The entries simply stop being listed.
  void deleteWhere(bool Function(String id, int type) shouldDelete) =>
      runSqliteTransaction(db, () {
        final idAndTypes = db.select("""
      select id, type from $_table;
    """);
        for (var element in idAndTypes) {
          final id = element["id"] as String;
          final type = element["type"] as int;
          if (shouldDelete(id, type)) {
            db.execute(
              """
          delete from $_table
          where id == ? and type == ?;
        """,
              [id, type],
            );
          }
        }
      });

  /// Moves one history entry to a new source identity.
  ///
  /// Reading progress (`ep`, `page`), metadata and the durable read marks are
  /// preserved; only the identity columns change. Returns false when there was
  /// no entry to move.
  bool switchSource(String oldId, int oldType, String newId, int newType) {
    final existing = find(oldId, oldType);
    if (existing == null) return false;
    // A row may already exist under the new identity; replacing it keeps the
    // primary key unique while preserving the progress being moved over.
    remove(newId, newType);
    runSqliteTransaction(db, () {
      db.execute(
        'UPDATE $_table SET id = ?, type = ? WHERE id = ? AND type = ?;',
        [newId, newType, oldId, oldType],
      );
      db.execute(
        'UPDATE $_readTable SET id = ?, type = ? WHERE id = ? AND type = ?;',
        [newId, newType, oldId, oldType],
      );
      db.execute(
        'UPDATE $_progressTable SET id = ?, type = ? WHERE id = ? AND type = ?;',
        [newId, newType, oldId, oldType],
      );
    }, immediate: true);
    return true;
  }

  /// Removes one history row along with its durable records.
  ///
  /// This is the deliberate "forget this comic" action from the history page,
  /// so unlike [clear] it discards the position and read marks too; keeping
  /// them would make the entry reappear as soon as the comic was reopened.
  void remove(String id, int type) {
    runSqliteTransaction(db, () {
      db.execute('delete from $_table where id = ? and type = ?;', [id, type]);
      db.execute(
        'delete from $_readTable where id = ? and type = ?;',
        [id, type],
      );
      db.execute(
        'delete from $_progressTable where id = ? and type = ?;',
        [id, type],
      );
    }, immediate: true);
  }

  void removeMany(Iterable<(String, int)> identities) =>
      runSqliteTransaction(db, () {
        for (final (id, type) in identities) {
          remove(id, type);
        }
      });

  /// Removes history rows only. The durable read marks and reading position
  /// live in their own tables and deliberately survive: clearing history is a
  /// statement about "what did I read recently", not about forgetting where the
  /// reader was or which chapters are finished.
  void clearBefore(int cutoff) {
    db.execute(
      """
      delete from $_table
      where time < ?;
    """,
      [cutoff],
    );
  }

  /// Removes every history row, keeping the durable read marks and position.
  void clear() => db.execute("delete from $_table;");

  /// Identities that still have a history row. Only the listed entries carry
  /// title and cover; use [knownIdentities] to include comics whose position
  /// survived a clear.
  List<(String, int)> identities({String? id}) => db
      .select(
        id == null
            ? 'select id, type from $_table;'
            : 'select id, type from $_table where id = ?;',
        id == null ? const [] : [id],
      )
      .map((row) => (row['id'] as String, row['type'] as int))
      .toList();

  /// Every identity the store can still resume, including ones whose history
  /// row was cleared but whose durable position remains.
  List<(String, int)> knownIdentities({String? id}) {
    final result = <(String, int)>{...identities(id: id)};
    final rows = db.select(
      id == null
          ? 'select id, type from $_progressTable;'
          : 'select id, type from $_progressTable where id = ?;',
      id == null ? const [] : [id],
    );
    for (final row in rows) {
      result.add((row['id'] as String, row['type'] as int));
    }
    return result.toList();
  }

  String get _insertHistorySql =>
      """
        insert or replace into $_table (id, title, subtitle, cover, time, type, ep, page, readEpisode, max_page, chapter_group, chapter_title, group_title)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """;

  /// Metadata refreshes never replace progress or recreate deleted records.
  bool updateMetadata(
    String id,
    int type, {
    String? title,
    String? subtitle,
    String? cover,
  }) {
    final fields = <String, String>{
      'title': ?title,
      'subtitle': ?subtitle,
      'cover': ?cover,
    };
    if (fields.isEmpty) return false;
    db.execute(
      'UPDATE $_table SET ${fields.keys.map((field) => '$field = ?').join(', ')} '
      'WHERE id = ? AND type = ?;',
      [...fields.values, id, type],
    );
    return db.updatedRows > 0;
  }

  String get _updateHistorySql =>
      """
        update $_table set
          time = ?,
          ep = ?,
          page = ?,
          readEpisode = ?,
          max_page = ?,
          chapter_group = ?,
          chapter_title = ?,
          group_title = ?
        where id = ? and type = ?;
      """;

  // Legacy databases do not consistently expose a single-column UNIQUE(id).
  void writeProgress(History item) =>
      _writeHistory(item, replaceMetadata: false);

  /// Imports deliberately replace metadata as well as progress. Duration keeps
  /// the existing import policy and is not replaced by a progress snapshot.
  void importHistory(History item) =>
      _writeHistory(item, replaceMetadata: true);

  void _writeHistory(History item, {required bool replaceMetadata}) {
    runSqliteTransaction(db, () {
      final marks = _storeReadChapters(item, replace: replaceMetadata);
      _storeProgress(item);
      db.execute(_updateHistorySql, [
        item.time.millisecondsSinceEpoch,
        item.ep,
        item.page,
        marks.join(','),
        item.maxPage,
        item.group,
        item.chapterTitle,
        item.groupTitle,
        item.id,
        item.type.value,
      ]);
      if (db.updatedRows == 0) {
        db.execute(_insertHistorySql, [
          item.id,
          item.title,
          item.subtitle,
          item.cover,
          item.time.millisecondsSinceEpoch,
          item.type.value,
          item.ep,
          item.page,
          marks.join(','),
          item.maxPage,
          item.group,
          item.chapterTitle,
          item.groupTitle,
        ]);
      } else if (replaceMetadata) {
        updateMetadata(
          item.id,
          item.type.value,
          title: item.title,
          subtitle: item.subtitle,
          cover: item.cover,
        );
      }
    }, immediate: true);
  }

  /// Writes the position to its own table, which clearing history never
  /// touches. Replace rather than merge: the newest snapshot is the position.
  void _storeProgress(History item) {
    db.execute(
      'insert or replace into $_progressTable '
      '(id, type, ep, page, max_page, chapter_group, chapter_title, '
      'group_title, time) values (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        item.id,
        item.type.value,
        item.ep,
        item.page,
        item.maxPage,
        item.group,
        item.chapterTitle,
        item.groupTitle,
        item.time.millisecondsSinceEpoch,
      ],
    );
  }

  /// Merge or replace the snapshot's marks, then return the stored set.
  ///
  /// A progress write may carry fewer marks than are already stored (the reader
  /// holds a snapshot from before a batch edit), so it merges rather than
  /// replaces; only an explicit unread action removes a mark. An import is the
  /// authoritative copy of another device, so it replaces wholesale. The
  /// history row stores the resulting set so an export still carries it.
  Set<String> _storeReadChapters(History item, {required bool replace}) {
    if (replace) {
      db.execute(
        'delete from $_readTable where id = ? and type = ?;',
        [item.id, item.type.value],
      );
    }
    for (final chapter in item.readEpisode) {
      db.execute(
        'insert or ignore into $_readTable (id, type, chapter) values (?, ?, ?);',
        [item.id, item.type.value, chapter],
      );
    }
    return readChapters(item.id, item.type.value);
  }
}
