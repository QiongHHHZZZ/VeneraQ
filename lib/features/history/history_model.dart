import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/history_contract.dart';
import 'package:venera_next/foundation/translations.dart';

class History implements Comic, ReadState {
  HistoryType type;

  DateTime time;

  @override
  String title;

  @override
  String subtitle;

  @override
  String cover;

  /// index of chapters. 1-based.
  int ep;

  /// index of pages. 1-based.
  int page;

  /// index of chapter groups. 1-based.
  /// If [group] is not null, [ep] is the index of chapter in the group.
  int? group;

  /// Last read names remain available when the source or chapter list is gone.
  String? chapterTitle;
  String? groupTitle;

  @override
  String id;

  /// readEpisode is a set of episode numbers that have been read.
  /// For normal chapters, it is a set of chapter numbers.
  /// For grouped chapters, it is a set of strings in the format of "group_number-chapter_number".
  /// 1-based.
  @override
  Set<String> readEpisode;

  @override
  int? maxPage;

  /// Cumulative foreground reading time for this comic.
  int readDurationMs;

  History({
    required this.type,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.ep,
    required this.page,
    required this.id,
    required this.readEpisode,
    required this.maxPage,
    required this.readDurationMs,
    this.group,
    this.chapterTitle,
    this.groupTitle,
  });

  /// Detached values for a submitted storage operation, including read keys.
  History copy() => History(
    type: type,
    time: time,
    title: title,
    subtitle: subtitle,
    cover: cover,
    ep: ep,
    page: page,
    id: id,
    readEpisode: Set.of(readEpisode),
    maxPage: maxPage,
    readDurationMs: readDurationMs,
    group: group,
    chapterTitle: chapterTitle,
    groupTitle: groupTitle,
  );

  History.fromModel({
    required HistoryMixin model,
    required this.ep,
    required this.page,
    this.group,
    Set<String>? readChapters,
    DateTime? time,
    this.readDurationMs = 0,
  }) : type = model.historyType,
       title = model.title,
       subtitle = model.subTitle ?? '',
       cover = model.cover,
       id = model.id,
       readEpisode = readChapters ?? <String>{},
       time = time ?? DateTime.now();

  /// The snapshot a reader starts from, given the metadata the source loaded.
  ///
  /// An entry that already carries metadata is returned unchanged, so callers
  /// comparing instances keep their identity. A cleared history leaves only the
  /// durable position, which has no title and no cover; metadata from the
  /// loaded comic is layered underneath it. Writing progress from a bare
  /// position used to re-create the history row without a cover, which is why
  /// a cleared-then-read comic came back as a blank tile.
  static History resume(History? stored, HistoryMixin model) {
    if (stored == null) {
      return History.fromModel(model: model, ep: 0, page: 0);
    }
    if (stored.title.isNotEmpty) return stored;
    return History.fromModel(
      model: model,
      ep: stored.ep,
      page: stored.page,
      group: stored.group,
    )
      ..maxPage = stored.maxPage
      ..chapterTitle = stored.chapterTitle
      ..groupTitle = stored.groupTitle
      ..time = stored.time
      ..readEpisode.addAll(stored.readEpisode);
  }

  History.fromMap(Map<String, dynamic> map)
    : type = HistoryType(map["type"]),
      time = DateTime.fromMillisecondsSinceEpoch(map["time"]),
      title = map["title"],
      subtitle = map["subtitle"],
      cover = map["cover"],
      ep = map["ep"],
      page = map["page"],
      id = map["id"],
      readEpisode = Set<String>.from(
        (map["readEpisode"] as List<dynamic>?)?.toSet() ?? const <String>{},
      ),
      maxPage = map["max_page"],
      group = map['chapter_group'] as int?,
      chapterTitle = map['chapter_title'] as String?,
      groupTitle = map['group_title'] as String?,
      readDurationMs = (map["read_duration_ms"] as num?)?.round() ?? 0;

  @override
  String toString() {
    return 'History{type: $type, time: $time, title: $title, subtitle: $subtitle, cover: $cover, ep: $ep, page: $page, id: $id}';
  }

  @override
  bool operator ==(Object other) {
    return other is History && type == other.type && id == other.id;
  }

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String get description {
    var res = "";
    if (groupTitle?.trim().isNotEmpty == true || group != null) {
      res +=
          '${groupTitle?.trim().isNotEmpty == true ? groupTitle!.trim() : "Group @group".tlParams({"group": group!})} - ';
    }
    if (chapterTitle?.trim().isNotEmpty == true) {
      res += chapterTitle!.trim();
    } else if (ep >= 1) {
      res += "Chapter @ep".tlParams({"ep": ep});
    }
    if (page >= 1) {
      if (res.isNotEmpty) {
        res += " - ";
      }
      res += "Page @page".tlParams({"page": page});
    }
    return res;
  }

  @override
  String? get favoriteId => null;

  @override
  String? get language => null;

  @override
  String get sourceKey => type == ComicType.local
      ? 'local'
      : type.comicSource?.key ?? "Unknown:${type.value}";

  @override
  double? get stars => null;

  @override
  List<String>? get tags => null;

  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError();
  }
}
