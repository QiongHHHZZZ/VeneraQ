import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'page_layout.dart';

/// Map a loaded viewport to the existing persisted history coordinates.
/// The caller gates loading and owns persistence scheduling.
void applyReaderHistoryProgress({
  required History history,
  required int page,
  required int imageCount,
  required int chapter,
  required ComicChapters? chapters,
  required ReaderPageLayout layout,
  required DateTime time,
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
  if (chapters?.isGrouped ?? false) {
    final position = chapters!.positionAt(chapter);
    history.readEpisode.add(position.historyKey);
    history.ep = position.chapter;
    history.group = position.group;
  } else {
    history.readEpisode.add(chapter.toString());
    history.ep = chapter;
    // Preserve the existing ungrouped update contract: do not rewrite group.
  }
  history.time = time;
}
