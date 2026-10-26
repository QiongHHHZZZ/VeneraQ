import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'page_layout.dart';

/// Map a loaded viewport to the existing persisted history coordinates.
/// The caller gates loading and owns persistence scheduling.
///
/// [markRead] decides whether this position finishes the chapter. Opening a
/// chapter only saves the position; the read mark lands when the last page is
/// reached, which is what the library does. Marking on open made every chapter
/// you glanced at look finished.
void applyReaderHistoryProgress({
  required History history,
  required int page,
  required int imageCount,
  required int chapter,
  required ComicChapters? chapters,
  required ReaderPageLayout layout,
  required DateTime time,
  bool markRead = false,
}) {
  history.page = layout.historyImage(page, imageCount);
  history.maxPage = imageCount;
  history.chapterTitle = null;
  history.groupTitle = null;
  if (chapters != null && chapter >= 1 && chapter <= chapters.length) {
    final position = chapters.positionAt(chapter);
    if (position.group case final group?) {
      history.groupTitle = chapters.groups.elementAt(group - 1);
      history.chapterTitle = chapters
          .getGroupByIndex(group - 1)
          .values
          .elementAt(position.chapter - 1);
    } else {
      history.chapterTitle = chapters.allChapters.values.elementAt(chapter - 1);
    }
  }
  // The position is always advanced so closing mid-chapter resumes there; only
  // the read mark waits for the chapter to actually end.
  if (chapters?.isGrouped ?? false) {
    if (markRead) {
      final position = chapters!.positionAt(chapter);
      history.readEpisode.add(position.historyKey);
    }
    final position = chapters!.positionAt(chapter);
    history.ep = position.chapter;
    history.group = position.group;
  } else {
    if (markRead) history.readEpisode.add(chapter.toString());
    history.ep = chapter;
    // Preserve the existing ungrouped update contract: do not rewrite group.
  }
  history.time = time;
}
