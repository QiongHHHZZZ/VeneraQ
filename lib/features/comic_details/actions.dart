import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/side_bar.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/features/comic_details/archive_download_dialog.dart';
import 'package:venera_next/features/comic_details/comments_page.dart';
import 'package:venera_next/features/comic_details/favorite.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/favorites/favorites_api.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/download.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/features/search/search_shortcut.dart';
import 'package:venera_next/features/search/search_shortcuts.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/navigation_admission.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/routing/page_jump_target.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/features/comic_details/rating_dialog.dart';
import 'package:venera_next/features/comic_details/migrate_favorite_dialog.dart';
import 'package:venera_next/features/comic_details/comic_page.dart';
import 'package:venera_next/features/history/history_manager.dart';

abstract mixin class ComicPageActions {
  void update();

  BuildContext get context;

  MenuRouteController get contextMenus;

  bool isComicActive(ComicDetails value);

  ComicDetails get comic;

  ComicSource get comicSource => ComicSource.find(comic.sourceKey)!;

  History? get history;

  /// Lets the overflow menu trigger the page's own reload, which needs the
  /// page's request scope; the mixin cannot start one itself.
  VoidCallback? get onRefreshRequested => null;

  ComicDetails? _likingComic;

  bool get isLiking => _likingComic != null && isComicActive(_likingComic!);

  bool isLiked = false;

  Future<void> likeOrUnlike() async {
    if (isLiking) return;
    final target = comic;
    final wasLiked = isLiked;
    _likingComic = target;
    update();
    Res<bool> result;
    try {
      result = await comicSource.likeOrUnlikeComic!(target.id, wasLiked);
    } catch (error, stack) {
      result = Res.fromException(error, stack);
    } finally {
      if (identical(_likingComic, target)) _likingComic = null;
    }
    if (!isComicActive(target)) return;
    if (result.error) {
      final currentContext = context;
      if (currentContext.mounted) {
        currentContext.showMessage(message: result.errorMessage!);
      }
    } else {
      isLiked = !wasLiked;
    }
    update();
  }

  /// whether the comic is added to local favorite
  bool isAddToLocalFav = false;

  /// whether the comic is favorite on the server
  bool isFavorite = false;

  /// Adds the comic to the local favorites.
  ///
  /// Supplied by the page, which owns the persistence work. Downloading depends
  /// on being favorited, so the gate needs a way to satisfy itself; the default
  /// handles the common case and a caller may override it.
  Future<bool> Function()? addToFavorites;

  /// Adds the comic to a favorite folder, asking which one when there is a
  /// choice. Used by the download gate, which needs a definite answer rather
  /// than the fire-and-forget favourite button.
  Future<bool> addToFavoritesNow() async {
    final target = comic;
    final folders = FavoritesScope.read(context).folderNames;
    if (folders.length == 1) {
      await _addToOnlyFolder(folders.single);
    } else {
      // The panel owns the write and reports back through onFavorite; await the
      // reader's choice by watching the sidebar route settle.
      await showSideBar(
        appNavigation.rootContext,
        ComicFavoritePanel(
          cid: comic.id,
          type: comic.comicType,
          isFavorite: isFavorite,
          onFavorite: (local, network) {
            if (!isComicActive(target)) return;
            if (network != null) isFavorite = network;
            if (local != null) isAddToLocalFav = local;
            update();
          },
          favoriteItem: _toFavoriteItem(),
          updateTime: comic.findUpdateTime(),
          chapterCount: comic.chapters?.length,
        ),
      );
    }
    if (!isComicActive(target)) return false;
    return isAddToLocalFav;
  }

  /// Returns true when downloading may start, prompting to favorite first if
  /// this comic is not in the library yet.
  ///
  /// A download that is not favorited has nowhere to be found later: the shelf
  /// lists favorites, so the files would sit on the device with no entry to
  /// reopen them. The page supplies [addToFavorites] where the default does not
  /// fit.
  Future<bool> canDownload() async {
    if (isAddToLocalFav) return true;
    final target = comic;
    final owner = context;
    final confirmed = await showDialog<bool>(
      context: owner,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add to favorites first?'.tl),
        content: Text(
          'Downloaded chapters are only reachable from your library, so this '
                  'comic has to be favorited before it is downloaded.'
              .tl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Favorite and download'.tl),
          ),
        ],
      ),
    );
    if (confirmed != true || !isComicActive(target)) return false;
    final add = addToFavorites ?? addToFavoritesNow;
    final added = await add();
    if (!isComicActive(target)) return false;
    return added;
  }

  FavoriteItem _toFavoriteItem() {
    var tags = <String>[];
    for (var e in comic.tags.entries) {
      tags.addAll(e.value.map((tag) => '${e.key}:$tag'));
    }
    return FavoriteItem(
      id: comic.id,
      name: comic.title,
      coverPath: comic.cover,
      author: comic.subTitle ?? comic.uploader ?? '',
      type: comic.comicType,
      tags: tags,
    );
  }

  void openFavPanel() {
    final target = comic;
    final owner = context;
    // With one local folder there is nothing to choose: add or remove directly
    // instead of opening a panel whose only action is that.
    final folders = FavoritesScope.read(context).folderNames;
    if (folders.length == 1) {
      final folder = folders.single;
      if (isAddToLocalFav) {
        unawaited(_removeFromOnlyFolder(folder));
      } else {
        unawaited(_addToOnlyFolder(folder));
      }
      return;
    }
    showSideBar(
      appNavigation.rootContext,
      ComicFavoritePanel(
        cid: comic.id,
        type: comic.comicType,
        isFavorite: isFavorite,
        onFavorite: (local, network) {
          if (!owner.mounted || !isComicActive(target)) return;
          if (network != null) {
            isFavorite = network;
          }
          if (local != null) {
            isAddToLocalFav = local;
          }
          update();
        },
        favoriteItem: _toFavoriteItem(),
        updateTime: comic.findUpdateTime(),
        chapterCount: comic.chapters?.length,
      ),
    );
  }

  /// Removes this comic from [folder] without opening the favorite panel.
  Future<void> _removeFromOnlyFolder(String folder) async {
    final target = comic;
    final owner = context;
    final type = comic.comicType;
    final manager = FavoritesScope.read(context);
    final generation = manager.connectionGeneration;
    try {
      await AppDataOperations.instance.access(() async {
        if (!owner.mounted || !isComicActive(target)) return;
        if (manager.connectionGeneration != generation) {
          throw StateError('Favorites database changed. Try again.');
        }
        await manager.deleteComicWithId(folder, target.id, type);
      });
      if (!owner.mounted || !isComicActive(target)) return;
      isAddToLocalFav = false;
      update();
      owner.showMessage(
        message: 'Removed from @folder'.tlParams({'folder': folder}),
      );
    } catch (error, stack) {
      Log.error('Remove from favorite', error, stack);
      if (owner.mounted && isComicActive(target)) {
        owner.showMessage(message: error.toString());
      }
    }
  }

  /// Migrates a chosen favorite onto this comic, keeping its place and progress.
  ///
  /// The reader finds the replacement comic first (often by searching), opens it,
  /// then picks the old record here. Its folders, ordering, tags and reading
  /// position move onto this comic, and the old entry is removed, so the shelf
  /// keeps one entry, now pointing at a source that works.
  Future<void> migrateFavorite() async {
    final target = comic;
    final owner = context;
    if (!NavigationAdmission.allows(owner)) return;
    final newId = target.id;
    final newType = target.comicType;
    final picked = await showMigrateFavoriteDialog(
      owner,
      currentId: newId,
      currentSourceKey: target.sourceKey,
      currentTitle: target.title,
    );
    if (picked == null || !owner.mounted) return;
    final oldId = picked.id;
    final oldType = picked.type;
    if (oldId == newId && oldType == newType) return;
    final manager = FavoritesScope.read(owner);
    final generation = manager.connectionGeneration;
    final history = HistoryManager();
    final folders = List<String>.of(manager.folderNames);
    try {
      await AppDataOperations.instance.access(() async {
        if (manager.connectionGeneration != generation) {
          throw StateError('Favorites database changed. Try again.');
        }
        manager.moveFavoriteOnto(
          folders: folders,
          oldId: oldId,
          oldType: oldType,
          newId: newId,
          newType: newType,
        );
        await history.switchSource(oldId, oldType.value, newId, newType.value);
      });
      if (!owner.mounted) return;
      owner.showMessage(
        message: 'Moved @title here'.tlParams({'title': picked.title}),
      );
      // The page now owns a record that came from elsewhere; rebuild so the
      // favorite state and chapter list reflect the inherited data.
      appNavigation.mainNavigatorKey?.currentContext?.to(
        () => ComicPage(
          id: newId,
          sourceKey: target.sourceKey,
          title: target.title,
          cover: target.cover,
        ),
      );
    } catch (error, stack) {
      Log.error('Move favorite', error, stack);
      if (owner.mounted) {
        owner.showMessage(message: error.toString());
      }
    }
  }

  /// Adds this comic to [folder] without opening the favorite panel.
  Future<void> _addToOnlyFolder(String folder) async {
    final target = comic;
    final owner = context;
    final item = _toFavoriteItem();
    final updateTime = target.findUpdateTime();
    // The detail page already loaded the chapter list, so record its total now:
    // waiting for the next update check would leave the shelf badge empty.
    final chapterCount = target.chapters?.length;
    final manager = FavoritesScope.read(context);
    final generation = manager.connectionGeneration;
    try {
      await AppDataOperations.instance.access(() async {
        if (!owner.mounted || !isComicActive(target)) return;
        if (manager.connectionGeneration != generation) {
          throw StateError('Favorites database changed. Try again.');
        }
        await manager.addComic(
          folder,
          item,
          null,
          updateTime,
          chapterCount,
        );
      });
      if (!owner.mounted || !isComicActive(target)) return;
      isAddToLocalFav = true;
      update();
      owner.showMessage(
        message: 'Added to @folder'.tlParams({'folder': folder}),
      );
    } catch (error, stack) {
      Log.error('Add to favorite', error, stack);
      if (owner.mounted && isComicActive(target)) {
        owner.showMessage(message: error.toString());
      }
    }
  }

  /// read the comic
  ///
  /// [ep] the episode number, start from 1
  ///
  /// [page] the page number, start from 1
  ///
  /// [group] the chapter group number, start from 1
  void read([int? ep, int? page, int? group]) {
    appNavigation.rootContext
        .to(
          () => Reader(
            onClosed: ReaderSessionScope.onClosedOf(appNavigation.rootContext),
            type: comic.comicType,
            cid: comic.id,
            name: comic.title,
            chapters: comic.chapters,
            initialChapter: ep,
            initialPage: page,
            initialChapterGroup: group,
            // A cleared history can still supply the resume position, but that
            // entry has no title or cover. Merge it onto the details this page
            // just loaded instead of writing a blank metadata row back.
            history: History.resume(history, comic),
            author: comic.findAuthor() ?? '',
            tags: comic.plainTags,
          ),
        )
        .then((_) {
          onReadEnd();
        });
  }

  /// Opens the first chapter that has not been read yet.
  ///
  /// This is the library behaviour: "continue" targets the outstanding chapter
  /// rather than the last position, so jumping ahead mid-read does not strand
  /// the earlier chapters. With nothing unread it falls back to the last
  /// position, which is what re-opening a finished comic should do.
  void continueRead() {
    final chapters = comic.chapters;
    final current = history;
    // Read marks are their own record: they survive clearing history, so
    // "continue" still skips chapters finished earlier.
    final marks = HistoryManager().readMarks(comic.id, comic.comicType);
    if (chapters != null) {
      if (current != null) {
        // Resume the chapter already in progress before hunting for unread
        // ones. An unfinished chapter still counts as unread, so asking for the
        // next unread chapter would jump back to the earliest unread one and
        // throw away the saved page.
        final at = current.ep;
        if (at >= 1 && at <= chapters.length) {
          if (!chapters.isChapterRead(at, marks)) {
            read(at, current.page, current.group);
            return;
          }
        }
      }
      final next = chapters.nextUnreadChapter(marks);
      if (next != null) {
        final position = chapters.positionAt(next);
        // A null group means "not grouped", which keeps the reader from
        // re-mapping the chapter through the group table.
        read(next, 1, position.group);
        return;
      }
    }
    var ep = history?.ep ?? 1;
    var page = history?.page ?? 1;
    var group = history?.group;
    read(ep, page, group);
  }

  void onReadEnd();

  bool _choosingDownload = false;

  Future<void> download() async {
    if (_choosingDownload) return;
    final owner = context;
    if (!owner.mounted) return;
    final admission = WindowSelectionTask(owner);
    if (!admission.canPresent) return;
    final target = comic;
    final source = comicSource;
    final library = LocalManager();
    bool canContinue() => admission.canPresent && isComicActive(target);
    if (!canContinue()) return;
    _choosingDownload = true;
    try {
      if (library.isDownloading(target.id, target.comicType)) {
        owner.showMessage(message: "The comic is downloading".tl);
        return;
      }
      if (target.chapters == null &&
          library.isDownloaded(target.id, target.comicType, 0)) {
        owner.showMessage(message: "The comic is downloaded".tl);
        return;
      }
      // Favoriting is a precondition: an ungated download would leave files on
      // the device with no library entry to reopen them from.
      if (!await canDownload()) return;
      if (!canContinue() || !owner.mounted) return;

      if (source.archiveDownloader != null) {
        final selection = await showArchiveDownloadDialog(
          context: owner,
          downloader: source.archiveDownloader!,
          comicId: target.id,
        );
        if (!owner.mounted || !canContinue() || selection == null) {
          return;
        }
        if (selection.url != null) {
          if (library.isDownloading(target.id, target.comicType)) return;
          library.addTask(
            ArchiveDownloadTask(selection.url!, target, storage: library),
          );
          owner.showMessage(message: "Download started".tl);
          update();
          return;
        }
      }

      if (!owner.mounted || !canContinue()) return;
      if (library.isDownloading(target.id, target.comicType)) return;
      if (target.chapters == null) {
        library.addTask(
          ImagesDownloadTask(
            storage: library,
            source: source,
            comicId: target.id,
            comic: target,
          ),
        );
      } else {
        final chapterIds = List<String>.unmodifiable(target.chapters!.ids);
        final chapterTitles = List<String>.unmodifiable(
          target.chapters!.titles,
        );
        var downloaded = <int>[];
        var localComic = library.find(target.id, target.comicType);
        if (localComic != null) {
          for (int i = 0; i < chapterIds.length; i++) {
            if (localComic.downloadedChapters.contains(chapterIds[i])) {
              downloaded.add(i);
            }
          }
        }
        final selected = await showSideBar<List<int>>(
          owner,
          _SelectDownloadChapter(
            chapterTitles,
            List<int>.unmodifiable(downloaded),
            isCurrent: () =>
                owner.mounted && admission.active && isComicActive(target),
          ),
        );
        if (!owner.mounted || !canContinue() || selected == null) {
          return;
        }
        if (library.isDownloading(target.id, target.comicType)) return;
        library.addTask(
          ImagesDownloadTask(
            storage: library,
            source: source,
            comicId: target.id,
            comic: target,
            chapters: selected.map((i) => chapterIds[i]).toList(),
          ),
        );
      }
      owner.showMessage(message: "Download started".tl);
      update();
    } catch (error, stack) {
      Log.error('Download selection', error, stack);
      if (owner.mounted && canContinue()) {
        owner.showMessage(message: error.toString());
      }
    } finally {
      _choosingDownload = false;
    }
  }

  /// Queues the chapters the reader ticked, without opening the picker.
  ///
  /// The selection already names exactly what to download, so this is the same
  /// task [download] builds once a choice is made; chapters already stored are
  /// left out rather than downloaded twice.
  Future<void> downloadSelectedChapters(Set<int> chapters) async {
    final target = comic;
    final source = comicSource;
    final library = LocalManager();
    final list = target.chapters;
    if (list == null || chapters.isEmpty) return;
    if (source.loadComicPages == null) return;
    if (library.isDownloading(target.id, target.comicType)) {
      context.showMessage(message: "The comic is downloading".tl);
      return;
    }
    final local = library.find(target.id, target.comicType);
    final stored = local?.downloadedChapters.toSet() ?? const <String>{};
    final ids = <String>[];
    for (final chapter in chapters) {
      if (chapter < 1 || chapter > list.length) continue;
      final id = list.positionAt(chapter).id;
      if (stored.contains(id) || ids.contains(id)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) {
      context.showMessage(message: "The comic is downloaded".tl);
      return;
    }
    // Same precondition as the single-comic path: the selection is already
    // made, so ask before anything is written to disk.
    if (!await canDownload()) return;
    if (!isComicActive(target) || !context.mounted) return;
    library.addTask(
      ImagesDownloadTask(
        storage: library,
        source: source,
        comicId: target.id,
        comic: target,
        chapters: ids,
      ),
    );
    context.showMessage(message: "Download started".tl);
    update();
  }

  /// Deletes the stored pages of the chapters the reader ticked.
  ///
  /// Removal drops the queue entries for those chapters first, so a running
  /// download cannot keep writing into a directory that is being deleted.
  Future<void> deleteSelectedChapters(Set<int> chapters) async {
    final target = comic;
    final library = LocalManager();
    final list = target.chapters;
    if (chapters.isEmpty) return;
    final local = library.find(target.id, target.comicType);
    if (local == null) return;
    final ids = <String>{};
    if (list != null) {
      for (final chapter in chapters) {
        if (chapter < 1 || chapter > list.length) continue;
        ids.add(list.positionAt(chapter).id);
      }
    } else if (chapters.contains(1)) {
      // A comic stored as a single unit has no per-chapter ids to match.
      ids.addAll(local.downloadedChapters);
    }
    ids.retainWhere(local.downloadedChapters.contains);
    if (ids.isEmpty) return;
    for (final task in library.downloadingTasks.toList()) {
      if (task.comicType == target.comicType && task.id == target.id) {
        await library.cancelDownload(task);
      }
    }
    await library.deleteComicChapters(local, ids.toList());
    // The page owns the route; a retired one must not rebuild for a result it
    // no longer shows.
    if (!context.mounted) return;
    update();
  }

  void onTapTag(String tag, String namespace) {
    var target = searchTargetForTag(tag, namespace);
    var context = appNavigation.mainNavigatorKey!.currentContext!;
    target?.jump(context);
  }

  PageJumpTarget? searchTargetForTag(String tag, String namespace) {
    return comicSource.handleClickTagEvent?.call(namespace, tag);
  }

  void onLongPressTag(String tag, String namespace, BuildContext tagContext) {
    final target = comic;
    final renderBox = tagContext.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final shortcut = searchTargetForTag(tag, namespace) == null
        ? null
        : SearchShortcut(
            kind: isAuthorNamespace(namespace)
                ? SearchShortcutKind.author
                : SearchShortcutKind.tag,
            sourceKey: comic.sourceKey,
            namespace: namespace,
            value: tag,
          );
    showSearchShortcutMenu(
      menus: contextMenus,
      isValid: () => isComicActive(target),
      context: tagContext,
      location: Offset(
        offset.dx + renderBox.size.width / 2 - 121,
        offset.dy + renderBox.size.height - 8,
      ),
      copyText: tag,
      shortcut: shortcut,
    );
  }

  void showMoreActions() {
    final target = comic;
    // Downloading chapters moved to the batch actions in the chapter list, so
    // the overflow entry would only repeat it. It stays for the two cases the
    // chapter list cannot serve: a source that hands over a whole archive, and
    // a comic stored as a single unit with no chapters to pick.
    final batchCoversDownload =
        target.chapters != null && comicSource.loadComicPages != null;
    final needsDownloadEntry =
        comicSource.archiveDownloader != null || !batchCoversDownload;
    contextMenus.show(
      context,
      Offset(context.width - 16, context.padding.top),
      [
        if (needsDownloadEntry)
          MenuEntry(
            icon: Icons.download_outlined,
            text: "Download".tl,
            onClick: () {
              if (isComicActive(target)) download();
            },
          ),
        // Disabled rather than hidden when the source cannot reload: the entry
        // is still informative, but a tap must not look ignored.
        MenuEntry(
          icon: Icons.refresh,
          text: "Refresh".tl,
          enabled: onRefreshRequested != null,
          onClick: () {
            if (isComicActive(target)) onRefreshRequested?.call();
          },
        ),
        MenuEntry(
          icon: Icons.copy,
          text: "Copy Title".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: target.title));
            context.showMessage(message: "Copied".tl);
          },
        ),
        MenuEntry(
          icon: Icons.copy_rounded,
          text: "Copy ID".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: target.id));
            context.showMessage(message: "Copied".tl);
          },
        ),
        if (target.url != null)
          MenuEntry(
            icon: Icons.link,
            text: "Copy URL".tl,
            onClick: () {
              Clipboard.setData(ClipboardData(text: target.url!));
              context.showMessage(message: "Copied".tl);
            },
          ),
        if (target.url != null)
          MenuEntry(
            icon: Icons.open_in_browser,
            text: "Open in Browser".tl,
            onClick: () {
              launchUrlString(target.url!);
            },
          ),
      ],
      isValid: () => isComicActive(target),
    );
  }

  void showComments() {
    showSideBar(
      appNavigation.rootContext,
      CommentsPage(data: comic, source: comicSource),
    );
  }

  void starRating() {
    final source = comicSource;
    if (!source.isLogged) return;
    final id = comic.id;
    showDialog<void>(
      context: context,
      builder: (_) => ComicRatingDialog(
        submit: (rating) => source.starRatingFunc!(id, rating),
      ),
    );
  }
}

class _SelectDownloadChapter extends StatefulWidget {
  const _SelectDownloadChapter(
    this.eps,
    this.downloadedEps, {
    required this.isCurrent,
  });

  final List<String> eps;
  final List<int> downloadedEps;
  final bool Function() isCurrent;

  @override
  State<_SelectDownloadChapter> createState() => _SelectDownloadChapterState();
}

class _SelectDownloadChapterState extends State<_SelectDownloadChapter> {
  List<int> selected = [];
  WindowSelectionTask? _owner;
  NavigatorState? _navigator;
  Object _generation = Object();
  bool _confirming = false;

  /// Whether the list runs from the last chapter to the first.
  ///
  /// The picker used to render the source order only, which is the opposite of
  /// what a reader who keeps the chapter list descending sees on the page
  /// behind it. Seeded from that same preference, so both agree by default.
  late bool _reverse = _storedReverse;

  static bool get _storedReverse {
    final settings = appdata.settings;
    // A build from before the order became a choice stored a boolean under the
    // old key; it is only consulted when set, matching the chapter list.
    if (settings['reverseChapterOrder'] == true) return true;
    return GlobalPreferenceStore(settings).read(AppPreferences.chapterOrder) ==
        'descending';
  }

  /// One-based chapter index at display position [position].
  int _chapterAt(int position) =>
      _reverse ? widget.eps.length - position - 1 : position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A surviving sidebar never adopts a replacement application or window.
    _owner ??= WindowSelectionTask(context);
    _navigator ??= Navigator.of(context);
  }

  @override
  void didUpdateWidget(covariant _SelectDownloadChapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eps != widget.eps ||
        oldWidget.downloadedEps != widget.downloadedEps ||
        oldWidget.isCurrent != widget.isCurrent) {
      _generation = Object();
      selected = [];
    }
  }

  bool _canSelect(Object generation) =>
      mounted &&
      identical(generation, _generation) &&
      !_confirming &&
      _owner?.canPresent == true &&
      Navigator.maybeOf(context) == _navigator &&
      widget.isCurrent();

  void _submit(Object generation, List<int> selection) {
    if (!_canSelect(generation)) return;
    _confirming = true;
    try {
      _navigator!.pop<List<int>>(List<int>.unmodifiable(selection));
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final active = _canSelect(generation);
    final eps = widget.eps;
    final downloaded = widget.downloadedEps;
    // The order control sits at the right end of the title bar: it changes the
    // view the body below shows, so it belongs on the bar rather than as a row
    // of its own above the list. Icon-only segments keep it inside the bar's
    // remaining width, which the two-word labels overflowed on a narrow phone.
    final orderControl = Tooltip(
      message: 'Order'.tl,
      child: SegmentedButton<bool>(
        selected: {_reverse},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        ),
        segments: [
          ButtonSegment<bool>(
            value: false,
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Ascending'.tl,
          ),
          ButtonSegment<bool>(
            value: true,
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: 'Descending'.tl,
          ),
        ],
        onSelectionChanged: (chosen) {
          if (!active) return;
          setState(() => _reverse = chosen.first);
        },
      ),
    );
    return Scaffold(
      appBar: Appbar(
        title: Text("Download".tl),
        backgroundColor: context.colorScheme.surfaceContainerLow,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: orderControl),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: eps.length,
              itemBuilder: (context, position) {
                // Selection stays keyed to the real chapter, so reversing the
                // view never changes which chapter a tick refers to.
                final i = _chapterAt(position);
                return CheckboxListTile(
                  title: Text(eps[i]),
                  value: selected.contains(i) || downloaded.contains(i),
                  onChanged: !active || downloaded.contains(i)
                      ? null
                      : (v) {
                          if (!_canSelect(generation)) return;
                          setState(() {
                            if (selected.contains(i)) {
                              selected.remove(i);
                            } else {
                              selected.add(i);
                            }
                          });
                        },
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextButton(
                    onPressed: !active
                        ? null
                        : () {
                            // Source order, deliberately independent of the
                            // view: displaying descending must not reorder the
                            // queue, which callers and tests pin.
                            final res = <int>[];
                            for (var i = 0; i < eps.length; i++) {
                              if (!downloaded.contains(i)) res.add(i);
                            }
                            _submit(generation, res);
                          },
                    child: Text("Download All".tl),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: !active || selected.isEmpty
                        ? null
                        : () {
                            if (selected.isEmpty) return;
                            _submit(generation, selected);
                          },
                    child: Text("Download Selected".tl),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
