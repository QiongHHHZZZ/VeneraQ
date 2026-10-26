import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/preferences.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/selection_mode.dart';
import 'favorite_models.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/flyout.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/features/comic_details/comic_details.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/favorites/favorite_actions.dart';
import 'package:venera_next/features/favorites/favorites_constants.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/favorites/favorite_confirmation_dialog.dart';
import 'package:venera_next/features/favorites/favorite_transfer_dialog.dart';
import 'package:venera_next/features/favorites/shelf_toolbar.dart';
import 'package:venera_next/features/follow_updates/follow_updates_manager.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_locale.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/navigation_admission.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/consts.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/opencc.dart';
import 'package:venera_next/foundation/read_progress.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

/// If the number of comics in a folder exceeds this limit, it will be
/// fetched asynchronously.
const _asyncDataFetchLimit = 500;

class LocalFavoritesPage extends StatefulWidget {
  const LocalFavoritesPage({
    required this.folder,
    required this.showFolders,
    required this.onFolderSelected,
    required this.updateFolderList,
    this.importFolder = importNetworkFolder,
    super.key,
  });

  final String folder;
  final VoidCallback showFolders;
  final void Function(bool isNetwork, String? folder) onFolderSelected;
  final VoidCallback updateFolderList;
  final Future<void> Function(
    BuildContext context,
    String source,
    int pages,
    String folder,
    String remoteFolder,
  )
  importFolder;

  @override
  State<LocalFavoritesPage> createState() => _LocalFavoritesPageState();
}

class _LocalFavoritesPageState extends State<LocalFavoritesPage>
    with ContextMenuOwner {
  late List<FavoriteItem> comics;

  String? networkSource;
  String? networkFolder;

  Map<Comic, bool> selectedComics = {};

  String keyword = "";
  bool searchHasUpper = false;

  bool searchMode = false;

  /// Owned here so entering search from the navigation bar can focus and clear
  /// the field the page renders.
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  bool multiSelectMode = false;

  int? lastSelectedIndex;

  bool get isAllFolder => widget.folder == localAllFolderLabel;

  /// Whether the shelf currently lays its comics out as a grid.
  ///
  /// The list and the grid remember separate cover sizes, so picking the right
  /// one needs to know which arrangement is on screen.
  bool get shelfUsesGrid =>
      GlobalPreferenceStore(
        appdata.settings,
      ).read(FavoritePreferences.displayMode) ==
      'gallery';

  /// The folder this page shows, not the widget instance the parent rebuilt.
  ///
  /// The default `=> widget` identity retires an open folder menu on any parent
  /// rebuild, because every rebuild hands the state a new widget instance. The
  /// menu entries already re-read the live folder (`widget.folder ==
  /// target.folder`) before they act, so only a real retarget has to close it.
  @override
  Object? get contextMenuIdentity => widget.folder;

  LocalFavoritesManager get manager => _store.manager;

  late final FavoriteStoreBinding _store;

  late final LocalFavoritesManager _observedManager;
  late final int _observedGeneration;
  late final String _observedDataPath;
  WindowSelectionTask? _queryOwner;
  final _metadataTasks = <WindowSelectionTask>{};

  bool get _canReadObservedFolder =>
      mounted &&
      _queryOwner?.active == true &&
      _store.isCurrent &&
      _observedManager.connectionGeneration == _observedGeneration &&
      App.dataPath == _observedDataPath;

  bool isLoading = false;
  int _queryGeneration = 0;
  int _filterRequest = 0;
  Object? _loadError;

  late String readFilterSelect;

  late String sortSelect;

  var searchResults = <FavoriteItem>[];

  void updateSearchResult() {
    setState(() {
      if (keyword.trim().isEmpty) {
        searchResults = comics;
      } else {
        searchResults = [];
        for (var comic in comics) {
          if (matchKeyword(keyword, comic) ||
              matchKeywordT(keyword, comic) ||
              matchKeywordS(keyword, comic)) {
            searchResults.add(comic);
          }
        }
      }
    });
  }

  void updateComics() {
    if (!_canReadObservedFolder) return;
    final manager = _observedManager;
    final generation = ++_queryGeneration;
    final folder = widget.folder;
    _loadError = null;
    isLoading = false;
    try {
      final count = isAllFolder
          ? manager.totalComics
          : manager.folderComics(folder);
      if (!isAllFolder && !manager.existsFolder(folder)) {
        comics = [];
      } else if (count < _asyncDataFetchLimit) {
        comics = isAllFolder
            ? manager.getAllComics()
            : manager.getFolderComics(folder);
      } else {
        isLoading = true;
        final reading = isAllFolder
            ? manager.getAllComicsAsync()
            : manager.getFolderComicsAsync(folder);
        unawaited(
          reading.then<void>(
            (value) {
              if (!_canReadObservedFolder ||
                  generation != _queryGeneration ||
                  widget.folder != folder) {
                return;
              }
              setState(() {
                isLoading = false;
                comics = value;
              });
            },
            onError: (Object error, StackTrace stack) {
              Log.error('Favorites query', error, stack);
              if (!_canReadObservedFolder ||
                  generation != _queryGeneration ||
                  widget.folder != folder) {
                return;
              }
              setState(() {
                isLoading = false;
                _loadError = error;
              });
            },
          ),
        );
      }
    } catch (error, stack) {
      Log.error('Favorites query', error, stack);
      _loadError = error;
    }
    setState(() {});
  }

  /// Applies the shelf's filter and order. The unread view always ranks by
  /// remaining chapters so the list answers "what should I read next".
  List<FavoriteItem> filterComics(List<FavoriteItem> curComics) {
    final filtered = curComics.where((comic) {
      if (readFilterSelect == "Unread") {
        return _unreadChaptersOf(comic) > 0;
      }
      return true;
    }).toList();
    if (readFilterSelect == "Unread") {
      filtered.sort((a, b) {
        final byUnread = _unreadChaptersOf(b).compareTo(_unreadChaptersOf(a));
        if (byUnread != 0) return byUnread;
        return a.title.compareTo(b.title);
      });
      return filtered;
    }
    return applySort(filtered);
  }

  /// Orders the shelf by the user's choice. "Default" keeps the stored manual
  /// order, which is what the database already returned.
  List<FavoriteItem> applySort(List<FavoriteItem> comics) =>
      sortFavoriteComics(comics, sortSelect, unreadOf: _unreadChaptersOf);

  /// Chapters past the reader's position, matching the badge on the cover.
  int _unreadChaptersOf(FavoriteItem comic) {
    final type = ComicType(comic.sourceKey.hashCode);
    final total = _observedManager.chapterCountOf(comic.id, type);
    if (total == null || total <= 0) return 0;
    // Counted from the durable read marks, not the reading position: marking
    // chapters by hand updates only the marks, so a position-based count never
    // moved. The marks survive clearing history.
    final read = HistoryScope.read(context).readChapters(comic.id, type);
    return total - countReadChapters(read, total);
  }

  bool matchKeyword(String keyword, FavoriteItem comic) {
    var list = keyword.split(" ");
    for (var k in list) {
      if (k.isEmpty) continue;
      if (checkKeyWordMatch(k, comic.title, false)) {
        continue;
      } else if (comic.subtitle != null &&
          checkKeyWordMatch(k, comic.subtitle!, false)) {
        continue;
      } else if (comic.tags.any((tag) {
        if (checkKeyWordMatch(k, tag, true)) {
          return true;
        } else if (tag.contains(':') &&
            checkKeyWordMatch(k, tag.split(':')[1], true)) {
          return true;
        } else if (appLocale.languageCode != 'en' &&
            checkKeyWordMatch(k, tag.translateTagsToCN, true)) {
          return true;
        }
        return false;
      })) {
        continue;
      } else if (checkKeyWordMatch(k, comic.author, true)) {
        continue;
      }
      return false;
    }
    return true;
  }

  bool checkKeyWordMatch(String keyword, String compare, bool needEqual) {
    String temp = compare;
    // 没有大写的话, 就转成小写比较, 避免搜索需要注意大小写
    if (!searchHasUpper) {
      temp = temp.toLowerCase();
    }
    if (needEqual) {
      return keyword == temp;
    }
    return temp.contains(keyword);
  }

  // Convert keyword to traditional Chinese to match comics
  bool matchKeywordT(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseSimplified(keyword)) {
      return false;
    }
    keyword = OpenCC.simplifiedToTraditional(keyword);
    return matchKeyword(keyword, comic);
  }

  // Convert keyword to simplified Chinese to match comics
  bool matchKeywordS(String keyword, FavoriteItem comic) {
    if (!OpenCC.hasChineseTraditional(keyword)) {
      return false;
    }
    keyword = OpenCC.traditionalToSimplified(keyword);
    return matchKeyword(keyword, comic);
  }

  @override
  void initState() {
    super.initState();
    _store = FavoritesScope.capture(context);
    _observedManager = _store.manager;
    // The title bar owns the back gesture, so it needs a way to ask this page to
    // leave selection mode.
    SelectionModeNotifier.instance.leave = _leaveSelectionFromBar;
    _observedGeneration = _observedManager.connectionGeneration;
    _observedDataPath = App.dataPath;
    readFilterSelect =
        appdata.implicitData["local_favorites_read_filter"] ??
        readFilterList[0];
    sortSelect =
        appdata.implicitData["local_favorites_sort"] ?? sortSelectList[0];
    if (!isAllFolder) {
      var (a, b) = _observedManager.findLinked(widget.folder);
      networkSource = a;
      networkFolder = b;
    } else {
      networkSource = null;
      networkFolder = null;
    }
    comics = [];
    _observedManager.addListener(updateComics);
  }

  /// Publishes this page's controls to the navigation bar so the shelf keeps a
  /// single title bar. The bar drives the same inline search the page owns.
  void _publishToolbar() {
    if (!mounted) return;
    ShelfToolbar.instance.bind(
      folder: widget.folder == localAllFolderLabel ? 'All'.tl : widget.folder,
      hasFolders: true,
      filterActive:
          readFilterSelect != readFilterList[0] ||
          sortSelect != sortSelectList[0],
      searching: searchMode,
      openFolders: widget.showFolders,
      toggleSearch: _toggleSearch,
      // One button covers display, sort and filter; the toolbar keeps a single
      // "how is this list shown and ordered" entry.
      openDisplay: _openFilter,
      openFolderMenu: _showFolderMenu,
      canFolderMenu: !isAllFolder,
    );
  }

  void _toggleSearch() {
    if (!mounted) return;
    setState(() {
      if (searchMode) {
        searchMode = false;
        keyword = "";
        _searchController.clear();
      } else {
        keyword = "";
        searchMode = true;
        _searchController.clear();
        updateSearchResult();
      }
    });
    if (searchMode) {
      // Focus after the field is built this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && searchMode) _searchFocusNode.requestFocus();
      });
    }
    _publishToolbar();
  }

  /// Anchors the sync flyout. The page keeps a Flyout in its tree and shows it
  /// from the folder menu, which has no widget of its own to anchor to.
  final _syncFlyout = FlyoutController();

  /// Panel for the folder's network link, built on demand so it reads the
  /// current link instead of one captured when the menu opened.
  Widget _buildSyncPanel() {
    final source = networkSource!;
    final remoteFolder = networkFolder!;
    final folder = widget.folder;
    final importFolder = widget.importFolder;
    final generation = _observedManager.connectionGeneration;
    bool isCurrent() =>
        _canReadObservedFolder &&
        widget.folder == folder &&
        widget.importFolder == importFolder &&
        _observedManager.connectionGeneration == generation &&
        _observedManager.findLinked(folder) == (source, remoteFolder) &&
        NavigationAdmission.allows(context);
    return _FavoriteFolderSyncPanel(
      networkSource: source,
      networkFolder: remoteFolder,
      onUpdate: (pages) async {
        if (!isCurrent()) return;
        await importFolder(context, source, pages, folder, remoteFolder);
        if (isCurrent()) updateComics();
      },
    );
  }

  /// Sync the current network-favorite folder.
  ///
  /// Rename, reorder, export, metadata refresh and delete used to live here as
  /// well; those were removed, so this menu now serves only the action that has
  /// no other entry point.
  void _showFolderMenu() {
    if (networkSource == null || isAllFolder) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    contextMenus.show(
      context,
      Offset(origin.dx + box.size.width - 16, origin.dy + 16),
      [
        MenuEntry(
          icon: Icons.sync,
          text: "Sync".tl,
          onClick: () => _syncFlyout.show(),
        ),
      ],
    );
  }

  void _openFilter() {
    if (!mounted) return;
    final folder = widget.folder;
    final request = ++_filterRequest;
    showDialog(
      context: context,
      builder: (context) {
        return _LocalFavoritesFilterDialog(
          initReadFilterSelect: readFilterSelect,
          initSortSelect: sortSelect,
          updateConfig: (readFilter, sort) {
            if (!mounted ||
                widget.folder != folder ||
                request != _filterRequest) {
              return;
            }
            setState(() {
              readFilterSelect = readFilter;
              sortSelect = sort;
            });
            updateComics();
            _publishToolbar();
          },
        );
      },
    ).then((_) {
      // Cover size and list/grid are read while the shelf builds, so a change
      // made in the dialog only shows once this page rebuilds. The grids listen
      // to settings too, but the write lands after the dialog already repainted.
      if (mounted && widget.folder == folder) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_queryOwner != null) return;
    _queryOwner = WindowSelectionTask(context);
    updateComics();
  }

  @override
  void didUpdateWidget(LocalFavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder != widget.folder) {
      _cancelMetadataUpdates();
      _filterRequest++;
      final linked = isAllFolder || !_canReadObservedFolder
          ? (null, null)
          : _observedManager.findLinked(widget.folder);
      networkSource = linked.$1;
      networkFolder = linked.$2;
      updateComics();
    }
  }

  @override
  void dispose() {
    _cancelMetadataUpdates();
    // A retired shelf must not answer a back gesture that now belongs to a
    // different page.
    SelectionModeNotifier.instance
      ..leave = null
      ..setActive(false);
    // A refresh whose page is gone must stop issuing source requests and must
    // not report back into a retired shelf.
    _chapterJob?.cancel();
    _chapterResultTimer?.cancel();
    _observedManager.removeListener(updateComics);
    _searchController.dispose();
    _searchFocusNode.dispose();
    ShelfToolbar.instance.unbind(keepFolderOpener: true);
    scrollController.dispose();
    super.dispose();
  }

  void selectAll() {
    setState(() {
      if (searchMode) {
        selectedComics = searchResults.asMap().map((k, v) => MapEntry(v, true));
      } else {
        selectedComics = comics.asMap().map((k, v) => MapEntry(v, true));
      }
    });
  }

  void invertSelection() {
    setState(() {
      if (searchMode) {
        for (var c in searchResults) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      } else {
        for (var c in comics) {
          if (selectedComics.containsKey(c)) {
            selectedComics.remove(c);
          } else {
            selectedComics[c] = true;
          }
        }
      }
    });
  }

  bool downloadComic(FavoriteItem c) {
    final library = LocalManager();
    var source = c.type.comicSource;
    if (source != null) {
      bool isDownloaded = library.isDownloaded(c.id, (c).type);
      if (isDownloaded) {
        return false;
      }
      library.addTask(
        ImagesDownloadTask(
          storage: library,
          source: source,
          comicId: c.id,
          comicTitle: c.title,
        ),
      );
      return true;
    }
    return false;
  }

  void downloadSelected() {
    int count = 0;
    for (var c in selectedComics.keys) {
      if (downloadComic(c as FavoriteItem)) {
        count++;
      }
    }
    if (count > 0) {
      context.showMessage(
        message: "Added @c comics to download queue.".tlParams({"c": count}),
      );
    }
  }

  /// Whether any of [comics] has stored chapters on the device.
  ///
  /// The shelf's delete-downloads action has nothing to remove otherwise, so it
  /// is disabled rather than opening a confirmation for a no-op.
  bool _selectionHasDownloads(List<FavoriteItem> comics) {
    final library = LocalManager();
    for (final comic in comics) {
      final local = library.find(comic.id, comic.type);
      if (local != null && local.downloadedChapters.isNotEmpty) return true;
    }
    return false;
  }

  /// Removes the downloaded files of the selected comics.
  ///
  /// This is about the library, not the favorites, so it applies the same way
  /// in the "All" view as in a named folder. Nothing is removed from the
  /// favorites: the comic stays on the shelf and can be downloaded again.
  Future<void> deleteSelectedDownloads(List<FavoriteItem> comics) async {
    if (comics.isEmpty) return;
    final owner = _queryOwner;
    if (owner?.canPresent != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete downloaded?'.tl),
        content: Text(
          'The downloaded chapters of @c comics are removed from the '
                  'device. The comics stay in your library.'
              .tlParams({'c': comics.length}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete'.tl),
          ),
        ],
      ),
    );
    if (confirmed != true || owner?.canPresent != true) return;
    final library = LocalManager();
    var count = 0;
    for (final comic in comics) {
      if (!_canReadObservedFolder) return;
      final local = library.find(comic.id, comic.type);
      if (local == null) continue;
      // Drop any running task first, so a download cannot keep writing into a
      // directory that is about to be deleted.
      for (final task in library.downloadingTasks.toList()) {
        if (task.comicType == comic.type && task.id == comic.id) {
          await library.cancelDownload(task);
        }
      }
      await library.deleteComic(local);
      count++;
    }
    if (!mounted) return;
    _cancel();
    if (count > 0) {
      context.showMessage(
        message: 'Deleted downloads of @c comics.'.tlParams({'c': count}),
      );
    }
  }

  var scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final target = widget;
    final selection = selectedComics.keys.cast<FavoriteItem>().toList();
    final selectedItems = selection.map((comic) => comic.detached()).toList();
    bool isCurrentSelection() =>
        _canReadObservedFolder &&
        widget.folder == target.folder &&
        multiSelectMode &&
        listEquals(selectedComics.keys.toList(), selection);
    var title = widget.folder;
    if (title == localAllFolderLabel) {
      title = "All".tl;
    }

    _publishToolbar();

    Widget body = SmoothCustomScrollView(
      controller: scrollController,
      // A folder with only a few comics is shorter than the viewport, and an
      // under-filled list cannot overscroll: without this the pull-to-refresh
      // below never fires, so the page looked like it had no refresh at all.
      additionalPhysics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Nothing is drawn here while browsing: the navigation bar holds the
        // title and every action, so this page shows only its grid.
        if (multiSelectMode)
          SliverAppbar(
            style: context.width < changePoint
                ? AppbarStyle.shadow
                : AppbarStyle.blur,
            leading: Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _setSelecting(false);
                    selectedComics.clear();
                  });
                },
              ),
            ),
            title: Text(
              "Selected @c comics".tlParams({"c": selectedComics.length}),
            ),
            actions: [
              MenuButton(
                entries: [
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.drive_file_move,
                      text: "Move to folder".tl,
                      onClick: () {
                        if (_queryOwner?.canPresent != true ||
                            !isCurrentSelection()) {
                          return;
                        }
                        showFavoriteTransferDialog(
                          context: context,
                          manager: _observedManager,
                          source: target.folder,
                          comics: selectedItems,
                          move: true,
                          isCurrent: isCurrentSelection,
                          onCommitted: _cancel,
                        );
                      },
                    ),
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.copy,
                      text: "Copy to folder".tl,
                      onClick: () {
                        if (_queryOwner?.canPresent != true ||
                            !isCurrentSelection()) {
                          return;
                        }
                        showFavoriteTransferDialog(
                          context: context,
                          manager: _observedManager,
                          source: target.folder,
                          comics: selectedItems,
                          move: false,
                          isCurrent: isCurrentSelection,
                          onCommitted: _cancel,
                        );
                      },
                    ),
                  MenuEntry(
                    icon: Icons.select_all,
                    text: "Select All".tl,
                    onClick: selectAll,
                  ),
                  MenuEntry(
                    icon: Icons.deselect,
                    text: "Deselect".tl,
                    onClick: _cancel,
                  ),
                  MenuEntry(
                    icon: Icons.flip,
                    text: "Invert Selection".tl,
                    onClick: invertSelection,
                  ),
                  if (!isAllFolder)
                    MenuEntry(
                      icon: Icons.delete_outline,
                      text: "Delete Comic".tl,
                      color: context.colorScheme.error,
                      onClick: () {
                        if (_queryOwner?.canPresent != true ||
                            !isCurrentSelection()) {
                          return;
                        }
                        confirmFavoriteMutation(
                          context: context,
                          manager: _observedManager,
                          folder: target.folder,
                          title: "Delete".tl,
                          content: "Delete @c comics?".tlParams({
                            "c": selectedItems.length,
                          }),
                          btnColor: context.colorScheme.error,
                          isCurrent: isCurrentSelection,
                          mutate: () => _observedManager.batchDeleteComics(
                            target.folder,
                            selectedItems,
                          ),
                          onCommitted: _cancel,
                        );
                      },
                    )
                  // "All" gathers comics from every folder, so removing them
                  // from "the current folder" is not defined; this drops every
                  // membership instead.
                  else
                    MenuEntry(
                      icon: Icons.bookmark_remove_outlined,
                      text: "Remove from favorites".tl,
                      color: context.colorScheme.error,
                      onClick: () {
                        if (_queryOwner?.canPresent != true ||
                            !isCurrentSelection()) {
                          return;
                        }
                        confirmFavoriteMutation(
                          context: context,
                          manager: _observedManager,
                          folder: target.folder,
                          title: "Remove from favorites".tl,
                          content: "Remove @c comics from your library?"
                              .tlParams({"c": selectedItems.length}),
                          btnColor: context.colorScheme.error,
                          isCurrent: isCurrentSelection,
                          mutate: () => _observedManager.batchRemoveFromLibrary(
                            selectedItems,
                          ),
                          onCommitted: _cancel,
                        );
                      },
                    ),
                  MenuEntry(
                    icon: Icons.download,
                    text: "Download".tl,
                    onClick: downloadSelected,
                  ),
                  // Removing downloads works on the library rather than on a
                  // folder, so it means the same thing in "All" as anywhere
                  // else and is offered in both. It is greyed out unless one of
                  // the selected comics actually has stored chapters.
                  MenuEntry(
                    icon: Icons.delete_sweep_outlined,
                    text: "Delete downloads".tl,
                    enabled: _selectionHasDownloads(selectedItems),
                    onClick: () => deleteSelectedDownloads(selectedItems),
                  ),
                ],
              ),
            ],
          )
        else if (searchMode)
          SliverAppbar(
            style: context.width < changePoint
                ? AppbarStyle.shadow
                : AppbarStyle.blur,
            leading: Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSearch,
              ),
            ),
            title: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search".tl,
                border: UnderlineInputBorder(),
              ),
              onChanged: (v) {
                keyword = v;
                searchHasUpper = keyword.contains(RegExp(r'[A-Z]'));
                updateSearchResult();
              },
            ).paddingBottom(8).paddingRight(8),
          ),
        if (_loadError != null)
          SliverToBoxAdapter(
            child: Column(
              children: [
                Text(_loadError.toString()),
                TextButton(onPressed: updateComics, child: Text('Retry'.tl)),
              ],
            ),
          )
        else if (isLoading)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: const Center(child: CircularProgressIndicator()),
            ),
          )
        else
          SliverGridComics(
            comics: searchMode ? searchResults : filterComics(comics),
            selections: selectedComics,
            useFavoriteDisplaySettings: true,
            // The shelf owns its own cover size, so resizing covers on an
            // Explore page no longer resizes the shelf. The list and the grid
            // keep separate values, matching what the display dialog edits.
            tileScale: coverSizeScale(
              GlobalPreferenceStore(appdata.settings).read(
                shelfUsesGrid
                    ? FavoritePreferences.tileScale
                    : FavoritePreferences.listTileScale,
              ),
            ),
            menuBuilder: (c) {
              return [
                if (!isAllFolder)
                  MenuEntry(
                    icon: Icons.delete,
                    text: "Delete".tl,
                    onClick: () async {
                      if (!_canReadObservedFolder ||
                          _queryOwner?.canPresent != true ||
                          widget.folder != target.folder) {
                        return;
                      }
                      final item = (c as FavoriteItem).detached();
                      final owner = WindowSelectionTask(context);
                      try {
                        await owner.run<void>((operation) async {
                          operation.checkActive();
                          await AppDataOperations.instance.access(() async {
                            // An accepted deletion may outlive its page, but
                            // cannot enter a replacement database after queuing.
                            if (!_store.isCurrent ||
                                _observedManager.connectionGeneration !=
                                    _observedGeneration ||
                                App.dataPath != _observedDataPath ||
                                !_observedManager.existsFolder(target.folder)) {
                              throw const SelectionCancelled();
                            }
                            await _observedManager.deleteComicWithId(
                              target.folder,
                              item.id,
                              item.type,
                            );
                          });
                        }, reportFailureOnClose: true);
                      } on SelectionCancelled {
                        // The original caller or database retired before admission.
                      } catch (error, stack) {
                        Log.error('Delete favorite', error, stack);
                        if (context.mounted &&
                            owner.canPresent &&
                            _canReadObservedFolder &&
                            widget.folder == target.folder) {
                          context.showMessage(message: error.toString());
                        }
                      }
                    },
                  ),
                MenuEntry(
                  icon: Icons.check,
                  text: "Select".tl,
                  onClick: () {
                    setState(() {
                      if (!multiSelectMode) {
                        _setSelecting(true);
                      }
                      if (selectedComics.containsKey(c as FavoriteItem)) {
                        selectedComics.remove(c);
                      } else {
                        selectedComics[c] = true;
                      }
                      lastSelectedIndex = comics.indexOf(c);
                    });
                  },
                ),
                MenuEntry(
                  icon: Icons.download,
                  text: "Download".tl,
                  onClick: () {
                    downloadComic(c as FavoriteItem);
                    context.showMessage(message: "Download started".tl);
                  },
                ),
                if (GlobalPreferenceStore(
                      appdata.settings,
                    ).read(FavoritePreferences.onClickFavorite) ==
                    "viewDetail")
                  MenuEntry(
                    icon: Icons.menu_book_outlined,
                    text: "Read".tl,
                    onClick: () {
                      appNavigation.mainNavigatorKey?.currentContext?.to(
                        () =>
                            ReaderWithLoading(id: c.id, sourceKey: c.sourceKey),
                      );
                    },
                  ),
              ];
            },
            onTap: (c, heroID) {
              if (multiSelectMode) {
                setState(() {
                  if (selectedComics.containsKey(c as FavoriteItem)) {
                    selectedComics.remove(c);
                  } else {
                    selectedComics[c] = true;
                  }
                  lastSelectedIndex = comics.indexOf(c);
                });
              } else if (GlobalPreferenceStore(
                    appdata.settings,
                  ).read(FavoritePreferences.onClickFavorite) ==
                  "viewDetail") {
                appNavigation.mainNavigatorKey?.currentContext?.to(
                  () => ComicPage(
                    id: c.id,
                    sourceKey: c.sourceKey,
                    cover: c.cover,
                    title: c.title,
                    heroID: heroID,
                  ),
                );
              } else {
                appNavigation.mainNavigatorKey?.currentContext?.to(
                  () => ReaderWithLoading(id: c.id, sourceKey: c.sourceKey),
                );
              }
            },
            onLongPressed: (c, heroID) {
              setState(() {
                if (!multiSelectMode) {
                  _setSelecting(true);
                  if (!selectedComics.containsKey(c as FavoriteItem)) {
                    selectedComics[c] = true;
                  }
                  lastSelectedIndex = comics.indexOf(c);
                } else {
                  if (lastSelectedIndex != null) {
                    int start = lastSelectedIndex!;
                    int end = comics.indexOf(c as FavoriteItem);
                    if (start > end) {
                      int temp = start;
                      start = end;
                      end = temp;
                    }

                    for (int i = start; i <= end; i++) {
                      if (i == lastSelectedIndex) continue;

                      var comic = comics[i];
                      if (selectedComics.containsKey(comic)) {
                        selectedComics.remove(comic);
                      } else {
                        selectedComics[comic] = true;
                      }
                    }
                  }
                  lastSelectedIndex = comics.indexOf(c as FavoriteItem);
                }
              });
            },
          ),
      ],
    );
    body = AppScrollBar(
      topPadding: 48,
      controller: scrollController,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: body,
      ),
    );
    if (!multiSelectMode && !searchMode) {
      // Pulling down refreshes chapter counts and update flags, replacing the
      // removed follow-up updates tab.
      body = RefreshIndicator(
        onRefresh: () => _checkChapters(target.folder),
        child: body,
      );
    }
    // The sync flyout is anchored here; the folder menu shows it on demand,
    // since a menu entry has no widget of its own to anchor to.
    body = Flyout(
      controller: _syncFlyout,
      flyoutBuilder: (context) => _buildSyncPanel(),
      child: body,
    );
    // A running refresh keeps a determinate banner above the grid; its result
    // replaces it for a few seconds so the pull never ends silently.
    if (_chapterProgress != null || _chapterResult != null) {
      body = Column(
        children: [
          _ShelfRefreshBanner(
            progress: _chapterProgress,
            result: _chapterResult,
          ),
          Expanded(child: body),
        ],
      );
    }
    return PopScope(
      canPop: !multiSelectMode && !searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            _setSelecting(false);
            selectedComics.clear();
          });
        } else if (searchMode) {
          setState(() {
            searchMode = false;
            keyword = "";
            updateComics();
          });
        }
      },
      child: body,
    );
  }

  void _cancelMetadataUpdates() {
    for (final task in _metadataTasks.toList()) {
      task.cancel();
    }
  }

  bool _checkingChapters = false;
  FollowUpdateJob? _chapterJob;
  UpdateProgress? _chapterProgress;
  String? _chapterResult;
  Timer? _chapterResultTimer;

  /// Refreshes every favorite folder's chapters, like a library update scan.
  /// The shelf aggregates folders, so one pull checks all of them in a single
  /// bounded-concurrency pass instead of finishing one folder after another,
  /// and reports its progress while it runs.
  Future<void> _checkChapters(String folder) async {
    if (_checkingChapters) return;
    final manager = _observedManager;
    final generation = _observedGeneration;
    final dataPath = _observedDataPath;
    final folders = manager.folderNames;
    if (folders.isEmpty) return;
    bool isCurrent() =>
        _canReadObservedFolder &&
        manager.connectionGeneration == generation &&
        App.dataPath == dataPath;
    _checkingChapters = true;
    _chapterResultTimer?.cancel();
    _chapterResultTimer = null;
    var preparedErrors = 0;
    var updated = 0;
    var errors = 0;
    var skipped = 0;
    FollowUpdateJob? job;
    try {
      final targets = <ShelfUpdateTarget>[];
      for (final target in folders) {
        if (!isCurrent()) return;
        try {
          // Every folder records its own totals and update flags, so the badge
          // works on the aggregated shelf instead of only the tracked folder.
          await manager.prepareTableForFollowUpdates(
            target,
            clearData: false,
            generation: generation,
            isCurrent: isCurrent,
          );
        } catch (error, stack) {
          Log.error('Check Updates', error, stack);
          preparedErrors++;
          continue;
        }
        for (final comic in manager.getComicsWithUpdatesInfo(target)) {
          targets.add(ShelfUpdateTarget(target, comic));
        }
      }
      if (!isCurrent()) return;
      // One job owns the whole shelf: it cancels a previous refresh, reports
      // real processed/total progress and skips comics checked recently.
      job = _chapterJob = FollowUpdateJob.shelf(
        targets: targets,
        manager: manager,
        isCurrent: isCurrent,
      );
      await for (final progress in job.progress) {
        updated = progress.updated;
        errors = progress.errors;
        skipped = progress.skipped;
        if (mounted) {
          setState(() => _chapterProgress = progress);
        }
      }
    } catch (error, stack) {
      Log.error('Check Updates', error, stack);
      preparedErrors++;
    } finally {
      _checkingChapters = false;
      if (identical(_chapterJob, job)) _chapterJob = null;
      if (mounted) {
        setState(() => _chapterProgress = null);
      }
    }
    // A retired or replaced page keeps its result to itself; a cancelled job
    // stopped before its remaining comics, so it reports nothing.
    if (!mounted || job == null || job.isCancelled) return;
    updateComics();
    final summary = _chapterSummary(updated, errors + preparedErrors, skipped);
    context.showMessage(message: summary);
    setState(() => _chapterResult = summary);
    _chapterResultTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _chapterResult = null);
      }
    });
  }

  /// The one result line shown as a toast and as the banner's last frame.
  String _chapterSummary(int updated, int errors, int skipped) {
    if (skipped > 0) {
      return errors > 0
          ? 'Updated @u comics, @e failed, @s skipped'.tlParams({
              'u': updated,
              'e': errors,
              's': skipped,
            })
          : 'Updated @u comics, @s skipped'.tlParams({
              'u': updated,
              's': skipped,
            });
    }
    return errors > 0
        ? 'Updated @u comics, @e failed'.tlParams({'u': updated, 'e': errors})
        : 'Updated @u comics'.tlParams({'u': updated});
  }

  /// Updates the selection mode and tells the title bar, which owns the back
  /// gesture: a page cannot refuse one from inside the navigator.
  void _setSelecting(bool value) {
    multiSelectMode = value;
    SelectionModeNotifier.instance.setActive(value);
  }

  /// Leaves selection mode when the title bar consumes a back gesture.
  void _leaveSelectionFromBar() {
    if (!mounted || !multiSelectMode) return;
    _cancel();
  }

  void _cancel() {
    setState(() {
      selectedComics.clear();
      _setSelecting(false);
    });
  }
}

class _ShelfRefreshBanner extends StatelessWidget {
  const _ShelfRefreshBanner({required this.progress, required this.result});

  /// The latest counters while the refresh runs; `null` once it has finished.
  final UpdateProgress? progress;

  /// The finished refresh's result line, shown briefly after completion.
  final String? result;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final scheme = context.colorScheme;
    final secondary = <String>[
      if ((progress?.skipped ?? 0) > 0)
        'Skipped @s comics checked in the last @m minutes'.tlParams({
          's': progress!.skipped,
          'm': shelfRefreshSkipWindow.inMinutes,
        }),
      if ((progress?.errors ?? 0) > 0)
        '@count failed'.tlParams({'count': progress!.errors}),
    ].join(' · ');
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress == null
                  ? (result ?? '')
                  : 'Refreshing comics: @current/@total'.tlParams({
                      'current': progress.current,
                      'total': progress.total,
                    }),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.fraction,
                backgroundColor: scheme.onSecondaryContainer.withValues(
                  alpha: 0.16,
                ),
              ),
            ],
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                secondary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FavoriteFolderSyncPanel extends StatefulWidget {
  const _FavoriteFolderSyncPanel({
    required this.networkSource,
    required this.networkFolder,
    required this.onUpdate,
  });

  final Future<void> Function(int pages) onUpdate;
  final String networkFolder;
  final String networkSource;

  @override
  State<_FavoriteFolderSyncPanel> createState() =>
      _FavoriteFolderSyncPanelState();
}

class _FavoriteFolderSyncPanelState
    extends SettingsSaveState<_FavoriteFolderSyncPanel> {
  int updatePageNum = 9999999;
  bool startingUpdate = false;
  late final Future<void> Function(int) _update;

  Future<void> _submit() async {
    if (startingUpdate || !acceptsSettingsChanges) return;
    final pages = updatePageNum;
    final update = _update;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    setState(() => startingUpdate = true);
    try {
      await waitForSettingsSave();
      if (!mounted ||
          !acceptsSettingsChanges ||
          route?.isCurrent != true ||
          !NavigationAdmission.allows(context)) {
        return;
      }
      if (!await navigator.maybePop() || route?.isCurrent == true) return;
      await update(pages);
    } catch (error, stack) {
      Log.error('Favorite update settings', error, stack);
      if (mounted) context.showMessage(message: error.toString());
    } finally {
      if (mounted) setState(() => startingUpdate = false);
    }
  }

  String get _allPageText => 'All'.tl;

  static const pageCounts = [1, 2, 3, 5, 10, 20, 50, 100, 200, 9999999];

  @override
  void initState() {
    _update = widget.onUpdate;
    final stored = appdata.implicitData['local_favorites_update_page_num'];
    updatePageNum = stored is int && stored > 0 ? stored : 9999999;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var source = ComicSource.find(widget.networkSource);
    final sourceName = source?.name ?? widget.networkSource;
    var text = "The folder is Linked to @source".tlParams({
      "source": sourceName,
    });
    if (widget.networkFolder.isNotEmpty) {
      text += "\n${"Source Folder".tl}: ${widget.networkFolder}";
    }

    final target = (widget.networkSource, widget.networkFolder);
    return protectSettings(
      FlyoutContent(
        title: 'Sync'.tl,
        actions: [
          FilledButton(
            onPressed: startingUpdate ? null : _submit,
            child: Text('Update'.tl),
          ),
        ],
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text("Update the page number by the latest collection".tl),
                Select(
                  current: updatePageNum.toString() == '9999999'
                      ? _allPageText
                      : updatePageNum.toString(),
                  values: [
                    for (final value in pageCounts)
                      value == 9999999 ? _allPageText : '$value',
                  ],
                  minWidth: 48,
                  onTap: (index) {
                    if (!mounted ||
                        !acceptsSettingsChanges ||
                        startingUpdate ||
                        target !=
                            (widget.networkSource, widget.networkFolder) ||
                        index < 0 ||
                        index >= pageCounts.length) {
                      return;
                    }
                    final value = pageCounts[index];
                    setState(() {
                      updatePageNum = value;
                    });
                    saveSetting(
                      'local_favorites_update_page_num',
                      () => appdata.updateImplicit((draft) {
                        draft['local_favorites_update_page_num'] = value;
                      }),
                    );
                  },
                ),
              ],
            ),
            settingsSaveStatus,
          ],
        ),
      ),
    );
  }
}

class _LocalFavoritesFilterDialog extends StatefulWidget {
  const _LocalFavoritesFilterDialog({
    required this.initReadFilterSelect,
    required this.initSortSelect,
    required this.updateConfig,
  });

  final String initReadFilterSelect;

  final String initSortSelect;

  /// Reports both values at once so the shelf can apply them in one rebuild.
  final void Function(String readFilter, String sort) updateConfig;

  @override
  State<_LocalFavoritesFilterDialog> createState() =>
      _LocalFavoritesFilterDialogState();
}

const readFilterList = ['All', 'Unread'];

/// "Default" keeps the manual order the user can edit with Reorder.
const sortSelectList = ['Default', 'Title', 'Author', 'Favorited', 'Unread'];

/// Labels shown for [sortSelectList]. "Unread" would otherwise read as the
/// filter of the same name, so it is labelled as an ordering.
const sortSelectLabels = <String, String>{'Unread': 'Unread Chapters'};

/// Orders favorite comics by [sort]. "Default" returns the list untouched, so
/// callers keep the stored manual order.
///
/// [unreadOf] supplies the unread chapter count for the "Unread" order; it is
/// optional so the other orders stay usable without the page's update data.
List<FavoriteItem> sortFavoriteComics(
  List<FavoriteItem> comics,
  String sort, {
  int Function(FavoriteItem comic)? unreadOf,
}) {
  switch (sort) {
    case "Title":
      return comics..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case "Author":
      return comics..sort(
        (a, b) => (a.subtitle ?? '').toLowerCase().compareTo(
          (b.subtitle ?? '').toLowerCase(),
        ),
      );
    case "Favorited":
      return comics..sort((a, b) => b.time.compareTo(a.time));
    case "Unread":
      final unread = unreadOf;
      if (unread == null) return comics;
      return comics..sort((a, b) {
        final byUnread = unread(b).compareTo(unread(a));
        // Equal counts fall back to title so the order is stable to read.
        if (byUnread != 0) return byUnread;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    default:
      return comics;
  }
}

class _LocalFavoritesFilterDialogState
    extends SettingsSaveState<_LocalFavoritesFilterDialog> {
  late var readFilter = widget.initReadFilterSelect;
  late var sort = widget.initSortSelect;

  /// Display mode and column count are plain preferences, read and written
  /// directly. They share this dialog because the shelf's toolbar keeps one
  /// button for "how is this list shown and ordered" instead of three.
  late bool gallery =
      GlobalPreferenceStore(
        appdata.settings,
      ).read(FavoritePreferences.displayMode) ==
      'gallery';

  /// Cover size for the arrangement currently selected.
  ///
  /// The list and the grid keep separate values, so choosing a small cover for
  /// one does not resize the other.
  late String tileSize = _readTileSize();

  Preference<String> get _tileSizePreference => gallery
      ? FavoritePreferences.tileScale
      : FavoritePreferences.listTileScale;

  /// Columns for the grid: "auto" lets the cover size decide, a number pins it.
  late String gridColumns = GlobalPreferenceStore(
    appdata.settings,
  ).read(FavoritePreferences.gridColumns);

  /// Labels shown by the column picker, in the order the preference stores.
  static const _columnValues = ['auto', '2', '3', '4', '5', '6', '7'];

  String _readTileSize() =>
      GlobalPreferenceStore(appdata.settings).read(_tileSizePreference);

  /// Applies the display choice on pick: the shelf should follow it
  /// immediately.
  void _persistDisplay({bool sizeChanged = false}) {
    final useGallery = gallery;
    final useTileSize = tileSize;
    final sizeTarget = _tileSizePreference;
    unawaited(
      appdata
          .updateSettings((draft) {
            final writer = GlobalPreferenceStore(draft);
            writer.write(
              FavoritePreferences.displayMode,
              useGallery ? 'gallery' : 'list',
            );
            // Only the arrangement's own size is written; the other keeps its value.
            if (sizeChanged) writer.write(sizeTarget, useTileSize);
          })
          .then((_) {
            // The shelf lives behind this dialog. Its grids listen to the settings
            // notifier, but a value written here only repaints them once the write
            // lands, which is after the dialog has already shown the new choice.
            // Asking the shelf to rebuild closes that gap.
            if (mounted) setState(() {});
          }),
    );
  }

  /// Applies the filter or sort choice on pick, exactly like the display
  /// choice: the dialog has no Confirm button, so a selection saves itself.
  /// Both values are written in one update so they cannot diverge, and the
  /// shelf is only told about the pair once the save has settled.
  void _persistSortAndFilter() {
    final value = readFilter;
    final order = sort;
    unawaited(
      saveSetting(
        'local_favorites_view',
        () => appdata.updateImplicit((draft) {
          draft['local_favorites_read_filter'] = value;
          draft['local_favorites_sort'] = order;
        }),
        onSaved: () => widget.updateConfig(value, order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return protectSettings(
      ContentDialog(
        title: "Display & sorting".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text("Display".tl),
              trailing: Select(
                // The stored value stays "gallery"; the label now
                // matches what it draws, a grid of covers.
                current: (gallery ? "Grid" : "List").tl,
                values: ["List".tl, "Grid".tl],
                minWidth: 64,
                onTap: (index) {
                  if (!_canEdit || index < 0 || index > 1) return;
                  gallery = index == 1;
                  // Show the size that belongs to the arrangement just chosen.
                  tileSize = _readTileSize();
                  setState(() {});
                  _persistDisplay();
                },
              ),
            ),
            ListTile(
              title: Text("Cover size".tl),
              trailing: Select(
                current: switch (tileSize) {
                  'small' => "Small".tl,
                  'large' => "Large".tl,
                  _ => "Medium".tl,
                },
                values: ["Small".tl, "Medium".tl, "Large".tl],
                minWidth: 64,
                onTap: (index) {
                  if (!_canEdit || index < 0 || index > 2) return;
                  setState(() {
                    tileSize = const ['small', 'medium', 'large'][index];
                  });
                  _persistDisplay(sizeChanged: true);
                },
              ),
            ),
            if (gallery)
              ListTile(
                title: Text("Columns".tl),
                trailing: Select(
                  current: gridColumns == 'auto' ? "Auto".tl : gridColumns,
                  values: [
                    for (final value in _columnValues)
                      value == 'auto' ? "Auto".tl : value,
                  ],
                  minWidth: 64,
                  onTap: (index) {
                    if (!_canEdit ||
                        index < 0 ||
                        index >= _columnValues.length) {
                      return;
                    }
                    final value = _columnValues[index];
                    setState(() => gridColumns = value);
                    unawaited(
                      appdata.updateSettings((draft) {
                        GlobalPreferenceStore(
                          draft,
                        ).write(FavoritePreferences.gridColumns, value);
                      }),
                    );
                  },
                ),
              ),
            ListTile(
              title: Text("Filter".tl),
              trailing: Select(
                current: readFilter.tl,
                values: readFilterList.map((e) => e.tl).toList(),
                minWidth: 64,
                onTap: (index) {
                  if (!_canEdit ||
                      index < 0 ||
                      index >= readFilterList.length) {
                    return;
                  }
                  setState(() => readFilter = readFilterList[index]);
                  _persistSortAndFilter();
                },
              ),
            ),
            ListTile(
              title: Text("Opening a comic".tl),
              trailing: Select(
                current:
                    (GlobalPreferenceStore(
                          appdata.settings,
                        ).read(FavoritePreferences.onClickFavorite) ==
                        "read")
                    ? "Read".tl
                    : "View Detail".tl,
                values: ["View Detail".tl, "Read".tl],
                minWidth: 64,
                onTap: (index) {
                  if (!_canEdit || index < 0 || index > 1) return;
                  GlobalPreferenceStore(appdata.settings).write(
                    FavoritePreferences.onClickFavorite,
                    const ["viewDetail", "read"][index],
                  );
                  setState(() {});
                  _persistSortAndFilter();
                },
              ),
            ),
            ListTile(
              title: Text("Sort".tl),
              trailing: Select(
                current: (sortSelectLabels[sort] ?? sort).tl,
                values: sortSelectList
                    .map((e) => (sortSelectLabels[e] ?? e).tl)
                    .toList(),
                minWidth: 64,
                onTap: (index) {
                  if (!_canEdit ||
                      index < 0 ||
                      index >= sortSelectList.length) {
                    return;
                  }
                  setState(() => sort = sortSelectList[index]);
                  _persistSortAndFilter();
                },
              ),
            ),
          ],
        ),
        // The title stays, but the dialog is dismissed by tapping outside
        // instead of by an X or a Confirm button.
        showClose: false,
        actions: [settingsSaveStatus],
      ),
    );
  }

  bool get _canEdit =>
      mounted &&
      acceptsSettingsChanges &&
      !savingSettings &&
      !hasSettingsSaveError;
}
