import 'comic_type.dart';

typedef HistoryType = ComicType;

/// Reading state a chapter list needs to tell read from unread chapters.
///
/// Declared here rather than importing the history feature so the comic source
/// models can consume it without a circular dependency.
abstract mixin class ReadState {
  /// Chapter keys the reader has finished. Plain chapters record their number;
  /// grouped chapters record "group-chapter".
  Set<String> get readEpisode;
}

/// Minimal comic metadata required to create or update a reading history item.
abstract mixin class HistoryMixin {
  String get title;

  String? get subTitle;

  String get cover;

  String get id;

  int? get maxPage => null;

  HistoryType get historyType;
}
