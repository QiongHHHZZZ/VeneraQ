import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/components/file_save_task.dart';
import 'package:venera_next/network/request_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:venera_next/routing/local_reading.dart';
import 'package:venera_next/routing/page_replacement.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/image_save_binding.dart';
import 'package:venera_next/components/image.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/comic_details/action_button.dart';
import 'package:venera_next/features/comic_details/actions.dart';
import 'package:venera_next/features/comic_details/chapters.dart';
import 'package:venera_next/features/comic_details/comic_details_cache.dart';
import 'package:venera_next/features/comic_details/comments_preview.dart';
import 'package:venera_next/features/comic_details/cover_viewer.dart';
import 'package:venera_next/features/comic_details/thumbnails.dart';
import 'package:venera_next/foundation/app_locale.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/consts.dart';
import 'package:venera_next/foundation/back_interceptor.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/foundation/image_provider/cached_image.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/foundation/image_provider/read_image.dart';
import 'package:venera_next/foundation/image_save_work.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

bool isReadOnlyComicInfoNamespace(String namespace) {
  final key = namespace.trim().toLowerCase();
  const readOnlyNamespaces = {
    'views',
    'view',
    'view count',
    'view_count',
    'viewcount',
    '浏览量',
    '浏览次数',
    '观看数',
    '觀看數',
    '阅读量',
    '閱讀量',
    '更新',
    '最後更新',
    '最后更新',
    'update',
    'last update',
  };
  return readOnlyNamespaces.contains(key);
}

class ComicPage extends StatefulWidget {
  const ComicPage({
    super.key,
    required this.id,
    required this.sourceKey,
    this.cover,
    this.title,
    this.heroID,
  });

  final String id;

  final String sourceKey;

  final String? cover;

  final String? title;

  final int? heroID;

  @override
  State<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends LoadingState<ComicPage, ComicDetails>
    with ComicPageActions, ContextMenuOwner {
  @override
  Object? get contextMenuIdentity => data;
  late final _saves = ImageSaveWork(
    deliver: (bytes, filename, checkStop) => saveFileForWindow(
      context,
      data: bytes,
      filename: filename,
      checkStop: checkStop,
    ),
    onError: (error, stack) {
      Log.error('Image save', error, stack);
      if (mounted) context.showMessage(message: 'Error'.tl);
    },
  );

  @override
  Widget build(BuildContext context) {
    contextMenus.revalidate();
    return ImageSaveBinding(work: _saves, child: super.build(context));
  }

  @override
  History? history;

  /// Durable read marks for this comic, independent of [history].
  ///
  /// The chapter list, the "all read" label and "continue" read from here, so
  /// they keep working when the history row is absent or was cleared.
  ReadState get readState => HistoryScope.read(
    context,
  ).readMarks(widget.id, ComicType(widget.sourceKey.hashCode));

  /// Chapter ids stored on the device for this comic, or null when none are.
  ///
  /// Null rather than an empty set so the chapter list can tell "no library
  /// entry" from "nothing downloaded" and skip the per-row badge lookup.
  Set<String>? get downloadedChapters {
    final local = LocalManager().find(
      widget.id,
      ComicType.fromKey(widget.sourceKey),
    );
    if (local == null || local.downloadedChapters.isEmpty) return null;
    return local.downloadedChapters.toSet();
  }

  bool showAppbarTitle = false;

  /// Whether the chapter list is in multi-select mode.
  ///
  /// A notifier rather than a plain field: [PopScope.canPop] has to follow it
  /// without depending on this page rebuilding, because a cached ancestor can
  /// otherwise leave the route believing it may still pop.
  final _chapterSelection = ValueNotifier<bool>(false);

  /// Bumped to ask the chapter list to leave selection mode. The back gesture
  /// owns the exit, so the list cannot clear itself.
  final _chapterSelectionReset = ValueNotifier<int>(0);

  /// Claim handed to the app shell while a selection is active.
  ///
  /// Stored as a field rather than re-creating the tear-off so the shell can
  /// release exactly the claim this page registered.
  late final VoidCallback _backClaim = _cancelChapterSelection;

  /// Leaves selection mode. Used both by the back gesture and by the list's own
  /// cancel button, so the two cannot drift apart.
  void _cancelChapterSelection() {
    _chapterSelection.value = false;
    _chapterSelectionReset.value++;
  }

  var scrollController = ScrollController();

  @override
  void onReadEnd() {
    history ??= HistoryScope.read(
      context,
    ).find(widget.id, ComicType(widget.sourceKey.hashCode));
    update();
  }

  @override
  Widget buildLoading() {
    return _ComicPageLoadingPlaceHolder(
      cover: widget.cover,
      title: widget.title,
      sourceKey: widget.sourceKey,
      cid: widget.id,
      heroID: widget.heroID,
    );
  }

  @override
  Widget buildError() {
    final isDownloaded = LocalManager().isDownloaded(
      widget.id,
      ComicType.fromKey(widget.sourceKey),
    );
    Widget? action;
    if (isDownloaded) {
      action = FilledButton.tonal(
        child: Text("Read".tl),
        onPressed: () {
          final localComic = LocalManager().find(
            widget.id,
            ComicType.fromKey(widget.sourceKey),
          );
          if (localComic == null) {
            context.showMessage(message: "Local comic not found".tl);
            return;
          }
          openLocalComic(localComic);
        },
      );
    }
    return NetworkError(message: error!, retry: retry, action: action);
  }

  @override
  void initState() {
    scrollController.addListener(onScroll);
    super.initState();
  }

  @override
  void didUpdateWidget(ComicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.sourceKey != widget.sourceKey) {
      isFirst = true;
      retry();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(onScroll);
    scrollController.dispose();
    // Leaving the page must not leave a claim behind for the next one.
    BackInterceptor.unregister(_backClaim);
    _chapterSelection.dispose();
    _chapterSelectionReset.dispose();
    super.dispose();
  }

  @override
  bool isComicActive(ComicDetails value) => mounted && identical(data, value);

  @override
  void update() {
    if (mounted) setState(() {});
  }

  @override
  ComicDetails get comic => data!;

  /// Reveals the title in the top bar once the header scrolls away.
  void onScroll() {
    var offset =
        scrollController.position.pixels -
        scrollController.position.minScrollExtent;
    if (offset > 100) {
      if (!showAppbarTitle) {
        setState(() {
          showAppbarTitle = true;
        });
      }
    } else {
      if (showAppbarTitle) {
        setState(() {
          showAppbarTitle = false;
        });
      }
    }
  }

  var isFirst = true;

  bool _descriptionExpanded = false;

  bool _pendingRefresh = false;

  Future<void>? _refreshingDetails;

  /// Whether this comic is already stored on the device, which hides the
  /// download action.
  bool get downloaded => LocalManager().isDownloaded(
    widget.id,
    ComicType.fromKey(widget.sourceKey),
  );

  /// Lets the overflow menu start the same refresh a pull gesture does.
  ///
  /// Driven through the [RefreshIndicator] rather than a spinner of its own, so
  /// the menu shows the indicator the reader already associates with refreshing.
  /// `show()` runs [RefreshIndicator.onRefresh] itself, which is the same reload
  /// the pull path uses — the menu must not start a second one.
  final _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  VoidCallback? get onRefreshRequested =>
      comicSource.loadComicInfo == null ? null : _refreshFromMenu;

  void _refreshFromMenu() {
    final indicator = _refreshIndicatorKey.currentState;
    if (indicator == null) return;
    // Ignores the request while one is already on screen.
    unawaited(indicator.show());
  }

  @override
  Widget buildContent(BuildContext context, ComicDetails data) {
    // The bar's action follows the reading state, not just the history row.
    //
    // Read marks are their own record and do not create a history row, so
    // marking chapters read left `hasHistory` false here: the button still said
    // "Read" and went through `read()` at chapter 1, discarding every mark the
    // reader had just made. Any stored position or any read mark means there is
    // somewhere to continue from.
    final hasHistory =
        (history != null && (history!.ep > 1 || history!.page > 1)) ||
        readState.readEpisode.isNotEmpty;
    // With every chapter read, "continue" would reopen the last one; saying so
    // avoids implying there is something new to read. Marks are independent of
    // the history row, so this stays correct after clearing history.
    final marks = readState;
    final allRead =
        comic.chapters != null &&
        comic.chapters!.nextUnreadChapter(marks) == null;
    return ValueListenableBuilder<bool>(
      valueListenable: _chapterSelection,
      builder: (context, selecting, child) => PopScope(
        // While a chapter selection is active this page claims the back gesture
        // and cancels it; otherwise the framework pops normally.
        //
        // Popping manually in the other branch was the bug: cancelling flips the
        // flag, so a second delivery of the same swipe found "not selecting" and
        // left the comic instead of stopping at the selection.
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop || !selecting) return;
          // Back leaves selection mode and nothing else.
          _chapterSelection.value = false;
          _chapterSelectionReset.value++;
        },
        child: child!,
      ),
      child: Scaffold(
        // Reading is the primary action, so it floats at the bottom right like
        // the reader-style layout instead of taking a row of its own.
        floatingActionButton: FloatingActionButton.extended(
          onPressed: allRead
              ? continueRead
              : (hasHistory ? continueRead : read),
          icon: Icon(
            allRead
                ? Icons.done_all
                : (hasHistory ? Icons.menu_book : Icons.play_arrow_rounded),
          ),
          label: Text(
            allRead ? "All Read".tl : (hasHistory ? "Continue".tl : "Read".tl),
          ),
        ),
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          // Pull-to-refresh re-reads the source, so new chapters appear without
          // hunting for the top-bar refresh button. The menu drives this same
          // indicator, so both entries show the identical spinner.
          onRefresh: () => _refreshDetails(manual: true),
          child: SmoothCustomScrollView(
            controller: scrollController,
            // A short details page still needs to overscroll for the refresh.
            additionalPhysics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ...buildTitle(),
              buildActions(),
              buildDescription(),
              buildChapters(),
              buildComments(),
              buildThumbnails(),
              buildRecommend(),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: context.padding.bottom + 96,
                ), // Clear the floating reading button
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<Res<ComicDetails>> loadData(RequestScope scope) async {
    if (widget.sourceKey == 'local') {
      var localComic = LocalManager().find(widget.id, ComicType.local);
      if (localComic == null) {
        return const Res.error('Local comic not found');
      }
      var history = HistoryScope.read(context).find(widget.id, ComicType.local);
      if (isFirst) {
        final pageContext = context;
        Future.microtask(() {
          if (!pageContext.mounted || scope.isCancelled) return;
          final onClosed = ReaderSessionScope.onClosedOf(pageContext);
          replaceWithRootPage(pageContext, (_) {
            return Reader(
              onClosed: onClosed,
              type: ComicType.local,
              cid: localComic.id,
              name: localComic.title,
              chapters: localComic.chapters,
              initialPage: history?.page,
              initialChapter: history?.ep,
              initialChapterGroup: history?.group,
              history: History.resume(history, localComic),
              author: localComic.subTitle ?? '',
              tags: localComic.tags,
            );
          });
        });
        isFirst = false;
      }
      await scope.wait(const Duration(milliseconds: 200));
      return const Res.error('Local comic');
    }
    var comicSource = ComicSource.find(widget.sourceKey);
    if (comicSource == null) {
      return const Res.error('Comic source not found');
    }
    isAddToLocalFav = FavoritesScope.read(
      context,
    ).isExist(widget.id, ComicType(widget.sourceKey.hashCode));
    history = HistoryScope.read(
      context,
    ).find(widget.id, ComicType(widget.sourceKey.hashCode));
    final cache = ComicDetailsCache.instance;
    final cached = await cache.read(widget.sourceKey, widget.id);
    if (cached != null) {
      final age = cache.age(widget.sourceKey, widget.id);
      _pendingRefresh = age == null || age > const Duration(seconds: 20);
      return Res(cached);
    }
    final stopwatch = Stopwatch()..start();
    final result = await comicSource.loadComicInfo!(widget.id);
    Log.info(
      "Comic details",
      "loadInfo ${widget.sourceKey}/${widget.id} took "
          "${stopwatch.elapsedMilliseconds}ms",
    );
    if (result.success) {
      unawaited(ComicDetailsCache.instance.write(result.data));
    }
    return result;
  }

  @override
  Future<void> onDataLoaded(RequestScope scope) async {
    _descriptionExpanded = false;
    isLiked = comic.isLiked ?? false;
    isFavorite = comic.isFavorite ?? false;
    // A position-only entry has no title and no cover, so restoring it verbatim
    // would blank the tile and be written back as an empty metadata row. Merge
    // it onto the details this page loaded, keeping its position.
    final stored = history;
    if (stored != null && stored.title.isEmpty) {
      history = History.resume(stored, comic);
    }
    if (_pendingRefresh) {
      _pendingRefresh = false;
      unawaited(_refreshDetails());
    }
    // The favorite-folder lookup is a second network request. Do not block the
    // first frame on it: render the source-provided status immediately and
    // refresh the icon when the lookup finishes.
    final favoriteData = comicSource.favoriteData;
    final loadFolders = favoriteData?.loadFolders;
    if (loadFolders == null || !comicSource.isLogged) return;
    final details = comic;
    unawaited(() async {
      final stopwatch = Stopwatch()..start();
      try {
        final res = await loadFolders(details.id);
        Log.info(
          "Comic details",
          "loadFolders ${widget.sourceKey}/${details.id} took "
              "${stopwatch.elapsedMilliseconds}ms",
        );
        if (!mounted ||
            widget.sourceKey != details.sourceKey ||
            widget.id != details.id) {
          return;
        }
        if (res.error || res.subData is! List) return;
        isFavorite = (res.subData as List).isNotEmpty;
        update();
      } catch (error, stack) {
        Log.error("Comic details", error, stack);
      }
    }());
  }

  /// Reloads the details from the source.
  ///
  /// Concurrent calls share one request, but a manual call must not be folded
  /// into a silent one that is already running: doing so dropped the spinner and
  /// the completion message, so tapping Refresh during the automatic reload that
  /// follows an old cache looked like it did nothing. A manual call now marks
  /// the shared run as manual, which is what makes the feedback appear.
  Future<void> _refreshDetails({bool manual = false}) {
    if (manual) _manualRefreshRequested = true;
    final running = _refreshingDetails;
    if (running != null) return running;
    final isManual = _manualRefreshRequested;
    _manualRefreshRequested = false;
    final future = _refreshDetailsInner(manual: isManual);
    _refreshingDetails = future.whenComplete(() {
      _refreshingDetails = null;
      // A tap that lands just after this run finished still deserves feedback;
      // the flag above makes the next run manual, and nothing else would start
      // it, so start one here.
      if (_manualRefreshRequested && mounted) {
        _manualRefreshRequested = false;
        unawaited(_refreshDetails(manual: true));
      }
    });
    return _refreshingDetails!;
  }

  /// Set while a manual reload is waiting to run; see [_refreshDetails].
  bool _manualRefreshRequested = false;

  Future<void> _refreshDetailsInner({required bool manual}) async {
    final loadComicInfo = ComicSource.find(widget.sourceKey)?.loadComicInfo;
    if (loadComicInfo == null) return;
    try {
      final stopwatch = Stopwatch()..start();
      final result = await loadComicInfo(widget.id);
      Log.info(
        "Comic details",
        "refresh ${widget.sourceKey}/${widget.id} took "
            "${stopwatch.elapsedMilliseconds}ms",
      );
      if (!mounted) return;
      if (result.error) {
        if (manual) {
          final message = result.errorMessage ?? 'Error'.tl;
          if (context.mounted) context.showMessage(message: message);
        }
        return;
      }
      final fresh = result.data;
      if (widget.sourceKey != fresh.sourceKey || widget.id != fresh.comicId) {
        return;
      }
      final previous = data;
      final next =
          (fresh.chapters == null || fresh.chapters!.length == 0) &&
              previous?.chapters != null &&
              previous!.chapters!.length > 0
          ? ComicDetailsCache.instance.withChapters(fresh, previous.chapters!)
          : fresh;
      setState(() {
        data = next;
        isLiked = next.isLiked ?? false;
        isFavorite = next.isFavorite ?? false;
      });
      unawaited(ComicDetailsCache.instance.write(next));
      // The indicator is the feedback; when it was started from the menu rather
      // than a pull there is otherwise no sign that anything happened, because
      // the source often returns the same chapters and nothing on screen moves.
      if (manual && context.mounted) {
        context.showMessage(message: 'Refreshed'.tl);
      }
    } catch (error, stack) {
      Log.error("Comic details", error, stack);
      if (manual && context.mounted) {
        context.showMessage(message: 'Error'.tl);
      }
    }
  }

  Iterable<Widget> buildTitle() sync* {
    yield SliverAppbar(
      title: AnimatedOpacity(
        opacity: showAppbarTitle ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Text(comic.title),
      ),
      actions: [
        // Only useful while this comic is not yet on the shelf: migrating is
        // how an old favorite is moved onto a source that still works.
        if (!isFavorite && !isAddToLocalFav)
          IconButton(
            tooltip: 'Migrate'.tl,
            onPressed: migrateFavorite,
            icon: const Icon(Icons.move_down),
          ),
        IconButton(
          tooltip: 'Favorite'.tl,
          onPressed: openFavPanel,
          icon: Icon(
            (isFavorite || isAddToLocalFav)
                ? Icons.bookmark
                : Icons.bookmark_border,
            color: (isFavorite || isAddToLocalFav)
                ? context.useTextColor(Colors.purple)
                : null,
          ),
        ),
        IconButton(
          onPressed: showMoreActions,
          icon: const Icon(Icons.more_vert),
        ),
      ],
    );

    yield const SliverPadding(padding: EdgeInsets.only(top: 8));

    // One row: cover on the left, and the title, source, information and last
    // reading stacked on the right, matching the compact layout.
    yield SliverLazyToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _viewCover(context),
              onLongPress: () => _saveCover(context),
              child: Hero(
                tag: "cover${widget.heroID}",
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: context.colorScheme.outlineVariant,
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  height: 144,
                  width: 144 * 0.72,
                  clipBehavior: Clip.antiAlias,
                  child: _cover == null
                      ? const SizedBox()
                      : AnimatedImage(
                          image: CachedImageProvider(
                            _cover!,
                            sourceKey: comic.sourceKey,
                            cid: comic.id,
                          ),
                          width: double.infinity,
                          height: double.infinity,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(comic.title, style: ts.s18),
                  if (comic.subTitle != null)
                    SelectableText(
                      comic.subTitle!,
                      style: ts.s14,
                    ).paddingVertical(4),
                  Text(
                    (ComicSource.find(comic.sourceKey)?.name) ?? '',
                    style: ts.s12,
                  ),
                  if (comic.stars != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          StarRating(
                            value: comic.stars!,
                            size: 16,
                            onTap: starRating,
                          ),
                          const SizedBox(width: 6),
                          Text(comic.stars!.toStringAsFixed(2), style: ts.s12),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildHeaderInfo(),
                  ),
                  // Reading progress belongs to the same column as the other
                  // information; a full-width row below the cover read as a
                  // separate band.
                  if (history != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.history,
                            size: 14,
                            color: context.useTextColor(Colors.teal),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _buildLastReadingText(),
                              style: ts.s12,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildActions() {
    final secondaryActions = <Widget>[
      // Comments sit before the like button: reading what others said is the
      // more common reason to look at this row, and the like button stays in the
      // same place it has always been on the right.
      if (comicSource.commentsLoader != null)
        ComicDetailActionButton(
          icon: const Icon(Icons.comment),
          text: (comic.commentCount ?? 'Comments'.tl).toString(),
          onPressed: showComments,
          iconColor: context.useTextColor(Colors.green),
        ),
      if (data!.isLiked != null)
        ComicDetailActionButton(
          icon: const Icon(Icons.favorite_border),
          activeIcon: const Icon(Icons.favorite),
          isActive: isLiked,
          text:
              ((data!.likesCount != null)
                      ? (data!.likesCount! + (isLiked ? 1 : 0))
                      : (isLiked ? 'Liked'.tl : 'Like'.tl))
                  .toString(),
          isLoading: isLiking,
          onPressed: likeOrUnlike,
          iconColor: context.useTextColor(Colors.red),
        ),
    ];

    // Reading moved to the floating button, so this section only carries the
    // source-provided actions and disappears when the source has none.
    if (secondaryActions.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return SliverLazyToBoxAdapter(
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: secondaryActions,
      ).fixHeight(48),
    );
  }

  String _buildLastReadingText() {
    final currentHistory = history!;
    final page = currentHistory.page <= 0 ? 1 : currentHistory.page;
    final chapters = comic.chapters;
    if (chapters == null || chapters.length == 0) {
      return "${"Last Reading".tl}: P$page";
    }

    String chapterTitle = "E${currentHistory.ep}";
    String chapterProgress;
    String? groupName;

    try {
      if (chapters.isGrouped) {
        final groupIndex = (currentHistory.group ?? 1)
            .clamp(1, chapters.groupCount)
            .toInt();
        final group = chapters.getGroupByIndex(groupIndex - 1);
        final groupChapterIndex = currentHistory.ep
            .clamp(1, group.length)
            .toInt();
        var globalChapterIndex = groupChapterIndex;
        for (int i = 0; i < groupIndex - 1; i++) {
          globalChapterIndex += chapters.getGroupByIndex(i).length;
        }
        chapterTitle = group.values.elementAt(groupChapterIndex - 1);
        chapterProgress = "Chapter @ep".tlParams({
          "ep": "$globalChapterIndex/${chapters.length}",
        });
        groupName = chapters.groups.elementAt(groupIndex - 1);
      } else {
        final chapterIndex = currentHistory.ep
            .clamp(1, chapters.length)
            .toInt();
        chapterTitle = chapters.titles.elementAt(chapterIndex - 1);
        chapterProgress = "Chapter @ep".tlParams({
          "ep": "$chapterIndex/${chapters.length}",
        });
      }
    } catch (_) {
      chapterProgress = "Chapter @ep".tlParams({"ep": currentHistory.ep});
    }

    final parts = [chapterProgress, ?groupName, chapterTitle, "P$page"];
    return "${"Last Reading".tl}: ${parts.join(" - ")}";
  }

  Widget _buildHeaderInfo() {
    final authors = <({String text, String namespace})>[];
    final tags = <({String text, String namespace})>[];
    for (final entry in comic.tags.entries) {
      for (final value in entry.value) {
        final item = (text: value, namespace: entry.key);
        if (isAuthorNamespace(entry.key)) {
          authors.add(item);
        } else if (!isReadOnlyComicInfoNamespace(entry.key)) {
          tags.add(item);
        }
      }
    }

    final update =
        comic.findUpdateTime() ?? comic.updateTime ?? comic.uploadTime;
    final rows = <Widget>[
      if (authors.isNotEmpty)
        _buildInfoRow(
          "Authors".tl,
          Colors.lightBlue,
          authors
              .map((item) => _buildTagText(item.text, item.namespace))
              .toList(),
        ),
      if (comic.maxPage != null)
        _buildInfoRow("Pages".tl, Colors.teal, [Text("${comic.maxPage!}")]),
      if (update != null && update.trim().isNotEmpty)
        _buildInfoRow("Update".tl, Colors.cyan, [
          Text(_formatInfoTime(update)),
        ]),
      if (tags.isNotEmpty)
        _buildInfoRow(
          "Tags".tl,
          Colors.pinkAccent,
          tags.map((item) => _buildTagText(item.text, item.namespace)).toList(),
        ),
      if (authors.isEmpty && comic.uploader != null)
        _buildInfoRow("Uploader".tl, Colors.orange, [Text(comic.uploader!)]),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _buildInfoRow(String label, Color color, List<Widget> values) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 12),
              child: Wrap(
                spacing: 0,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < values.length; i++) ...[
                    values[i],
                    if (i != values.length - 1)
                      Text(
                        " / ",
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagText(String text, String namespace) {
    final translated =
        appLocale.languageCode == "zh" && comicSource.enableTagsTranslate
        ? TagsTranslation.translationTagWithNamespace(
            text,
            namespace.toLowerCase(),
          )
        : text;
    final readOnly = isReadOnlyComicInfoNamespace(namespace);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: readOnly ? null : () => onTapTag(text, namespace),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: translated));
        context.showMessage(message: "Copied".tl);
      },
      child: Text(
        translated,
        style: TextStyle(
          fontSize: 12,
          color: readOnly
              ? context.colorScheme.onSurfaceVariant
              : context.colorScheme.primary,
        ),
      ).paddingHorizontal(2),
    );
  }

  String _formatInfoTime(String time) {
    final numeric = int.tryParse(time);
    if (numeric != null) {
      final milliseconds = numeric > 1000000000000 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
      ).toString().substring(0, 19);
    }
    if (time.contains("T") || time.contains("Z")) {
      return DateTime.tryParse(time)?.toString().substring(0, 19) ?? time;
    }
    return time;
  }

  Widget _buildHeaderDescription() {
    final description = comic.description;
    if (description == null || description.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style;
        // Collapsed shows a single line; the caret reveals the rest.
        final collapsedLines = 1;
        final painter = TextPainter(
          text: TextSpan(text: description, style: style),
          maxLines: collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        if (!canExpand) {
          // Short descriptions are not selectable-toggle targets; showing a
          // caret that does nothing was the old behaviour.
          return SelectableText(description).fixWidth(double.infinity);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _descriptionExpanded
                  ? SelectableText(description).fixWidth(double.infinity)
                  : Text(
                      description,
                      maxLines: collapsedLines,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
            // The whole footer is the target and the caret sits in the middle,
            // matching the expandable description users already know.
            InkWell(
              onTap: () {
                setState(() {
                  _descriptionExpanded = !_descriptionExpanded;
                });
              },
              child: SizedBox(
                height: 32,
                width: double.infinity,
                child: Center(
                  child: Icon(
                    _descriptionExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The description spans the full width under the cover row. The heading was
  /// removed: the text and its caret are self-explanatory.
  Widget buildDescription() {
    final description = comic.description;
    if (description == null || description.trim().isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return SliverLazyToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderDescription(),
            const SizedBox(height: 4),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget buildChapters() {
    if (comic.chapters == null) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return ComicChaptersView(
      chapters: comic.chapters!,
      // Read marks are independent of the history row: the chapter list stays
      // accurate after history is cleared or has never been written.
      readState: readState,
      downloadedChapters: downloadedChapters,
      onSelectionChanged: (selecting) {
        _chapterSelection.value = selecting;
        // The shell consumes the back gesture while this claim is held, so the
        // navigator never gets the chance to pop the comic.
        if (selecting) {
          BackInterceptor.register(_backClaim);
        } else {
          BackInterceptor.unregister(_backClaim);
        }
      },
      selectionResetToken: _chapterSelectionReset,
      // Tapping the chapter already in progress resumes its saved page;
      // any other chapter starts from its first page.
      readChapter: (chapter) {
        final current = history;
        final resumeHere = current != null && _isSameChapter(chapter, current);
        if (resumeHere) {
          // Pass the stored group straight through: defaulting it to 1 made a
          // non-grouped comic look grouped, and the reader then relocated the
          // chapter through the group table and lost the saved page.
          read(chapter, current.page, current.group);
        } else {
          read(chapter);
        }
      },
      markChaptersRead: (chapters, read) => _setChaptersRead(chapters, read),
      // Batch download and delete live in the selection bar, so the reader
      // picks the chapters and acts on them in one place.
      downloadChapters: comicSource.loadComicPages == null
          ? null
          : downloadSelectedChapters,
      deleteChapters: deleteSelectedChapters,
    );
  }

  /// Whether [chapter] is the one the saved position points at.
  bool _isSameChapter(int chapter, History saved) {
    final list = comic.chapters;
    if (list == null) return false;
    if (!list.isGrouped) return saved.ep == chapter;
    final position = list.positionAt(chapter);
    return saved.ep == position.chapter && saved.group == position.group;
  }

  /// Marks a batch of chapters read or unread without opening the reader.
  ///
  /// The marks are their own durable record, so this no longer has to write a
  /// history row: marking chapters on a comic that was never read would
  /// otherwise create a fake "last read" position, and clearing history would
  /// have thrown the marks away.
  Future<void> _setChaptersRead(Set<int> chapters, bool read) async {
    final list = comic.chapters;
    if (list == null || chapters.isEmpty) return;
    final type = ComicType(widget.sourceKey.hashCode);
    final manager = HistoryScope.read(context);
    final keys = <String>{};
    for (final chapter in chapters) {
      if (chapter < 1 || chapter > list.length) continue;
      final at = list.positionAt(chapter);
      keys.add(list.isGrouped ? '${at.group}-${at.chapter}' : '$chapter');
      // A grouped list may also carry the plain index from before it was
      // grouped; clear both so "unread" really shows as unread.
      if (!read) keys.add('$chapter');
    }
    if (keys.isEmpty) return;
    await manager.setChaptersRead(widget.id, type, keys, read: read);
    if (!mounted) return;
    history = manager.find(widget.id, type);
    update();
  }

  Widget buildThumbnails() {
    if (comic.thumbnails == null && comicSource.loadComicThumbnail == null) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return ComicThumbnails(
      comicId: comic.id,
      sourceKey: widget.sourceKey,
      initialThumbnails: comic.thumbnails ?? const [],
      loadComicThumbnail: comicSource.loadComicThumbnail,
      readPage: (page) => read(null, page),
    );
  }

  Widget buildRecommend() {
    if (comic.recommend == null || comic.recommend!.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: ListTile(title: Text("Related".tl))),
        SliverGridComics(comics: comic.recommend!),
      ],
    );
  }

  Widget buildComments() {
    if (comic.comments == null || comic.comments!.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    return ComicCommentsPreview(
      comments: comic.comments!,
      showMore: showComments,
    );
  }

  void _viewCover(BuildContext context) {
    final cover = _cover;
    if (cover == null) {
      return;
    }
    final imageProvider = CachedImageProvider(
      cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
    );

    context.to(
      () => ComicCoverViewer(
        imageProvider: imageProvider,
        title: comic.title,
        heroTag: "cover${widget.heroID}",
      ),
    );
  }

  void _saveCover(BuildContext context) {
    final cover = _cover;
    if (cover == null) return;
    final provider = CachedImageProvider(
      cover,
      sourceKey: comic.sourceKey,
      cid: comic.id,
    );
    unawaited(
      _saves.save(
        read: (scope) => readImageProvider(provider, scope: scope),
        name: 'cover',
      ),
    );
  }

  String? get _cover {
    final cover = widget.cover?.trim().isNotEmpty == true
        ? widget.cover
        : comic.cover;
    if (cover == null || cover.trim().isEmpty) {
      return null;
    }
    return cover;
  }
}

class _ComicPageLoadingPlaceHolder extends StatelessWidget {
  const _ComicPageLoadingPlaceHolder({
    this.cover,
    this.title,
    required this.sourceKey,
    required this.cid,
    this.heroID,
  });

  final String? cover;

  final String? title;

  final String sourceKey;

  final String cid;

  final int? heroID;

  @override
  Widget build(BuildContext context) {
    Widget buildContainer(
      double? width,
      double? height, {
      Color? color,
      double? radius,
    }) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: color ?? context.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius ?? 4),
        ),
      );
    }

    return Shimmer(
      color: context.isDarkMode ? Colors.grey.shade700 : Colors.white,
      child: Column(
        children: [
          Appbar(title: Text(""), backgroundColor: context.colorScheme.surface),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 16),
              buildImage(context),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title ?? "", style: ts.s18)
                    else
                      buildContainer(200, 25),
                    const SizedBox(height: 8),
                    buildContainer(80, 20),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (context.width < changePoint)
            Row(
              children: [
                Expanded(child: buildContainer(null, 36, radius: 18)),
                const SizedBox(width: 16),
                Expanded(child: buildContainer(null, 36, radius: 18)),
              ],
            ).paddingHorizontal(16),
          const Divider(),
          const SizedBox(height: 8),
          Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
            ).fixHeight(24).fixWidth(24),
          ),
        ],
      ),
    );
  }

  Widget buildImage(BuildContext context) {
    Widget child;
    if (cover?.trim().isNotEmpty == true) {
      child = AnimatedImage(
        image: CachedImageProvider(cover!, sourceKey: sourceKey, cid: cid),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    } else {
      child = const SizedBox();
    }

    return Hero(
      tag: "cover$heroID",
      child: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: context.colorScheme.outlineVariant,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        height: 144,
        width: 144 * 0.72,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
