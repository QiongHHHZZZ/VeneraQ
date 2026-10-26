/// Chapter read-progress maths shared by the tile badge and the shelf sort.
///
/// Both places need the same answer to "how many chapters are read", so the rule
/// lives here once instead of being re-derived per call site.
library;

/// Chapters in [readEpisode] that fall inside the current chapter total.
///
/// Keys are plain indices ("3") for normal comics and "group-chapter" for
/// grouped ones. A grouped comic may also still carry a stale plain key from
/// before it was grouped, so those are ignored: counting them would inflate the
/// read total and hide unread chapters.
int countReadChapters(Set<String> readEpisode, int chapterCount) {
  if (chapterCount <= 0) return 0;
  var grouped = 0;
  var plain = 0;
  for (final key in readEpisode) {
    if (key.contains('-')) {
      grouped++;
      continue;
    }
    final index = int.tryParse(key);
    if (index == null || index < 1 || index > chapterCount) continue;
    plain++;
  }
  // A grouped list is counted by its grouped keys; one that has both (grouped
  // after being read flat) keeps the larger of the two views.
  return (grouped > 0 ? grouped : plain).clamp(0, chapterCount);
}

/// Chapters still to read, given the read set and the known chapter total.
///
/// Returns null when the total is unknown, which callers render as "no badge"
/// rather than "zero unread".
int? unreadChapterCount(Set<String>? readEpisode, int? chapterCount) {
  if (chapterCount == null || chapterCount <= 0) return null;
  return (chapterCount -
          countReadChapters(readEpisode ?? const {}, chapterCount))
      .clamp(0, chapterCount);
}
