import 'package:venera_next/foundation/history_contract.dart';

/// Chapter read marks that no longer need a reading-history row to exist.
///
/// Clearing history answers "what did I read recently"; it does not answer
/// which chapters are finished. Marks therefore live in their own table and
/// survive an explicit clear and the retention sweep, while the chapter list,
/// the shelf badge and "continue" reach them through [ReadState].
class ReadChapters implements ReadState {
  ReadChapters([Iterable<String> chapters = const []])
    : readEpisode = Set<String>.of(chapters);

  @override
  final Set<String> readEpisode;

  /// A fresh empty set per call: callers mutate what they receive, so a shared
  /// static instance would leak marks between comics.
  factory ReadChapters.empty() => ReadChapters();

  bool get isEmpty => readEpisode.isEmpty;

  bool get isNotEmpty => readEpisode.isNotEmpty;

  ReadChapters detached() => ReadChapters(readEpisode);

  @override
  bool operator ==(Object other) =>
      other is ReadChapters &&
      other.readEpisode.length == readEpisode.length &&
      other.readEpisode.containsAll(readEpisode);

  @override
  int get hashCode => Object.hashAllUnordered(readEpisode);

  @override
  String toString() => 'ReadChapters(${readEpisode.join(',')})';
}
