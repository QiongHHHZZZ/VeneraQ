import 'package:flutter/material.dart';
import 'package:venera_next/features/discovery/discovery.dart';
import 'package:venera_next/features/discovery/discovery_display_sheet.dart';
import 'package:venera_next/features/discovery/discovery_toolbar.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/favorites/shelf_toolbar.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/search/search.dart';
import 'package:venera_next/features/settings/settings.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/translations.dart';

import '../components/menu.dart';
import '../components/navigation_bar.dart';
import '../components/pop_up_widget.dart';
import 'package:venera_next/routing/app_navigation.dart';
import '../foundation/context.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with ContextMenuOwner {
  late final NaviObserver _observer;

  GlobalKey<NavigatorState>? _navigatorKey;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    _navigatorKey!.currentContext!.to(widget);
  }

  @override
  void initState() {
    _observer = NaviObserver();
    _navigatorKey = GlobalKey();
    appNavigation.mainNavigatorKey = _navigatorKey;
    index = int.parse(
      GlobalPreferenceStore(
        appdata.settings,
      ).read(DiscoveryPreferences.initialPage),
    );
    super.initState();
  }

  /// The favorites shelf is the start destination; the separate home summary
  /// page was removed in favour of it. Pulling down on the shelf refreshes
  /// chapters, so the dedicated follow-updates page is no longer a tab.
  final _pages = [
    const FavoritesPage(key: PageStorageKey('favorites')),
    const DiscoveryPage(key: PageStorageKey('discovery')),
    const SettingsPage(key: PageStorageKey('settings'), embedded: true),
  ];

  /// Position of [SettingsPage] in [_pages], whose actions differ from the
  /// library destinations.
  static const _settingsPageIndex = 2;

  /// Position of the favorites shelf, which searches the library instead of
  /// the comic sources.
  static const _homePageIndex = 0;

  /// Position of the discovery tab, whose toolbar offers its own display
  /// settings beside search.
  static const _discoverPageIndex = 1;

  var index = 0;

  /// Whether any download is queued or running right now.
  ///
  /// Resolved without creating a manager, so merely building the toolbar never
  /// initializes the library.
  bool get _hasDownloads => LocalManager.hasActiveDownloads;

  @override
  Widget build(BuildContext context) {
    // Both toolbars publish controls into this bar: the shelf its search and
    // display entries, discovery its source picker.
    return ListenableBuilder(
      listenable: Listenable.merge([
        ShelfToolbar.instance,
        DiscoveryToolbar.instance,
        // The queue entry appears and disappears with the running downloads.
        // The stable notifier is used rather than the manager itself: the
        // manager is created during bootstrap, so listening to a null
        // `current` meant the entry never appeared on a fresh launch.
        LocalManager.downloadActivity,
      ]),
      builder: (context, _) {
        return NaviPane(
          initialPage: index,
          observer: _observer,
          navigatorKey: _navigatorKey!,
          paneItems: [
            // The destination is the app's landing tab and holds favorites
            // alongside downloads and history, so it is named for what it is to
            // the reader rather than for one of the stores inside it.
            PaneItemEntry(
              label: 'Home'.tl,
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
            ),
            PaneItemEntry(
              label: 'Discover'.tl,
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore,
            ),
            PaneItemEntry(
              label: 'Settings'.tl,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
            ),
          ],
          onPageChanged: (i) {
            setState(() {
              index = i;
            });
          },
          // The action bar follows the destination. The shelf publishes its own
          // controls through [ShelfToolbar], so its title bar is the one rendered
          // here instead of a second one inside the page.
          paneActions: _buildActions(),
          paneLeading: _buildLeading(),
          paneTitle: index == _discoverPageIndex
              ? DiscoveryToolbar.instance.title
              : null,
          pageBuilder: (index) {
            return _pages[index];
          },
        );
      },
    );
  }

  /// Leading control for the shelf.
  ///
  /// The folder sidebar is otherwise reachable only by a swipe from the page
  /// edge, which nothing on screen advertises. The shelf itself reports whether
  /// this layout has a drawer to open, so a two-panel shelf keeps no button.
  Widget? _buildLeading() {
    if (index != _homePageIndex) return null;
    final shelf = ShelfToolbar.instance;
    // Always render the slot on the shelf. Hiding it while the page republished
    // its state shifted the title between two paddings, which read as a jump on
    // every folder switch. The control is simply disabled when unavailable.
    return Tooltip(
      // The same word the shelf's own picker uses, so one action keeps one name
      // wherever it appears.
      message: "Folders".tl,
      child: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: shelf.canOpenFolders ? shelf.openFolders : null,
      ),
    );
  }

  List<PaneActionEntry> _buildActions() {
    if (index == _settingsPageIndex) {
      // The search field lives inside the settings page now, so the toolbar
      // needs no entry that pushes a separate search screen.
      return const [];
    }
    if (index == _homePageIndex) {
      final shelf = ShelfToolbar.instance;
      return [
        PaneActionEntry(
          icon: shelf.searching ? Icons.close : Icons.search,
          label: shelf.searching ? "Cancel".tl : "Search".tl,
          // Searching happens inside the shelf so results keep the folder
          // context; no separate page is pushed.
          onTap: shelf.toggleSearch,
        ),
        if (shelf.canChangeDisplay)
          PaneActionEntry(
            // Display, sort and filter share one entry now that the dialog
            // covers all three.
            icon: Icons.grid_view,
            label: "Display & sorting".tl,
            onTap: shelf.openDisplay,
          ),
        PaneActionEntry(
          icon: Icons.history,
          label: "History".tl,
          onTap: () {
            to(
              () => HistoryPage(manager: HistoryScope.read(context)),
              preventDuplicate: true,
            );
          },
        ),
        // The queue is temporary work, so it earns a place only while it has
        // something to show. Without this the running downloads had no entry
        // at all once the local library page was removed.
        if (_hasDownloads)
          PaneActionEntry(
            icon: Icons.downloading_outlined,
            label: "Download".tl,
            onTap: () => showPopUpWidget(context, const DownloadingPage()),
          ),
      ];
    }
    if (index == _discoverPageIndex) {
      return [
        // Grid appearance belongs beside the grid, so the discovery toolbar
        // carries it instead of sending the reader into Settings.
        PaneActionEntry(
          icon: Icons.grid_view,
          label: "Display".tl,
          onTap: () => showDiscoveryDisplaySheet(context),
        ),
        PaneActionEntry(
          icon: Icons.search,
          label: "Search".tl,
          onTap: () {
            to(() => const SearchPage(), preventDuplicate: true);
          },
        ),
      ];
    }
    return [
      PaneActionEntry(
        icon: Icons.search,
        label: "Search".tl,
        onTap: () {
          to(() => const SearchPage(), preventDuplicate: true);
        },
      ),
    ];
  }
}
