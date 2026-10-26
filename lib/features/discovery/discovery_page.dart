import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'categories_page.dart';
import 'discovery_toolbar.dart';
import 'explore_page.dart';

/// Sources that can appear in the discovery source selector: a source with no
/// explore pages and no categories would open an empty screen.
List<ComicSource> browsableSources(List<ComicSource> all) => [
  for (final source in all)
    if (source.explorePages.isNotEmpty || source.categoryData != null) source,
];

/// The source key to show, preferring [remembered] when it is still browsable
/// and falling back to the first one otherwise.
String? resolveDiscoverySource(
  List<ComicSource> sources, {
  String? remembered,
}) {
  if (sources.isEmpty) return null;
  if (remembered != null && sources.any((s) => s.key == remembered)) {
    return remembered;
  }
  return sources.first.key;
}

/// Clamps a section index to what [source] offers, so the segmented control
/// cannot sit on a section that has no content.
int resolveDiscoverySection(ComicSource source, int section) {
  final hasBrowse = source.explorePages.isNotEmpty;
  final hasCategories = source.categoryData != null;
  if (hasBrowse && !hasCategories) return 0;
  if (!hasBrowse && hasCategories) return 1;
  return section;
}

/// Explore pages and category pages share one bottom-bar destination.
///
/// A source selector chooses which source's pages are shown, and a segmented
/// control switches between that source's browse and category sections. Only
/// pages the selected source actually provides are reachable, so the tab bar
/// never lists a page that would render empty.
class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  static const _sectionCount = 2;

  /// The selected section survives leaving and re-entering the destination.
  int _section = 0;

  /// A section is built on first visit and stays mounted afterwards, so its
  /// scroll position and loaded pages are not discarded when switching away.
  final _mounted = <int>{0};

  /// The chosen source, remembered across restarts. Null means "not chosen
  /// yet", which falls back to the first source that has any page to show.
  String? _sourceKey;

  List<ComicSource> _sources = const [];

  @override
  void initState() {
    super.initState();
    _sourceKey = appdata.implicitData['discovery_source'] as String?;
    _reloadSources();
    // The title-bar panel writes settings; the grids read them while building,
    // so the page has to rebuild for a change to be visible at once.
    DiscoveryToolbar.instance.addListener(_onAppearanceChanged);
  }

  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  /// Sources that provide at least one page, so an empty source is not offered.
  void _reloadSources() {
    _sources = browsableSources(ComicSource.all());
    _sourceKey = resolveDiscoverySource(_sources, remembered: _sourceKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stored = PageStorage.of(context).readState(context);
    if (stored is int && stored >= 0 && stored < _sectionCount) {
      _section = stored;
      _mounted.add(stored);
    }
  }

  ComicSource? get _source {
    for (final source in _sources) {
      if (source.key == _sourceKey) return source;
    }
    return null;
  }

  bool get _hasBrowse => _source?.explorePages.isNotEmpty ?? false;

  bool get _hasCategories => _source?.categoryData != null;

  void _select(int section) {
    if (section == _section) return;
    PageStorage.of(context).writeState(context, section);
    setState(() {
      _section = section;
      _mounted.add(section);
    });
  }

  Future<void> _selectSource() async {
    final source = _source;
    if (source == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Comic Source".tl,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in _sources)
                      ListTile(
                        leading: const Icon(Icons.source_outlined),
                        title: Text(item.name),
                        subtitle: Text(
                          _capabilitiesOf(item),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: item.key == _sourceKey
                            ? Icon(
                                Icons.check,
                                color: sheetContext.colorScheme.primary,
                              )
                            : null,
                        selected: item.key == _sourceKey,
                        onTap: () => Navigator.pop(sheetContext, item.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _sourceKey || !mounted) return;
    setState(() {
      _sourceKey = picked;
      // A source may not offer the section currently shown, so snap to one it
      // does offer instead of displaying an empty view.
      _mounted
        ..clear()
        ..add(_section);
    });
    appdata.implicitData['discovery_source'] = picked;
    unawaited(appdata.writeImplicitData());
  }

  /// "Recommend / Categories", so the sheet explains why a source has no tabs.
  String _capabilitiesOf(ComicSource source) {
    final hasBrowse = source.explorePages.isNotEmpty;
    final hasCategories = source.categoryData != null;
    if (hasBrowse && hasCategories) {
      return "${"Recommend".tl} / ${"Categories".tl}";
    }
    return hasBrowse ? "Recommend".tl : "Categories".tl;
  }

  /// The source picker shown in the app's title bar.
  ///
  /// It is built here because the page owns the selected source and the sheet
  /// that changes it; the title bar only renders what is published.
  Widget _buildSourcePicker(ComicSource source) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        borderRadius: BorderRadius.circular(8),
        color: context.colorScheme.surfaceContainerHighest.toOpacity(0.6),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _selectSource,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    source.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    DiscoveryToolbar.instance.removeListener(_onAppearanceChanged);
    DiscoveryToolbar.instance.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    if (source == null) {
      return Material(
        child: Center(
          child: Text(
            "${"No Comic Sources".tl}\n${"Please check your settings".tl}",
            textAlign: TextAlign.center,
          ).paddingHorizontal(16),
        ),
      );
    }

    // Clamp the section to what this source offers; otherwise the segmented
    // control could sit on a section with no content.
    final effectiveSection = resolveDiscoverySection(source, _section);

    // The source picker is published to the app's title bar: nothing on this
    // page is shown until a source is chosen, so it belongs beside the
    // destination name instead of in a second row.
    DiscoveryToolbar.instance.setTitle(_buildSourcePicker(source));

    return Material(
      child: Column(
        children: [
          if (_hasBrowse && _hasCategories)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              // The section switch is the page's remaining control, so it is
              // centred on the row now that the picker moved up.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(value: 0, label: Text("Recommend".tl)),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text("Categories".tl),
                      ),
                    ],
                    selected: {effectiveSection},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    onSelectionChanged: (selection) => _select(selection.first),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: effectiveSection,
              children: List<Widget>.generate(
                _sectionCount,
                (section) => _mounted.contains(section)
                    ? switch (section) {
                        0 => ExplorePage(
                          key: const PageStorageKey('discovery_explore'),
                          sourceKey: source.key,
                        ),
                        _ => CategoriesPage(
                          key: const PageStorageKey('discovery_categories'),
                          sourceKey: source.key,
                        ),
                      }
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
