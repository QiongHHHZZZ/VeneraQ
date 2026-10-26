import 'package:flutter/material.dart';
import 'package:venera_next/components/loading.dart';
import 'images.dart';
import 'chapter_request.dart';
import 'reader_viewport.dart';
import 'package:venera_next/features/reader/reader_page.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'image_read.dart';

import 'gallery_view.dart';
import 'gallery_data.dart';
import 'continuous_data.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/network/request_scope.dart';
import 'continuous_view.dart';

/// Application composition for reader content, view inputs and shell actions.
class ReaderImagesHost extends StatelessWidget {
  const ReaderImagesHost({super.key, required this.reader});
  final ReaderState reader;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ComicSourceManager.current]),
    builder: (context, _) => _buildImages(context),
  );

  Widget _buildImages(BuildContext context) {
    final chapters = reader.createChapterRequest();
    final chapter = reader.chapter;
    final shell = context.readerScaffold;
    bool current() => context.mounted && chapters.isCurrent();
    return ReaderImages(
      key: ValueKey(chapters.identity),
      imageWork: reader.imageWork,
      controller: reader.controller,
      beforeLoad: (scope) async {
        if (!current()) scope.cancel();
        scope.check();
        await reader.prepareLocalPageOrder(
          () => scope.isCancelled || !current(),
        );
        if (!current()) scope.cancel();
        scope.check();
      },
      loadImages: (scope) => chapters.load(chapter, scope),
      prepareMode: () async {
        if (!current()) throw const RequestCancelled();
      },
      onLoading: reader.onReaderContentLoading,
      onCommitted: () {
        if (!current()) return;
        if (reader.jumpToLastPageOnLoad) {
          reader.controller.restorePage(reader.maxPage);
          reader.controller.setJumpToLastPage(false);
        }
      },
      onReady: () {
        if (!current()) return;
        reader.updateHistory();
        reader.onReaderContentReady();
      },
      onSettled: () {
        if (!current()) return;
        reader.updateShell();
      },
      errorBuilder: (context, error, retry) => GestureDetector(
        onTap: () {
          if (current() && shell.mounted && chapters.canInteract()) {
            shell.openOrClose();
          }
        },
        child: SizedBox.expand(
          child: NetworkError(message: error, retry: retry),
        ),
      ),
      contentBuilder: (context, content) =>
          _buildContent(context, content, chapters),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ReaderContentState content,
    ReaderChapterRequest chapters,
  ) {
    final chapterNavigation = reader.createChapterNavigationRequest(content);
    final shell = context.readerScaffold;
    final mode = reader.mode;
    ReaderImageViewController? originalViewport;
    void viewportChanged(ReaderImageViewController viewport, bool attached) {
      if (attached) originalViewport = viewport;
      reader.onViewportChanged(viewport, attached);
    }

    bool current() => context.mounted && shell.mounted && chapters.isCurrent();
    bool canAct() =>
        current() &&
        chapters.canInteract() &&
        reader.mode == mode &&
        originalViewport != null &&
        identical(reader.imageViewController, originalViewport);

    if (reader.mode.isGallery) {
      final preferences = reader.preferences;
      final source = reader.type.comicSource;
      return ReaderGalleryView(
        imageWork: reader.imageWork,
        key: Key('${reader.mode.key}_${reader.imagesPerPage}'),
        data: ReaderGalleryData(
          content: content,
          layout: reader.pageLayout,
          vertical: reader.mode == ReaderMode.galleryTopToBottom,
          reverse: reader.mode == ReaderMode.galleryRightToLeft,
          firstChapter: reader.isFirstChapterOfGroup,
          lastChapter: reader.isLastChapterOfGroup,
          preloadCount: GlobalPreferenceStore(
            appdata.settings,
          ).read(NetworkPreferences.preloadImageCount).toInt(),
          pageAnimation: preferences.enablePageAnimation,
          sourceKey: source?.key,
          comicId: reader.cid,
          chapterId: reader.eid,
        ),
        navigation: reader.controller,
        onViewportChanged: viewportChanged,
        onReady: () => reader.chapterNavigation.report(chapterNavigation, 0),
        onPageReported: () {
          if (!canAct() || !identical(reader.controller.content, content)) {
            return;
          }
          reader.updateShell();
        },
        readerSize: () => reader.size,
        readImage: readReaderImageBytes,
      );
    } else {
      final preferences = reader.preferences;
      return ReaderContinuousView(
        imageWork: reader.imageWork,
        key: Key(reader.mode.key),
        data: ReaderContinuousData(
          vertical: reader.mode.isTopToBottom,
          reverse: false,
          crossChapter: reader.crossChapterFlow,
          firstChapter: reader.isFirstChapterOfGroup,
          lastChapter: reader.isLastChapterOfGroup,
          maxChapter: reader.maxChapter,
          preloadCount: GlobalPreferenceStore(
            appdata.settings,
          ).read(NetworkPreferences.preloadImageCount).toInt(),
          limitImageWidth: preferences.limitImageWidth == true,
          sourceKey: reader.type.comicSource?.key,
          comicId: reader.cid,
        ),
        navigation: reader.controller,
        loadChapter: chapters.load,
        chapterId: chapters.chapterId,
        chapterTitle: (chapter) =>
            chapters.chapterTitle(chapter) ?? '${'Chapter'.tl} $chapter',
        onViewportChanged: viewportChanged,
        onUpdate: () {
          if (current()) reader.updateShell();
        },
        onFloatingButton: (value) =>
            reader.chapterNavigation.report(chapterNavigation, value),
        onContentLoading: (loading) {
          if (!current()) return;
          if (loading) {
            reader.onReaderContentLoading();
          } else {
            reader.onReaderContentReady();
          }
        },
        onPreviousError: (error, stack) => Log.error(
          'Reader',
          'Failed to load previous chapter: $error',
          stack,
        ),
        onNavigationError: (chapter, error, stack) {
          Log.error('Reader', 'Failed to load chapter $chapter: $error', stack);
          if (canAct()) context.showMessage(message: error.toString());
        },
        readerSize: () => reader.size,
        readImage: readReaderImageBytes,
      );
    }
  }
}
