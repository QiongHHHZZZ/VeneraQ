import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_memory_info/flutter_memory_info.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/window_frame.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/gesture_host.dart';
import 'package:venera_next/features/reader/gesture_request.dart';
import 'package:venera_next/features/reader/images_host.dart';
import 'package:venera_next/features/reader/image_cache_policy.dart';
import 'package:venera_next/features/reader/reader_session.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/features/reader/history_writer.dart';
import 'package:venera_next/features/reader/exit_guard.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/reader/reader_viewport.dart';
import 'package:venera_next/features/reader/page_order_migration.dart';
import 'chapter_loader.dart';
import 'chapter_request.dart';
import 'package:venera_next/features/reader/image_export.dart';
import 'package:venera_next/features/reader/settings_effects.dart';
import 'package:venera_next/features/reader/chapter_navigation.dart';

import 'package:venera_next/features/reader/page_layout.dart';
import 'package:venera_next/features/reader/history_progress.dart';
import 'package:venera_next/features/reader/scaffold.dart';
import 'shell_host.dart';
import 'progress_navigation.dart';
import 'image_picker.dart';
import 'package:venera_next/features/reader/volume.dart';
import 'package:venera_next/features/reader/volume_controller.dart';
import 'package:venera_next/features/reader/window_controller.dart';
import 'package:venera_next/features/reader/platform_effects.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/reader_settings.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:window_manager/window_manager.dart';

extension ReaderContext on BuildContext {
  ReaderState get reader => findAncestorStateOfType<ReaderState>()!;

  ReaderScaffoldState get readerScaffold =>
      findAncestorStateOfType<ReaderScaffoldState>()!;
}

/// Value identity for captured progress and gesture targets, including mutable chapter maps.
class _ReaderInputTarget {
  const _ReaderInputTarget(this.key, this.ids, this.titles);
  final Object key;
  final List<String>? ids, titles;

  @override
  bool operator ==(Object other) =>
      other is _ReaderInputTarget &&
      other.key == key &&
      listEquals(ids, other.ids) &&
      listEquals(titles, other.titles);

  @override
  int get hashCode => Object.hash(
    key,
    Object.hashAll(ids ?? const []),
    Object.hashAll(titles ?? const []),
  );
}

class Reader extends StatefulWidget {
  const Reader({
    super.key,
    required this.type,
    required this.cid,
    required this.name,
    required this.chapters,
    required this.history,
    required this.onClosed,
    this.initialPage,
    this.initialChapter,
    this.initialChapterGroup,
    required this.author,
    required this.tags,
  });

  final ComicType type;

  final String author;

  final List<String> tags;

  final String cid;

  final String name;

  final ComicChapters? chapters;

  /// Starts from 1, invalid values equal to 1
  final int? initialPage;

  /// Starts from 1, invalid values equal to 1
  final int? initialChapter;

  /// Starts from 1, invalid values equal to 1
  final int? initialChapterGroup;

  final History history;

  final VoidCallback onClosed;

  @override
  State<Reader> createState() => ReaderState();
}

class ReaderState extends State<Reader>
    with ReaderImagePerPageHandler, WidgetsBindingObserver {
  final imageWork = ImageWork();
  final _targetValidity = ValueNotifier(0);
  final _shellChanges = ValueNotifier(0);
  Listenable get shellChanges => _shellChanges;

  void updateShell() {
    if (!_stateDisposed && mounted) _shellChanges.value++;
  }

  void onViewportChanged(ReaderImageViewController viewport, bool attached) {
    viewportBinding.update(viewport, attached);
    // Attachment happens while building content. Refresh input after the tree
    // has installed the viewport, without rebuilding that content subtree.
    WidgetsBinding.instance.addPostFrameCallback((_) => updateShell());
  }

  ReaderImagePickContext? readImagePickContext() {
    if (!mounted || _stateDisposed || _sessionFrozen || _session.isHeld) {
      return null;
    }
    final viewport = imageViewController;
    final currentImages = images;
    if (viewport == null || currentImages == null) return null;
    return ReaderImagePickContext(
      viewport: viewport,
      images: currentImages,
      chapter: chapter,
    );
  }

  ReaderProgressRequest createProgressRequest() {
    final content = controller.content;
    final route = ModalRoute.of(context);
    final viewport = imageViewController;
    final comic = cid, comicType = type, ep = chapter, currentMode = mode;
    final chapters = widget.chapters;
    final ids = chapters?.ids.toList(growable: false);
    final titles = chapters?.titles.toList(growable: false);
    final source = ComicSource.find(comicType.sourceKey);
    final layout = pageLayout;
    final count = maxPage;
    return ReaderProgressRequest(
      identity: _ReaderInputTarget(
        (
          content,
          viewport,
          comic,
          comicType,
          source,
          chapters,
          ep,
          currentMode,
          count,
          layout.imagesPerPage,
          layout.singleImageOnFirstPage,
        ),
        ids,
        titles,
      ),
      page: page,
      maxPage: count,
      chapter: ep,
      maxChapter: maxChapter,
      reversed: currentMode == ReaderMode.galleryRightToLeft,
      isCurrent: () =>
          mounted &&
          !_stateDisposed &&
          !_sessionFrozen &&
          !_session.isHeld &&
          (route?.isCurrent ?? true) &&
          !controller.isDisposed &&
          identical(controller.content, content) &&
          !content.isLoading &&
          viewport != null &&
          identical(imageViewController, viewport) &&
          cid == comic &&
          type == comicType &&
          chapter == ep &&
          mode == currentMode &&
          maxPage == count &&
          pageLayout.imagesPerPage == layout.imagesPerPage &&
          pageLayout.singleImageOnFirstPage == layout.singleImageOnFirstPage &&
          identical(widget.chapters, chapters) &&
          identical(ComicSource.find(comicType.sourceKey), source) &&
          listEquals(chapters?.ids.toList(growable: false), ids) &&
          listEquals(chapters?.titles.toList(growable: false), titles),
      toPage: toPage,
      toChapter: toChapter,
    );
  }

  ReaderGestureRequest? createGestureRequest() {
    if (!mounted || _stateDisposed || _sessionFrozen || _session.isHeld) {
      return null;
    }
    final content = controller.content, viewport = imageViewController;
    final viewportSize = size;
    final route = ModalRoute.of(context);
    final comic = cid,
        comicType = type,
        ep = chapter,
        imagePage = page,
        currentMode = mode;
    final source = ComicSource.find(comicType.sourceKey);
    final sources = ComicSourceManager.current;
    final chapters = widget.chapters;
    final ids = chapters?.ids.toList(growable: false);
    final titles = chapters?.titles.toList(growable: false);
    final settings = preferences;
    final layout = pageLayout;
    bool targetCurrent() =>
        mounted &&
        !_stateDisposed &&
        !_sessionFrozen &&
        !_session.isHeld &&
        !controller.isDisposed &&
        identical(controller.content, content) &&
        identical(imageViewController, viewport) &&
        cid == comic &&
        type == comicType &&
        chapter == ep &&
        page == imagePage &&
        size == viewportSize &&
        mode == currentMode &&
        identical(ComicSource.find(comicType.sourceKey), source) &&
        (sources == null || identical(ComicSourceManager.current, sources)) &&
        identical(widget.chapters, chapters) &&
        listEquals(chapters?.ids.toList(growable: false), ids) &&
        listEquals(chapters?.titles.toList(growable: false), titles) &&
        pageLayout.imagesPerPage == layout.imagesPerPage &&
        pageLayout.singleImageOnFirstPage == layout.singleImageOnFirstPage &&
        preferences.enableTapToTurnPages == settings.enableTapToTurnPages &&
        preferences.reverseTapToTurnPages == settings.reverseTapToTurnPages &&
        preferences.enableDoubleTapToZoom == settings.enableDoubleTapToZoom &&
        preferences.enableLongPressToZoom == settings.enableLongPressToZoom;
    bool current() => targetCurrent() && (route?.isCurrent ?? true);
    void turn(bool forward) {
      if (current() && viewport != null && !content.isLoading) {
        toPage(imagePage + (forward ? 1 : -1));
      }
    }

    return ReaderGestureRequest(
      identity: _ReaderInputTarget(
        (
          content,
          viewport,
          source,
          comic,
          comicType,
          ep,
          imagePage,
          viewportSize,
          currentMode,
          layout.imagesPerPage,
          layout.singleImageOnFirstPage,
          settings.enableTapToTurnPages,
          settings.reverseTapToTurnPages,
          settings.enableDoubleTapToZoom,
          settings.enableLongPressToZoom,
        ),
        ids,
        titles,
      ),
      isCurrent: current,
      isTargetCurrent: targetCurrent,
      targetChanges: Listenable.merge([sources, _targetValidity]),
      viewport: viewport,
      preferences: settings,
      vertical: currentMode.isTopToBottom,
      reversed: currentMode == ReaderMode.galleryRightToLeft,
      canUseImage: !content.isLoading && viewport != null,
      turnPage: turn,
      turnWheel: (forward) {
        if (!current() ||
            viewport == null ||
            content.isLoading ||
            !currentMode.isGallery) {
          return;
        }
        if (!toPage(imagePage + (forward ? 1 : -1)) && current()) {
          if (forward && !isLastChapterOfGroup) toNextChapter();
          if (!forward && !isFirstChapterOfGroup) {
            toPrevChapter(toLastPage: true);
          }
        }
      },
      fullscreen: () {
        if (current()) fullscreen();
      },
      exit: () => current() ? requestExit() : Future.value(),
    );
  }

  @override
  void didUpdateWidget(covariant Reader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _targetValidity.value++;
  }

  ReaderSettingsRequest? createSettingsRequest() {
    if (_sessionFrozen || controller.isDisposed) return null;
    final comic = cid, comicType = type;
    final sourceKey = comicType.sourceKey;
    final source = ComicSource.find(sourceKey);
    return ReaderSettingsRequest(
      comicId: comic,
      sourceKey: sourceKey,
      isCurrent: () =>
          mounted &&
          !_sessionFrozen &&
          !controller.isDisposed &&
          cid == comic &&
          type == comicType &&
          identical(ComicSource.find(sourceKey), source),
      currentMode: () => mode.key,
      applyReaderEffect: (effect) {
        switch (effect) {
          case ReaderSettingEffect.applyMode:
            applyReadingMode(ReaderMode.fromKey(preferences.readerMode));
          case ReaderSettingEffect.updateVolumeListener:
            if (preferences.enableTurnPageByVolumeKey) {
              handleVolumeEvent();
            } else {
              stopVolumeEvent();
            }
          case ReaderSettingEffect.rebuildReader:
            update();
          default:
            throw ArgumentError.value(effect, 'effect', 'Not a reader effect');
        }
      },
    );
  }

  ReaderImageExportRequest? createImageExportRequest() {
    final content = controller.content;
    final originalImages = content.images;
    if (_sessionFrozen ||
        content.isLoading ||
        originalImages == null ||
        originalImages.isEmpty) {
      return null;
    }
    final snapshot = List<String>.unmodifiable(originalImages);
    final comic = cid, comicType = type, chapterId = eid, ep = chapter;
    final sourceKey = comicType.sourceKey;
    final source = ComicSource.find(sourceKey);
    final chapters = widget.chapters;
    final ids = chapters?.ids.toList(growable: false);
    final titles = chapters?.titles.toList(growable: false);
    return ReaderImageExportRequest(
      images: snapshot,
      sourceKey: sourceKey,
      comicId: comic,
      chapterId: chapterId,
      title: widget.name,
      chapter: ep,
      isCurrent: () =>
          mounted &&
          !_sessionFrozen &&
          !controller.isDisposed &&
          identical(controller.content, content) &&
          cid == comic &&
          type == comicType &&
          chapter == ep &&
          eid == chapterId &&
          identical(widget.chapters, chapters) &&
          listEquals(chapters?.ids.toList(growable: false), ids) &&
          listEquals(chapters?.titles.toList(growable: false), titles) &&
          listEquals(images, snapshot) &&
          identical(ComicSource.find(sourceKey), source),
    );
  }

  late final chapterNavigation = ReaderChapterNavigationController(
    onChanged: update,
  );

  ReaderChapterNavigationRequest? createChapterNavigationRequest(
    ReaderContentState content,
  ) {
    final chapters = widget.chapters;
    if (chapters == null || _sessionFrozen || controller.isDisposed) {
      return null;
    }
    final comic = cid, comicType = type, ep = chapter, currentMode = mode;
    final sourceKey = comicType.sourceKey;
    final source = ComicSource.find(sourceKey);
    final ids = chapters.ids.toList(growable: false);
    final titles = chapters.titles.toList(growable: false);
    final supported = !currentMode.isGallery;
    return ReaderChapterNavigationRequest(
      identity: (
        this,
        content,
        chapters,
        source,
        comic,
        comicType,
        ep,
        currentMode,
      ),
      isCurrent: () =>
          mounted &&
          !_stateDisposed &&
          !_sessionFrozen &&
          !_session.isHeld &&
          !controller.isDisposed &&
          identical(controller.content, content) &&
          !content.isLoading &&
          cid == comic &&
          type == comicType &&
          chapter == ep &&
          mode == currentMode &&
          type.sourceKey == sourceKey &&
          identical(widget.chapters, chapters) &&
          identical(ComicSource.find(sourceKey), source) &&
          listEquals(chapters.ids.toList(growable: false), ids) &&
          listEquals(chapters.titles.toList(growable: false), titles),
      canPrevious: supported && !isFirstChapterOfGroup,
      canNext: supported && !isLastChapterOfGroup,
      // The remaining continuous modes all read top to bottom.
      reversed: false,
      select: (direction) => controller.toChapter(ep + direction),
    );
  }

  ReaderChapterRequest createChapterRequest() {
    final comic = cid, comicType = type, chapters = widget.chapters;
    final source = comicType == ComicType.local
        ? null
        : ComicSource.find(comicType.sourceKey);
    final sources = comicType == ComicType.local
        ? null
        : ComicSourceManager.current;
    final local = LocalManager();
    final ids = chapters?.ids.toList(growable: false);
    final titles = chapters?.titles.toList(growable: false);
    final route = ModalRoute.of(context);
    bool current() =>
        mounted &&
        !_stateDisposed &&
        !_sessionFrozen &&
        !controller.isDisposed &&
        cid == comic &&
        type == comicType &&
        identical(widget.chapters, chapters) &&
        identical(LocalManager(), local) &&
        (comicType == ComicType.local ||
            (identical(ComicSource.find(comicType.sourceKey), source) &&
                identical(ComicSourceManager.current, sources))) &&
        listEquals(chapters?.ids.toList(growable: false), ids);
    return ReaderChapterRequest(
      identity: _ReaderInputTarget(
        (this, comic, comicType, chapters, source, sources, local),
        ids,
        null,
      ),
      chapters: chapters,
      isCurrent: current,
      canInteract: () =>
          current() &&
          !_session.isHeld &&
          (route?.isCurrent ?? true) &&
          listEquals(chapters?.titles.toList(growable: false), titles),
      load: (chapter, snapshot, scope) => loadReaderChapterImages(
        comicId: comic,
        type: comicType,
        chapter: chapter,
        chapters: snapshot,
        scope: scope,
        onOnlineFallback: () {
          if (current()) onLocalChapterRecoveredOnline();
        },
      ),
    );
  }

  late final controller = ReaderController(
    pageCount: () => maxPage,
    chapterCount: () => maxChapter,
    animationEnabled: () => preferences.enablePageAnimation,
    viewport: () => imageViewController,
    onChanged: update,
    onPageChanged: onPageChanged,
    onError: (error, stack) =>
        Log.error('Reader', 'Page navigation failed: $error', stack),
  );

  @override
  int get page => controller.state.page;
  @override
  set page(int value) => controller.setPage(value);
  int get chapter => controller.state.chapter;
  bool get jumpToLastPageOnLoad => controller.state.jumpToLastPageOnLoad;

  final viewportBinding = ReaderViewportBinding();
  ReaderImageViewController? get imageViewController => viewportBinding.current;

  void setPage(int page) => controller.reportPage(page);
  @override
  void resetPageAnimation() => controller.resetAnimation();
  bool get isPageAnimating => controller.state.isAnimating;
  bool toPage(int page, {bool animated = true}) =>
      controller.toPage(page, animated: animated);
  bool toNextPage() => toPage(page + 1);
  bool toPrevPage() => toPage(page - 1);
  bool toChapter(int chapter, {bool toLastPage = false}) =>
      controller.toChapter(chapter, toLastPage: toLastPage);
  bool toNextChapter() => toChapter(chapter + 1);
  bool toPrevChapter({bool toLastPage = false}) =>
      toChapter(chapter - 1, toLastPage: toLastPage);

  void update() {
    if (!_stateDisposed) _targetValidity.value++;
    if (_sessionClosing != null || _sessionFrozen) return;
    if (mounted) setState(() {});
  }

  /// The maximum page number for images. Chapter comments are no longer part
  /// of the reader's page sequence, so this is also the internal page count.
  int get maxPage => pageLayout.pageCount(images?.length);

  @override
  ComicType get type => widget.type;

  @override
  String get cid => widget.cid;

  String get eid => widget.chapters?.ids.elementAtOrNull(chapter - 1) ?? '0';

  @override
  List<String>? get images => controller.content.images;

  @override
  late ReaderMode mode;

  @override
  bool get isPortrait =>
      MediaQuery.of(context).orientation == Orientation.portrait;

  History? history;

  late final _pageOrderMigration = ReaderPageOrderMigration(
    migrate: () async {
      final saved = history;
      if (saved == null) return null;
      final previousPage = saved.page;
      final savedChapter = saved.ep;
      await LocalManager().migrateLegacyPageOrder(saved);
      return MigratedReaderPosition(
        chapter: savedChapter,
        previousPage: previousPage,
        imagePage: saved.page,
      );
    },
    initialChapter: widget.initialChapter ?? 1,
    initialPage: widget.initialPage,
    currentChapter: () => chapter,
    displayPage: (imagePage) => pageLayout.pageForImage(imagePage),
    restorePage: controller.restorePage,
  );

  Future<void> prepareLocalPageOrder(bool Function() isCancelled) async {
    if (type != ComicType.local) return;
    await _pageOrderMigration.prepare(
      isCancelled: () => !mounted || isCancelled(),
    );
  }

  bool _reportedMissingLocalFiles = false;

  void onLocalChapterRecoveredOnline() {
    if (!mounted || _reportedMissingLocalFiles) return;
    _reportedMissingLocalFiles = true;
    showToast(
      context: context,
      message:
          'Local chapter files are unavailable. Reading online instead.'.tl,
    );
  }

  late final ReaderSession _session;
  SelectionTaskRegistry? _sessionRegistry;
  void Function()? _releaseSessionHost;
  Future<void>? _sessionClosing;
  bool _sessionFrozen = false;
  bool _stateDisposed = false;

  void _freezeSession() {
    if (_sessionFrozen) return;
    _sessionFrozen = true;
    _targetValidity.value++;
    chapterNavigation.dispose();
    _beginCloseVolume();
    _platformEffects?.dispose();
    disposeReaderWindow();
    controller.dispose();
    // A host can close from inside a child's callback or dependency rebuild.
    // Admission freezes now; the visual update waits until that build ends.
    scheduleMicrotask(() {
      if (mounted && !_stateDisposed) setState(() {});
    });
  }

  Future<void> _closeSession() {
    if (_sessionClosing case final closing?) return closing;
    _freezeSession();
    final closing = _sessionClosing = _session.dispose();
    _exitFrame?.removeCloseStartListener(_holdWindowSession);
    _exitFrame?.removeCloseFailureListener(_resumeWindowSession);
    _exitFrame?.removeExitTask(_prepareWindowSession);
    _exitFrame?.trackExitTask(closing);
    _resumeWindowSession();
    unawaited(
      closing.then<void>(
        (_) {
          _releaseSessionHost?.call();
          _releaseSessionHost = null;
        },
        onError: (Object error, StackTrace stack) {
          Log.error('Reader', 'Failed to close reading session: $error', stack);
        },
      ),
    );
    return closing;
  }

  void _bindSessionOwner() {
    _bindVolumeOwner();
    final registry = _sessionRegistry;
    if (registry != null) {
      // Every shared image/settings task keeps independent error evidence even
      // after a reversible page drain has already reported the failure.
      imageWork.retainTasks(
        (task) =>
            registry.retain(cancel: task.cancel, close: task.closeAndWait),
      );
      _releaseSessionHost = registry.retain(
        cancel: () {
          unawaited(_closeSession());
        },
        close: _closeSession,
      );
    }
    final frame = _exitFrame;
    if (_sessionFrozen || frame == null) return;
    frame.addCloseStartListener(_holdWindowSession);
    frame.addCloseFailureListener(_resumeWindowSession);
    frame.addExitTask(_prepareWindowSession);
    if (frame.isClosing) {
      _holdWindowSession();
      frame.trackExitTask(_prepareWindowSession());
    }
  }

  ReaderSettings get preferences =>
      appdata.settings.readerSettings(cid, type.sourceKey);

  /// Whether the current mode renders the following chapter in the same view.
  ///
  /// Only the vertical continuous mode merges chapters: it replaces the removed
  /// waterfall mode. Horizontal continuous modes keep their explicit chapter
  /// boundary, and gallery modes never cross chapters.
  bool get crossChapterFlow =>
      mode == ReaderMode.continuousTopToBottom &&
      preferences.autoReadingAcrossChapters;

  void applyReadingMode(ReaderMode next) {
    if (!mounted || _sessionFrozen || mode == next) return;
    resetPageAnimation();
    mode = next;
    // Convert the old display page to its source image before rebuilding.
    _checkImagesPerPageChange();
    viewportBinding.clear();
    update();
  }

  bool get isLoading => controller.content.isLoading;

  late final focusNode = FocusNode()..addListener(_keyboardFocusChanged);

  void _keyboardFocusChanged() {
    if (!_stateDisposed && !focusNode.hasPrimaryFocus) {
      imageViewController?.cancelKeyboardInput();
    }
  }

  @override
  void initState() {
    page = widget.initialPage ?? 1;
    if (page < 1) {
      page = 1;
    }
    final initialChapter = widget.initialChapter ?? 1;
    controller.restoreChapter(initialChapter < 1 ? 1 : initialChapter);
    if (widget.initialChapterGroup != null) {
      controller.restoreChapter(
        widget.chapters!.chapterIndex(
          chapter,
          group: widget.initialChapterGroup,
        ),
      );
    }
    if (widget.initialPage != null) {
      page = widget.initialPage!;
      if (page < 1) {
        page = 1;
      }
    }
    mode = ReaderMode.fromKey(
      appdata.settings.readerSettings(cid, type.sourceKey).readerMode,
    );
    history = widget.history;
    final historyManager = HistoryScope.read(context);
    _sessionRegistry = context
        .getInheritedWidgetOfExactType<SelectionTasksScope>()
        ?.registry;
    _exitFrame = context.getInheritedWidgetOfExactType<WindowFrameController>();
    final admitted = _sessionRegistry?.isClosing != true;
    final onClosed = widget.onClosed;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _volumeForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    // No reading-time tracker: nothing displays that statistic, and its extra
    // write was one more thing that could fail while leaving the reader.
    _session = ReaderSession(
      imageWork: imageWork,
      progress: ReaderHistoryWriter(
        write: () async {
          final item = history;
          if (item != null) await historyManager.addHistory(item);
        },
        onError: (error, stack) => Log.error(
          'Reader',
          'Failed to save reading progress: $error',
          stack,
        ),
      ),
      // Volume ownership follows the session's foreground/hold state.
      onPauseChanged: (_) {
        _observeVolume(_updateVolume());
      },
      onClosed: () {
        if (admitted) onClosed();
      },
      foreground: lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
    _bindSessionOwner();
    if (_sessionFrozen) {
      super.initState();
      return;
    }
    _platformEffects = ReaderPlatformEffectsBinding(
      context,
      systemBarsVisible: preferences.showSystemStatusBar,
    );
    if (appdata.settings
        .readerSettings(cid, type.sourceKey)
        .enableTurnPageByVolumeKey) {
      handleVolumeEvent();
    }
    setImageCacheSize();
    final favorites = FavoritesScope.read(context);
    final favoriteGeneration = favorites.connectionGeneration;
    final comicId = cid;
    final comicType = type;
    final readingDelay = Completer<void>();
    Timer? readingTimer;
    final readingTask = imageWork.start(
      onCancel: () {
        readingTimer?.cancel();
        if (!readingDelay.isCompleted) readingDelay.complete();
      },
    );
    if (readingTask != null) {
      readingTimer = Timer(
        const Duration(milliseconds: 200),
        readingDelay.complete,
      );
      unawaited(() async {
        try {
          // Retain the original post-navigation delay, but own it through exit.
          await readingDelay.future;
          readingTask.check();
          await favorites.onRead(
            comicId,
            comicType,
            generation: favoriteGeneration,
            checkActive: readingTask.check,
          );
        } on ImageWorkTaskCancelled {
          // Leaving before admission does not start another write.
        } catch (error, stack) {
          readingTask.recordFailure(error, stack);
          Log.error('Reader favorites', error, stack);
        } finally {
          readingTask.finish();
        }
      }());
    }
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = context
        .dependOnInheritedWidgetOfExactType<SelectionTasksScope>()
        ?.registry;
    final frame = context
        .dependOnInheritedWidgetOfExactType<WindowFrameController>();
    ReaderPlatformEffectsScope.watch(context);
    if (_platformEffects?.belongsTo(context) == false ||
        registry != _sessionRegistry ||
        frame?.trackExitTask != _exitFrame?.trackExitTask) {
      unawaited(_closeSession());
    }
    _volumeRoute = ModalRoute.of(context);
    _volumeCurrent = _volumeRoute?.isCurrent ?? true;
    _observeVolume(_updateVolume());
    if (!_isInitialized) {
      initImagesPerPage(widget.initialPage ?? 1);
      _isInitialized = true;
    } else {
      // For orientation changed
      _checkImagesPerPageChange();
    }
    if (!_sessionFrozen) initReaderWindow();
  }

  late final _imageCachePolicy = ReaderImageCachePolicy(
    readAvailableMemory: MemoryInfo.getFreePhysicalMemorySize,
    setLimit: (bytes) =>
        PaintingBinding.instance.imageCache.maximumSizeBytes = bytes,
    onConfigured: (memory, limit) => Log.info(
      'Reader',
      'Detect available RAM: $memory, set image cache size to $limit',
    ),
    onError: (error, stack) =>
        Log.error('Reader', 'Failed to size image cache: $error', stack),
  );

  void setImageCacheSize() => unawaited(_imageCachePolicy.configure());

  late final _volumeController = ReaderVolumeController(
    connect: createVolumeConnection,
    nextPage: () {
      return _canReceiveVolume && toNextPage();
    },
    previousPage: () {
      return _canReceiveVolume && toPrevPage();
    },
    nextChapter: () {
      if (_canReceiveVolume) toNextChapter();
    },
    previousChapter: () {
      if (_canReceiveVolume) toPrevChapter(toLastPage: true);
    },
    onError: (error, stack) =>
        Log.error('Reader', 'Volume navigation failed: $error', stack),
  );

  bool get supportsVolumeKeys => App.isAndroid;

  ReaderVolumeConnection createVolumeConnection(
    void Function(Object?) onEvent,
  ) => connectReaderVolume(onEvent);

  bool _volumeRequested = false;
  bool _volumeForeground = true;
  bool _volumeCurrent = false;
  ModalRoute<dynamic>? _volumeRoute;
  bool _volumeWindowHeld = false;
  bool _volumeClosed = false;
  Future<void>? _volumeClosing;
  void Function()? _releaseVolumeHost;

  bool get _canReceiveVolume =>
      supportsVolumeKeys &&
      _volumeRequested &&
      _volumeForeground &&
      _volumeCurrent &&
      (_volumeRoute?.isCurrent ?? true) &&
      !_volumeWindowHeld &&
      !_volumeClosed &&
      !_sessionFrozen &&
      !_session.isHeld;

  Future<void> _updateVolume() => _volumeClosed
      ? Future.value()
      : _volumeController.setEnabled(_canReceiveVolume);

  void _observeVolume(Future<void> operation) {
    // The controller reports the error; the retained close callback owns retry.
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void handleVolumeEvent() {
    _volumeRequested = true;
    _observeVolume(_updateVolume());
  }

  void stopVolumeEvent() {
    _volumeRequested = false;
    _observeVolume(_updateVolume());
  }

  void _bindVolumeOwner() {
    _releaseVolumeHost = _sessionRegistry?.retain(
      cancel: _beginCloseVolume,
      close: _closeVolume,
    );
    final frame = _exitFrame;
    if (frame == null) return;
    frame.addCloseStartListener(_holdVolume);
    frame.addCloseFailureListener(_resumeVolume);
    frame.addExitTask(_prepareVolume);
    if (frame.isClosing) _holdVolume();
  }

  void _holdVolume() {
    _volumeWindowHeld = true;
    _observeVolume(_updateVolume());
  }

  void _resumeVolume() {
    _volumeWindowHeld = false;
    _observeVolume(_updateVolume());
  }

  Future<void> _prepareVolume() =>
      _volumeClosed ? _closeVolume() : _volumeController.setEnabled(false);

  void _beginCloseVolume() => _observeVolume(_closeVolume());

  Future<void> _closeVolume() {
    if (_volumeClosing case final closing?) return closing;
    _volumeClosed = true;
    final closing = _volumeClosing = _volumeController.dispose();
    unawaited(
      closing.then<void>(
        (_) {
          _releaseVolumeHost?.call();
          _releaseVolumeHost = null;
          _exitFrame?.removeCloseStartListener(_holdVolume);
          _exitFrame?.removeCloseFailureListener(_resumeVolume);
          _exitFrame?.removeExitTask(_prepareVolume);
        },
        onError: (Object _, StackTrace _) {
          _volumeClosing = null;
        },
      ),
    );
    return closing;
  }

  Future<void Function()> _prepareReaderExit() async {
    final effects = _platformEffects?.prepareForExit();
    void Function()? release;
    final failures =
        <({String operation, Object error, StackTrace stackTrace})>[];
    Future<void> attempt(
      String operation,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error, stackTrace) {
        failures.add((
          operation: operation,
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }

    await Future.wait([
      attempt('reading preparation', () async {
        release = await _session.prepareForExit();
        await _updateVolume();
      }),
      if (effects != null) attempt('platform restoration', () => effects.ready),
    ]);
    if (failures.isNotEmpty) {
      // Leaving must not depend on a save or a platform restore succeeding.
      // Blocking here stranded the reader on a write it could not repair, and
      // the transport's own cancellation was reported as just such a failure.
      // Keep every failure as a diagnostic, then leave: the session still
      // retries its writers while it finalizes in the background.
      for (final failure in failures) {
        Log.error(
          'Reader',
          'Failed to prepare reader exit: '
              '${failure.operation}: ${failure.error}',
          failure.stackTrace,
        );
      }
    }
    return () {
      effects?.release();
      release?.call();
    };
  }

  ReaderPlatformEffectsBinding? _platformEffects;
  ReaderOrientation get readerOrientation =>
      _platformEffects?.handle.orientation ?? ReaderOrientation.system;

  void cycleReaderOrientation() {
    if (_sessionFrozen) return;
    if (_platformEffects?.cycleOrientation() == true) setState(() {});
  }

  void updateSystemUi(bool menuOpen) {
    if (_sessionFrozen) return;
    _platformEffects?.setSystemBarsVisible(
      menuOpen || preferences.showSystemStatusBar,
    );
  }

  ReaderWindowController? _windowController;
  Future<void>? _windowClosing;
  void Function()? _releaseWindowHost;
  WindowFrameController? _exitFrame;
  final _exitGuardKey = GlobalKey<ReaderExitGuardState>();
  void Function()? _windowSessionHold;
  final Set<void Function()> _preparedSessionReleases = {};

  Future<void> requestExit() => _sessionFrozen
      ? Future.value()
      : _exitGuardKey.currentState?.requestExit() ?? Future.value();

  void _holdWindowSession() {
    if (_sessionFrozen) return;
    _windowSessionHold ??= _session.holdForExit();
    _targetValidity.value++;
  }

  Future<void> _prepareWindowSession() async {
    if (_sessionFrozen) {
      await _closeSession();
      return;
    }
    final frame = _exitFrame;
    final release = await _session.prepareForExit();
    if (!mounted || _sessionFrozen || !identical(_exitFrame, frame)) {
      release();
      return;
    }
    _preparedSessionReleases.add(release);
  }

  void _resumeWindowSession() {
    final releases = _preparedSessionReleases.toList();
    final hold = _windowSessionHold;
    _preparedSessionReleases.clear();
    _windowSessionHold = null;
    final failures =
        <({String operation, Object error, StackTrace stackTrace})>[];
    for (final release in [...releases, ?hold]) {
      try {
        release();
      } catch (error, stackTrace) {
        failures.add((
          operation: 'resume',
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }
    if (failures.isNotEmpty) throw ReaderSessionFailure(failures);
  }

  void initReaderWindow() {
    if (!App.isDesktop || _windowController != null) return;
    final frame = _exitFrame;
    if (frame == null || frame.isClosing) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    _windowController = ReaderWindowController(
      coordinator: windowCoordinator,
      frameIdentity: frame.setWindowFrame,
      initialFrameVisible: !frame.isWindowFrameHidden,
      setFrameVisible: frame.setWindowFrame,
      addCloseListener: frame.addCloseListener,
      removeCloseListener: frame.removeCloseListener,
      canPop: navigator.canPop,
      pop: () {
        if (_sessionFrozen) return;
        if (ModalRoute.of(context)?.isCurrent == true) {
          unawaited(requestExit());
        } else {
          unawaited(navigator.maybePop());
        }
      },
      onError: (error, stack) =>
          Log.error('Reader', 'Window transition failed: $error', stack),
    );
    _releaseWindowHost = _sessionRegistry?.retain(
      cancel: disposeReaderWindow,
      close: _closeReaderWindow,
    );
    frame.addCloseStartListener(_holdWindowEffects);
    frame.addCloseFailureListener(_resumeWindowEffects);
    frame.addExitTask(_prepareWindowEffects);
    if (frame.isClosing) _holdWindowEffects();
    _observeWindow(_windowController!.attach());
  }

  // window_manager addresses one native window per engine. Keep its serial
  // coordinator across route and WindowFrame replacements, with scoped owners.
  static final _nativeWindowCoordinator = ReaderWindowCoordinator(
    hide: windowManager.hide,
    show: windowManager.show,
    setFullscreen: windowManager.setFullScreen,
  );

  ReaderWindowCoordinator get windowCoordinator => _nativeWindowCoordinator;

  void _observeWindow(Future<void> operation) {
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _holdWindowEffects() {
    final window = _windowController;
    if (window != null) _observeWindow(window.setHeld(true));
  }

  void _resumeWindowEffects() {
    final window = _windowController;
    if (window != null) _observeWindow(window.setHeld(false));
  }

  Future<void> _prepareWindowEffects() => _sessionFrozen
      ? _closeReaderWindow()
      : _windowController?.setHeld(true) ?? Future.value();

  void fullscreen() {
    if (_sessionFrozen) return;
    final window = _windowController;
    if (window != null) _observeWindow(window.toggle());
  }

  void disposeReaderWindow() => _observeWindow(_closeReaderWindow());

  Future<void> _closeReaderWindow() {
    if (_windowClosing case final closing?) return closing;
    final window = _windowController;
    if (window == null) return Future.value();
    final closing = _windowClosing = window.dispose();
    unawaited(
      closing.then<void>(
        (_) {
          _releaseWindowHost?.call();
          _releaseWindowHost = null;
          _exitFrame?.removeCloseStartListener(_holdWindowEffects);
          _exitFrame?.removeCloseFailureListener(_resumeWindowEffects);
          _exitFrame?.removeExitTask(_prepareWindowEffects);
        },
        onError: (Object _, StackTrace _) {
          _windowClosing = null;
        },
      ),
    );
    return closing;
  }

  @override
  void dispose() {
    _stateDisposed = true;
    _targetValidity.value++;
    viewportBinding.dispose();
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeSession());
    focusNode.dispose();
    _platformEffects?.dispose();
    _beginCloseVolume();
    _imageCachePolicy.dispose();
    disposeReaderWindow();
    _targetValidity.dispose();
    _shellChanges.dispose();
    super.dispose();
  }

  void onReaderContentLoading() {
    _session.setContentReady(false);
  }

  void onReaderContentReady() => _session.setContentReady(true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _volumeForeground = state == AppLifecycleState.resumed;
    _session.setForeground(state == AppLifecycleState.resumed);
    _observeVolume(_updateVolume());
  }

  @override
  Widget build(BuildContext context) {
    _checkImagesPerPageChange();
    return ReaderExitGuard(
      key: _exitGuardKey,
      prepare: _prepareReaderExit,
      holdForLeave: _session.holdForExit,
      onError: (error, stack) {
        Log.error('Reader', 'Failed to save before leaving: $error', stack);
        if (mounted) {
          showToast(
            message: 'Unable to close. Please try again.'.tl,
            context: context,
            seconds: 10,
            trailing: TextButton(
              onPressed: () => _exitGuardKey.currentState?.leaveWithoutSaving(),
              child: Text('Leave without saving'.tl),
            ),
          );
        }
      },
      child: ExcludeFocus(
        excluding: _sessionFrozen,
        child: AbsorbPointer(
          absorbing: _sessionFrozen,
          child: KeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: onKeyEvent,
            child: Overlay.wrap(
              child: ReaderShellHost(
                reader: this,
                child: ReaderGestureHost(
                  reader: this,
                  child: ReaderImagesHost(
                    reader: this,
                    // A cross-chapter flow reports the scrolled chapter while
                    // the view stays alive, so its host key must not follow
                    // [chapter].
                    key: Key(crossChapterFlow ? mode.key : chapter.toString()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onKeyEvent(KeyEvent event) {
    if (_sessionFrozen) return;
    if (event.logicalKey == LogicalKeyboardKey.f12 && event is KeyUpEvent) {
      fullscreen();
    }
    if (!focusNode.hasPrimaryFocus) return;
    imageViewController?.handleKeyEvent(event);
  }

  int get maxChapter => widget.chapters?.length ?? 1;

  void onPageChanged() {
    updateHistory();
    if (!_stateDisposed) _targetValidity.value++;
  }

  void updateHistory() {
    // Initial layout and orientation can update the viewport before images
    // arrive. Keep the saved image index intact until loading/migration ends.
    if (_sessionFrozen || isLoading || images == null) return;
    if (history != null) {
      final total = images!.length;
      // The chapter counts as read once its last page is on screen. Using the
      // last page rather than "opened" is what stops a half-read chapter from
      // showing as finished on the shelf.
      final range = pageLayout.imageRange(page, total);
      // The chapter counts as read once its last page is on screen. Using the
      // last page rather than "opened" is what stops a half-read chapter from
      // showing as finished on the shelf.
      //
      // "Single image on first page" maps page 1 to image range (0, 1) no matter
      // how many images the chapter has, so comparing against that end alone
      // marked a one-image chapter read the moment it opened, and a chapter
      // whose last display page was reached by that shortcut did the same. The
      // read mark therefore also requires page 1 to be the chapter's only page.
      final atEnd =
          total > 0 &&
          range.$2 >= total &&
          (page > 1 || pageLayout.pageCount(total) == 1);
      applyReaderHistoryProgress(
        history: history!,
        page: page,
        imageCount: total,
        chapter: chapter,
        chapters: widget.chapters,
        layout: pageLayout,
        time: DateTime.now(),
        markRead: atEnd,
      );
      _session.scheduleProgress();
      // A content/animation completion can arrive after the reader's own exit
      // task returned while another owner is still preparing. Register the
      // fresh drain so the window joins it before proceeding or restoring UI.
      if (_windowSessionHold != null) {
        _exitFrame?.trackExitTask(_prepareWindowSession());
      }
    }
  }

  bool get isFirstChapterOfGroup => widget.chapters?.isGrouped == true
      ? widget.chapters!.positionAt(chapter).isFirstInGroup
      : chapter == 1;

  bool get isLastChapterOfGroup => widget.chapters?.isGrouped == true
      ? widget.chapters!.positionAt(chapter).isLastInGroup
      : chapter == maxChapter;

  /// Get the size of the reader.
  /// The size is not always the same as the size of the screen.
  Size get size {
    var renderBox = context.findRenderObject() as RenderBox;
    return renderBox.size;
  }
}

abstract mixin class ReaderImagePerPageHandler {
  late int _lastImagesPerPage;

  late bool _lastOrientation;

  bool get isPortrait;

  int get page;

  set page(int value);

  ReaderMode get mode;

  String get cid;

  ComicType get type;

  /// Images used to bound page remapping
  List<String>? get images;

  void initImagesPerPage(int initialPage) {
    _lastImagesPerPage = imagesPerPage;
    _lastOrientation = isPortrait;
    if (imagesPerPage != 1) page = pageLayout.pageForImage(initialPage);
  }

  ReaderPageLayout get pageLayout => ReaderPageLayout(
    imagesPerPage: imagesPerPage,
    singleImageOnFirstPage: showSingleImageOnFirstPage(),
  );

  bool showSingleImageOnFirstPage() => appdata.settings
      .readerSettings(cid, type.sourceKey)
      .showSingleImageOnFirstPage;

  /// The number of images displayed on one screen
  int get imagesPerPage {
    if (mode.isContinuous) return 1;
    if (isPortrait) {
      return appdata.settings
          .readerSettings(cid, type.sourceKey)
          .readerScreenPicNumberForPortrait;
    } else {
      return appdata.settings
          .readerSettings(cid, type.sourceKey)
          .readerScreenPicNumberForLandscape;
    }
  }

  /// Check if the number of images per page has changed.
  void _checkImagesPerPageChange() {
    final currentImagesPerPage = imagesPerPage;
    final currentOrientation = isPortrait;
    if (_lastImagesPerPage != currentImagesPerPage ||
        _lastOrientation != currentOrientation) {
      // A page animation can be interrupted by the platform relayout that
      // accompanies a rotation. Clear its pending target before remapping the
      // page, otherwise automatic reading remains blocked by isAnimating until
      // the user performs another page turn.
      resetPageAnimation();
      final previousLayout = ReaderPageLayout(
        imagesPerPage: _lastImagesPerPage,
        singleImageOnFirstPage: showSingleImageOnFirstPage(),
      );
      page = previousLayout.remapPage(
        page,
        pageLayout,
        imageCount: images?.length,
      );
      _lastImagesPerPage = currentImagesPerPage;
      _lastOrientation = currentOrientation;
    }
  }

  /// Invalidates a navigation animation before a layout remaps the page.
  void resetPageAnimation();
}

enum ReaderMode {
  galleryLeftToRight('galleryLeftToRight'),
  galleryRightToLeft('galleryRightToLeft'),
  galleryTopToBottom('galleryTopToBottom'),
  continuousTopToBottom('continuousTopToBottom');

  final String key;

  bool get isGallery => key.startsWith('gallery');

  bool get isContinuous => key.startsWith('continuous');

  bool get isTopToBottom =>
      this == galleryTopToBottom || this == continuousTopToBottom;

  const ReaderMode(this.key);

  /// Resolves a stored mode key. Removed modes (`waterfallTopToBottom` and the
  /// horizontal continuous modes) migrate onto the remaining continuous mode,
  /// so an existing preference keeps working without user action.
  static ReaderMode fromKey(String key) {
    if (key == 'waterfallTopToBottom') {
      return continuousTopToBottom;
    }
    for (var mode in values) {
      if (mode.key == key) {
        return mode;
      }
    }
    return continuousTopToBottom;
  }
}
