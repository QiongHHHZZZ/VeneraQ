import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/favorites/shelf_toolbar.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/features/favorites/favorites_constants.dart';
import 'package:venera_next/features/favorites/local_favorites_page.dart';
import 'package:venera_next/features/favorites/network_favorites_page.dart';
import 'package:venera_next/features/favorites/side_bar.dart';

const _kLeftBarWidth = 256.0;

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends SettingsSaveState<FavoritesPage> {
  String? folder;

  bool isNetwork = false;

  FolderList? folderList;

  /// Publishes the current folder to the navigation bar, which owns the only
  /// title bar. The page keeps the folder state and its picker.
  void _publishToolbar() {
    final toolbar = ShelfToolbar.instance;
    final current = folder;
    final shown = current == null
        ? null
        : isNetwork
        ? current
        : current == localAllFolderLabel
        ? 'All'.tl
        : current;
    void publish() {
      if (!mounted) return;
      toolbar.bind(
        folder: shown,
        hasFolders: true,
        filterActive: false,
        searching: false,
        openFolders: showFolderSelector,
      );
    }

    // Notifying listeners while a frame is building is illegal, so a call that
    // originates from build still defers. Every other call publishes at once,
    // which removes the window where the bar saw no folder handler.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      unawaited(Future.microtask(publish));
    } else {
      publish();
    }
  }

  void setFolder(bool isNetwork, String? folder) {
    if (!acceptsSettingsChanges) return;
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    folderList?.update();
    _publishToolbar();
    saveSetting(
      'favoriteFolder',
      () => appdata.updateImplicit((draft) {
        draft['favoriteFolder'] = {'name': folder, 'isNetwork': isNetwork};
      }),
    );
  }

  @override
  void initState() {
    var data = appdata.implicitData['favoriteFolder'];
    if (data != null) {
      folder = data['name'];
      isNetwork = data['isNetwork'] ?? false;
    }
    if (folder != null &&
        !isNetwork &&
        !FavoritesScope.read(context).existsFolder(folder!)) {
      folder = null;
    }
    // This page is the app's start destination, so an unset or retired
    // selection falls back to every favorite instead of the empty prompt.
    folder ??= localAllFolderLabel;
    super.initState();
    _publishToolbar();
  }

  /// Global key so the toolbar and the edge gesture can open the same drawer.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Keeps the body alive while the shelf crosses the two-panel breakpoint.
  ///
  /// The narrow and the wide layout put the folder list in different subtrees,
  /// so without a global key every relayout replaced the page element: its
  /// scroll position, inline search and selection were discarded, and a reorder
  /// editor pushed from it lost the owner that authorises its writes. The body
  /// still rebuilds when the selected folder changes, because that replaces the
  /// list widget (and its per-folder [PageStorageKey]) underneath this key.
  final _bodyKey = GlobalKey();

  /// Opens the folder drawer, or closes it when it is already open.
  ///
  /// The toolbar button is the only way to reach the drawer on a narrow layout,
  /// so a second press has to dismiss it instead of doing nothing.
  void openFolderDrawer() {
    final state = _scaffoldKey.currentState;
    if (state == null) return;
    if (state.isDrawerOpen) {
      state.closeDrawer();
    } else {
      state.openDrawer();
    }
  }

  /// Where the current pointer drag started, in global coordinates.
  Offset? _dragStart;

  /// Accumulated travel of the current drag, used to tell a sideways pull from
  /// the slight sideways wobble of a pull-to-refresh.
  double _dragDx = 0;
  double _dragDy = 0;

  @override
  Widget build(BuildContext context) {
    final narrow = context.width <= favoritesTwoPanelChangeWidth;
    // Only the drawer is something a title-bar button could open; the
    // two-panel layout already shows the folder list, so it must not offer one.
    // Published from build because rotating across the breakpoint is what
    // changes the answer.
    ShelfToolbar.instance.setFoldersOpenable(narrow);
    return protectSettings(
      Column(
        children: [
          if (savingSettings || hasSettingsSaveError) settingsSaveStatus,
          Expanded(
            child: IconTheme(
              data: IconThemeData(
                color: Theme.of(context).colorScheme.secondary,
              ),
              child: narrow
                  // The framework drawer owns the open/close gesture, the scrim
                  // tap and the predictive-back handoff; reimplementing those
                  // with a full-screen GestureDetector fought the list's own
                  // vertical drag and never felt reliable.
                  ? Scaffold(
                      key: _scaffoldKey,
                      backgroundColor: Colors.transparent,
                      drawer: Drawer(
                        width: min(300, context.width - 16),
                        child: FavoritesFolderSidebar(
                          withAppbar: true,
                          selectedFolder: folder,
                          isNetworkSelected: isNetwork,
                          onFolderSelected: setFolder,
                          onFolderListReady: (list) {
                            folderList = list;
                          },
                          onSelected: () {
                            if (mounted) Navigator.of(context).maybePop();
                          },
                        ),
                      ),
                      drawerEnableOpenDragGesture: acceptsSettingsChanges,
                      // A raw pointer listener observes the drag without joining
                      // the gesture arena. A GestureDetector that claimed
                      // horizontal drags won that arena before any distance was
                      // known, so a pull-to-refresh opened the folder panel
                      // instead of refreshing. Observing pointer deltas cannot
                      // steal the gesture: the list still scrolls and refreshes,
                      // and a clearly sideways drag opens the panel from
                      // anywhere on the page.
                      body: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) {
                          _dragStart = event.position;
                          _dragDx = 0;
                          _dragDy = 0;
                        },
                        onPointerMove: (event) {
                          final start = _dragStart;
                          if (start == null) return;
                          _dragDx = event.position.dx - start.dx;
                          _dragDy = event.position.dy - start.dy;
                        },
                        onPointerUp: (_) {
                          final dx = _dragDx;
                          final dy = _dragDy;
                          _dragStart = null;
                          // Mostly sideways and far enough: a vertical pull, even
                          // with a little wobble, never qualifies.
                          if (dx > 48 && dx.abs() > dy.abs() * 1.5) {
                            openFolderDrawer();
                          }
                        },
                        onPointerCancel: (_) => _dragStart = null,
                        child: KeyedSubtree(key: _bodyKey, child: buildBody()),
                      ),
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: _kLeftBarWidth,
                          child: FavoritesFolderSidebar(
                            selectedFolder: folder,
                            isNetworkSelected: isNetwork,
                            onFolderSelected: setFolder,
                            onFolderListReady: (list) {
                              folderList = list;
                            },
                          ),
                        ),
                        Expanded(
                          child: KeyedSubtree(key: _bodyKey, child: buildBody()),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Kept as the single entry point the toolbar calls; the drawer is opened
  /// through the scaffold so its own gesture and scrim stay in charge.
  void showFolderSelector() {
    if (!acceptsSettingsChanges) return;
    if (context.width <= favoritesTwoPanelChangeWidth) {
      openFolderDrawer();
      return;
    }
    // The wide layout already shows the panel, so there is nothing to open.
  }

  @override
  void dispose() {
    ShelfToolbar.instance.unbind();
    super.dispose();
  }

  Widget buildBody() {
    if (folder == null) {
      return CustomScrollView(
        slivers: [
          SliverAppbar(
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= favoritesTwoPanelChangeWidth
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      color: context.colorScheme.primary,
                      onPressed: showFolderSelector,
                    )
                  : null,
            ),
            title: GestureDetector(
              onTap: context.width < favoritesTwoPanelChangeWidth
                  ? showFolderSelector
                  : null,
              child: Text("Unselected".tl),
            ),
          ),
        ],
      );
    }
    if (!isNetwork) {
      return LocalFavoritesPage(
        folder: folder!,
        key: PageStorageKey("local_$folder"),
        showFolders: showFolderSelector,
        onFolderSelected: setFolder,
        updateFolderList: () {
          folderList?.updateFolders();
        },
      );
    } else {
      var favoriteData = getFavoriteDataOrNull(folder!);
      if (favoriteData == null) {
        folder = null;
        return buildBody();
      } else {
        return NetworkFavoritePage(
          favoriteData,
          key: PageStorageKey("network_$folder"),
          showFolders: showFolderSelector,
        );
      }
    }
  }
}
