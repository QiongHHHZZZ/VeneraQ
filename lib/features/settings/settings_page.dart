import 'package:flutter/material.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/settings/about.dart';
import 'package:venera_next/features/settings/appearance.dart';
import 'package:venera_next/features/settings/combined_settings.dart';
import 'package:venera_next/features/settings/network.dart';
import 'package:venera_next/features/settings/settings_reveal.dart';
import 'package:venera_next/features/settings/settings_search_page.dart';
import 'package:venera_next/features/settings/app.dart';
import 'package:venera_next/features/settings/reader.dart';
import 'package:venera_next/features/settings/settings_hub.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, this.embedded = false, super.key});

  final int initialPage;

  /// When true the page is a bottom-bar destination instead of a pushed route,
  /// so it has no back button and starts on the first section on narrow
  /// layouts where only one column is shown.
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int currentPage = -1;

  /// Active search text. Non-empty replaces the destination list with matches,
  /// so searching never leaves the settings screen.
  String _query = '';

  final _searchController = TextEditingController();

  ColorScheme get colors => Theme.of(context).colorScheme;

  /// A narrow layout shows one column and pushes destinations, so nothing is
  /// "current" there; only the two-column layout has a destination on screen.
  bool get enableTwoViews => context.width > 840;

  /// Flat destination list mirroring the reading workflow: what you read, how
  /// it looks, where the content comes from, then the system-level controls.
  ///
  /// Titles are translation keys; `.tl` is applied when the row is rendered.
  List<SettingsEntry> get entries => const [
    SettingsEntry(
      title: "Reading",
      description: "Page layout, gestures and reading display",
      icon: Icons.book,
      builder: _readerSettingsPage,
    ),
    SettingsEntry(
      title: "Appearance",
      description: "Appearance, language and window behavior",
      icon: Icons.palette_outlined,
      builder: _appearancePage,
    ),
    SettingsEntry(
      title: "Sources & Services",
      description: "Comic sources and repositories",
      icon: Icons.extension_outlined,
      builder: _comicSourcePage,
    ),
    SettingsEntry(
      title: "Storage",
      description: "Storage and cache",
      icon: Icons.storage_outlined,
      builder: _appSettingsPage,
    ),
    SettingsEntry(
      title: "Network",
      description: "Proxy, DNS and download connections",
      icon: Icons.public,
      builder: _networkPage,
    ),
    SettingsEntry(
      title: "Advanced & Diagnostics",
      description: "Logs and troubleshooting tools",
      icon: Icons.tune,
      builder: _diagnosticsPage,
    ),
    SettingsEntry(
      title: "About",
      description: "Version, updates and help",
      icon: Icons.info_outline,
      builder: _aboutPage,
    ),
  ];

  // Const-constructible page builders keep the entry table immutable.
  static Widget _appearancePage() => const AppearanceSettings();
  static Widget _comicSourcePage() => const ComicSourcePage();
  static Widget _appSettingsPage() => const AppSettings();
  static Widget _networkPage() => const NetworkSettings();
  static Widget _aboutPage() => const AboutSettings();
  static Widget _readerSettingsPage() => const ReaderSettings();
  static Widget _diagnosticsPage() => const DiagnosticsSettings();

  @override
  void initState() {
    // A two-column layout needs a destination beside the list; a narrow one
    // shows the list alone and pushes destinations, so nothing starts selected.
    currentPage = widget.initialPage >= 0
        ? widget.initialPage
        : (widget.embedded ? 0 : -1);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Entering the wide layout needs a destination, and leaving it must drop
    // the highlight that no longer has a column to describe.
    if (enableTwoViews && currentPage < 0) {
      currentPage = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(child: buildBody());
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(width: 280, height: double.infinity, child: buildLeft()),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(),
            ),
          ),
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft() {
    // The navigation pane already renders a "Settings" title above an embedded
    // destination on narrow layouts, so the page header would duplicate it.
    final showHeader = !widget.embedded || enableTwoViews;
    final searching = _query.trim().isNotEmpty;
    return Material(
      child: Column(
        children: [
          SizedBox(height: showHeader ? MediaQuery.of(context).padding.top : 0),
          if (showHeader)
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  if (!widget.embedded)
                    Tooltip(
                      message: "Back".tl,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: context.pop,
                      ),
                    ),
                  SizedBox(width: widget.embedded ? 16 : 24),
                  Text("Settings".tl, style: ts.s20),
                ],
              ),
            ),
          // The search field is not part of the header: the narrow embedded
          // layout hides that header, and hiding search with it made the
          // feature look missing on phones.
          Padding(
            padding: EdgeInsets.fromLTRB(12, showHeader ? 0 : 8, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: "Search settings".tl,
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: "Cancel".tl,
                        onPressed: _clearSearch,
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GestureDetector(
              // A tap or a scroll outside the field dismisses the keyboard; the
              // search text stays so the results are still visible.
              behavior: HitTestBehavior.translucent,
              onTap: _dismissSearchFocus,
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (_) {
                  _dismissSearchFocus();
                  return false;
                },
                child: searching ? buildSearchResults() : buildCategories(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Drops keyboard focus without discarding the query.
  void _dismissSearchFocus() {
    final focus = FocusScope.of(context);
    if (focus.hasFocus) focus.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  /// Matches replace the category list in place, grouped under their page so
  /// the result still says where the setting lives.
  Widget buildSearchResults() {
    final results = searchSettings(_query);
    if (results.isEmpty) {
      return Center(child: Text("No matching settings".tl)).paddingTop(32);
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        final selected =
            _pickedResult != null &&
            _pickedResult!.section == entry.section &&
            _pickedResult!.title == entry.title;
        return ListTile(
          key: ValueKey('settings-result-${entry.section}/${entry.title}'),
          leading: Icon(entry.icon),
          title: Text(entry.title.tl),
          subtitle: Text(entry.path),
          // The tapped row stays highlighted while its destination opens, so
          // the click registers instead of the list silently changing.
          selected: selected,
          selectedTileColor: context.colorScheme.primaryContainer.toOpacity(
            0.5,
          ),
          onTap: () {
            _dismissSearchFocus();
            _openSearchResult(entry);
          },
        );
      },
    );
  }

  /// Result the user last opened, kept to render its selected state.
  SettingSearchEntry? _pickedResult;

  /// Localized row title the next destination build should scroll to.
  String? _revealTitle;

  void _openSearchResult(SettingSearchEntry entry) {
    // Reuse the normal destination switch: on a wide layout the page opens
    // beside the list, on a narrow one it is pushed. Highlight first so the tap
    // is acknowledged before the destination appears.
    setState(() {
      _pickedResult = entry;
      // The destination scrolls to this row and flashes a frame around it.
      _revealTitle = entry.title.tl;
    });
    // A search entry names its destination, which is exactly the row title the
    // list uses. Comparing builders never matched: the list holds page
    // tear-offs while the index holds constructors, so the wide layout always
    // pushed a route instead of switching in place.
    final index = entries.indexWhere(
      (candidate) => candidate.title == entry.section,
    );
    if (enableTwoViews && index >= 0) {
      setState(() {
        currentPage = index;
        // Leaving search restores the list, now highlighting the page the
        // setting lives on.
        _clearSearch();
      });
      return;
    }
    context.to(
      () => SettingsReveal(title: entry.title.tl, child: entry.build()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget buildCategories() {
    final flat = entries;
    final rows = <Widget>[];
    for (var id = 0; id < flat.length; id++) {
      final entry = flat[id];
      rows.add(
        SettingsEntryTile(
          entry: entry,
          // Narrow layouts push a route instead of showing it beside the
          // list, so a remembered selection must not stay highlighted.
          selected: enableTwoViews && id == currentPage,
          padding: enableTwoViews
              ? const EdgeInsets.fromLTRB(8, 0, 8, 0)
              : EdgeInsets.zero,
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(entry.builder);
            }
          },
        ),
      );
    }
    return ListView(padding: EdgeInsets.zero, children: rows);
  }

  Widget buildRight() {
    if (currentPage < 0 || currentPage >= entries.length) {
      return const SizedBox();
    }
    final entry = entries[currentPage];
    final reveal = _revealTitle;
    return Navigator(
      // Without a key the Navigator keeps its existing route when only the
      // selected index changes, so the right pane would keep showing the
      // previously chosen destination.
      key: ValueKey('settings-destination-$currentPage-$reveal'),
      onGenerateRoute: (settings) {
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            // The reveal runs once per destination build, then clears itself so
            // returning to the page later shows it normally.
            return SettingsReveal(title: reveal, child: entry.builder());
          },
          transitionDuration: Duration.zero,
        );
      },
    );
  }
}

