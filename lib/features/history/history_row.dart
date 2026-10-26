import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/history_contract.dart';
import 'history_model.dart';

/// Decode the existing SQLite representation after schema migration.
History historyFromRow(Row row) => History(
  type: HistoryType(row['type']),
  time: DateTime.fromMillisecondsSinceEpoch(row['time']),
  title: row['title'],
  subtitle: row['subtitle'],
  cover: row['cover'],
  ep: row['ep'],
  page: row['page'],
  id: row['id'],
  readEpisode: Set<String>.from(
    (row['readEpisode'] as String).split(',').where((entry) => entry != ''),
  ),
  maxPage: row['max_page'],
  group: row['chapter_group'],
  chapterTitle: row['chapter_title'],
  groupTitle: row['group_title'],
  readDurationMs: (row['read_duration_ms'] as num).round(),
);

/// The durable reading position: everything needed to resume, and nothing that
/// belongs to the history list. Deliberately excludes the metadata copy, which
/// only the history row keeps.
class ReadingProgress {
  const ReadingProgress({
    required this.id,
    required this.type,
    required this.ep,
    required this.page,
    required this.time,
    this.maxPage,
    this.group,
    this.chapterTitle,
    this.groupTitle,
  });

  final String id;
  final int type;
  final int ep;
  final int page;
  final DateTime time;
  final int? maxPage;
  final int? group;
  final String? chapterTitle;
  final String? groupTitle;
}

ReadingProgress progressFromRow(Row row) => ReadingProgress(
  id: row['id'] as String,
  type: row['type'] as int,
  ep: row['ep'] as int,
  page: row['page'] as int,
  time: DateTime.fromMillisecondsSinceEpoch(row['time'] as int),
  maxPage: row['max_page'] as int?,
  group: row['chapter_group'] as int?,
  chapterTitle: row['chapter_title'] as String?,
  groupTitle: row['group_title'] as String?,
);

/// A resume target with no metadata copy: the history row that supplied the
/// title and cover has been cleared, but the position still points at a page.
History historyFromProgress(ReadingProgress progress, HistoryType type) =>
    History(
      type: type,
      time: progress.time,
      title: '',
      subtitle: '',
      cover: '',
      ep: progress.ep,
      page: progress.page,
      id: progress.id,
      readEpisode: <String>{},
      maxPage: progress.maxPage,
      readDurationMs: 0,
      group: progress.group,
      chapterTitle: progress.chapterTitle,
      groupTitle: progress.groupTitle,
    );

/// Overlays the durable position onto a listed row whose own copy may be older.
History applyProgress(History history, ReadingProgress progress) {
  history
    ..ep = progress.ep
    ..page = progress.page
    ..maxPage = progress.maxPage
    ..group = progress.group
    ..chapterTitle = progress.chapterTitle
    ..groupTitle = progress.groupTitle;
  return history;
}
