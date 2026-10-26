import 'favorites_repository.dart';

/// Chapter totals across every favorite folder.
///
/// This used to track which comics had a new chapter. That flag is gone, so the
/// service now only carries the totals, which the unread badge is derived from.
class FavoriteUpdatesService {
  FavoriteUpdatesService({required this.repository, required this.folders});

  final FavoritesRepository Function() repository;
  final List<String> Function() folders;
  Map<(String, int), int> _chapterCounts = {};
  List<String> _loadedFolders = const [];

  void clear() {
    _chapterCounts = {};
    _loadedFolders = const [];
  }

  void refresh() {
    final selected = folders();
    if (selected.isEmpty) {
      clear();
      return;
    }
    _chapterCounts = repository().chapterCounts(selected);
    _loadedFolders = List<String>.of(selected);
  }

  /// Chapter total from the last check, or null when never checked.
  int? chapterCountFor(String id, int type) =>
      _loadedFolders.isEmpty ? null : _chapterCounts[(id, type)];

  /// Records the total reported by one committed check.
  void recordCommittedUpdate(
    String targetFolder,
    String id,
    int type, {
    int? chapterCount,
  }) {
    if (!_loadedFolders.contains(targetFolder)) {
      // A folder created after the last refresh must not lose its totals.
      refresh();
      return;
    }
    // The check already knows the total; publishing it here keeps the badge in
    // step without waiting for another database read.
    if (chapterCount != null) _chapterCounts[(id, type)] = chapterCount;
  }
}
