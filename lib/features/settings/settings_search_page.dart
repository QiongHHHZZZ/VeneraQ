import 'package:flutter/material.dart';
import 'package:venera_next/features/settings/about.dart';
import 'package:venera_next/features/settings/app.dart';
import 'package:venera_next/features/settings/appearance.dart';
import 'package:venera_next/features/settings/combined_settings.dart';
import 'package:venera_next/features/settings/network.dart';
import 'package:venera_next/features/settings/reader.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/translations.dart';

/// One searchable setting.
///
/// [title] is the exact translation key its page passes to `.tl`, so a result
/// localizes like the real row. [build] opens the page that owns the setting;
/// the settings screens are independent widgets with their own state, so a
/// result navigates instead of rendering the row out of context.
class SettingSearchEntry {
  const SettingSearchEntry({
    required this.title,
    required this.section,
    required this.build,
    this.keywords = const [],
    this.visible,
  });

  final String title;

  /// Translation key of the settings page this row lives on.
  final String section;

  final Widget Function() build;

  /// Extra English terms so pinyin-free synonyms still match.
  final List<String> keywords;

  /// Whether this row exists on the current platform.
  ///
  /// Settings that a page hides behind a platform check must not be found here:
  /// a result that opens a page without the row is worse than no result.
  final bool Function()? visible;

  /// Whether the row is present on this build. Evaluated lazily so the index can
  /// be a const list built before platform facts are known.
  bool get isAvailable => visible?.call() ?? true;

  /// The destination shown in the settings list that owns this row.
  ///
  /// The list is flat, so this is the destination name itself: a result reads
  /// "Explore / Search Sources", never a retired category heading.
  String get group => section;

  /// "Destination / Section", dropping the levels that repeat.
  ///
  /// Showing the path is what makes a result locatable after navigating; the
  /// middle level only appears when a page actually has named sub-sections.
  String get path {
    final sub = settingsSearchSections[section];
    return [
      group.tl,
      if (sub != null) sub.tl,
      if (section != group && sub == null) section.tl,
    ].join(' / ');
  }

  /// Mirrors the icon the settings list uses, so a result is recognisable
  /// without reading the path.
  IconData get icon => settingsSearchIcons[section] ?? Icons.settings_outlined;
}

/// Page -> a named sub-section, for rows that sit under a visible heading
/// inside their page. A page without an entry reads as just its destination.
///
/// The reader's rows span several headings (Display, Gestures, Image), so none
/// is named here; the diagnostics page groups its rows under "Debug".
const settingsSearchSections = <String, String>{
  'Advanced & Diagnostics': 'Debug',
};

/// The destinations the settings list actually renders, in list order.
///
/// Every index entry's `section` must be one of these: a result whose section
/// is not here would navigate to a page that does not carry that name.
const settingsSearchDestinations = <String>[
  'Reading',
  'Appearance',
  'Explore',
  'Local Favorites',
  'Sources & Services',
  'Storage',
  'Network',
  'Advanced & Diagnostics',
  'About',
];

/// Page -> the icon the settings list shows for that page.
///
/// Kept beside the index so a result is recognisable without reading the path.
const settingsSearchIcons = <String, IconData>{
  'Reading': Icons.book,
  'Appearance': Icons.palette_outlined,
  'Explore': Icons.explore_outlined,
  'Local Favorites': Icons.collections_bookmark_rounded,
  'Sources & Services': Icons.extension_outlined,
  'Storage': Icons.storage_outlined,
  'Network': Icons.public,
  'Advanced & Diagnostics': Icons.tune,
  'About': Icons.info_outline,
};

/// Search index over every settings destination.
///
/// Keep this list in sync with the pages themselves: when a setting is added,
/// renamed, or removed, update its entry so the index cannot point at a row
/// that no longer exists.
final List<SettingSearchEntry> settingsSearchIndex = [
  // Reader
  SettingSearchEntry(
    title: 'Tap to turn Pages',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['tap', 'page'],
  ),
  SettingSearchEntry(
    title: 'Reverse tap to turn Pages',
    section: 'Reading',
    build: ReaderSettings.new,
  ),
  SettingSearchEntry(
    title: 'Page animation',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['animation'],
  ),
  SettingSearchEntry(
    title: 'Continue to the next chapter at chapter end',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['chapter', 'next chapter', 'continue'],
  ),
  SettingSearchEntry(
    title: 'Number of images preloaded',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['preload', 'cache'],
  ),
  SettingSearchEntry(
    title: 'Show Page Number',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['page number'],
  ),
  SettingSearchEntry(
    title: 'Double tap to zoom',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['double tap', 'zoom'],
  ),
  SettingSearchEntry(
    title: 'Long press to zoom',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['long press', 'zoom'],
  ),
  SettingSearchEntry(
    title: 'Turn page by volume keys',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['volume', 'hardware key'],
    // The row is Android-only; another platform has no such control.
    visible: () => App.isAndroid,
  ),
  SettingSearchEntry(
    title: 'Display time & battery info in reader',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['clock', 'battery', 'time'],
  ),
  SettingSearchEntry(
    title: 'Show system status bar',
    section: 'Reading',
    build: ReaderSettings.new,
    keywords: ['status bar'],
  ),
  // Appearance
  SettingSearchEntry(
    title: 'Theme Mode',
    section: 'Appearance',
    build: AppearanceSettings.new,
    keywords: ['theme', 'dark', 'light'],
  ),
  SettingSearchEntry(
    title: 'Theme Color',
    section: 'Appearance',
    build: AppearanceSettings.new,
    keywords: ['color', 'theme'],
  ),
  // Browse & favorites
  // Neither tile display mode nor cover size is a settings row any more: both
  // live in the discovery title bar's "Display" panel, beside the grids they
  // affect.
  // The tile status switches are gone: both markers always show.
  // "Display mode of comic list" is gone too: the list chooses its own paging
  // style from what the source provides.
  // "Chapter order" moved to Appearance and is indexed there.
  SettingSearchEntry(
    title: 'Initial Page',
    section: 'Appearance',
    build: AppearanceSettings.new,
    keywords: ['start page', 'launch', 'home'],
  ),
  SettingSearchEntry(
    title: 'Chapter order',
    section: 'Appearance',
    build: AppearanceSettings.new,
    keywords: ['ascending', 'descending', 'reverse'],
  ),
  // Keyword blocking and the language filter were removed entirely, so
  // neither is indexed here.
  // Network
  SettingSearchEntry(
    title: 'Proxy',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['proxy'],
  ),
  SettingSearchEntry(
    title: 'Enable DNS Overrides',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['dns', 'override'],
  ),
  SettingSearchEntry(
    title: 'DNS Overrides',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['dns'],
  ),
  SettingSearchEntry(
    title: 'Server Name Indication',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['sni', 'tls'],
  ),
  SettingSearchEntry(
    title: 'Download Threads',
    section: 'Network',
    build: NetworkSettings.new,
    keywords: ['download', 'thread', 'concurrency'],
  ),
  SettingSearchEntry(
    title: 'Ignore Certificate Errors',
    section: 'Advanced & Diagnostics',
    build: DiagnosticsSettings.new,
    keywords: ['certificate', 'cert', 'tls'],
  ),
  // Storage
  SettingSearchEntry(
    title: 'Clear Cache',
    section: 'Storage',
    build: AppSettings.new,
    keywords: ['cache'],
  ),
  SettingSearchEntry(
    title: 'Import App Data',
    section: 'Storage',
    build: AppSettings.new,
    keywords: ['import', 'restore'],
  ),
  SettingSearchEntry(
    title: 'Export App Data',
    section: 'Storage',
    build: AppSettings.new,
    keywords: ['export', 'backup'],
  ),
  SettingSearchEntry(
    title: 'Language',
    section: 'Appearance',
    build: AppearanceSettings.new,
    keywords: ['language', 'locale'],
  ),
  SettingSearchEntry(
    title: 'Advanced & Diagnostics',
    section: 'Advanced & Diagnostics',
    build: DiagnosticsSettings.new,
    keywords: ['debug', 'diagnostics'],
  ),
  SettingSearchEntry(
    title: 'Check for updates on startup',
    section: 'About',
    build: AboutSettings.new,
    keywords: ['update', 'startup'],
  ),
];

/// Search over [settingsSearchIndex], matching the localized title, its English
/// source string, the destination it lives on, and any extra keyword.
///
/// Rows hidden on the current platform are skipped, mirroring VeneraX.
List<SettingSearchEntry> searchSettings(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const [];
  final terms = normalized.split(' ').where((t) => t.isNotEmpty).toList();
  bool matches(SettingSearchEntry entry) {
    final haystack = [
      entry.title.tl.toLowerCase(),
      entry.title.toLowerCase(),
      entry.section.tl.toLowerCase(),
      entry.section.toLowerCase(),
      entry.group.tl.toLowerCase(),
      ...entry.keywords.map((keyword) => keyword.toLowerCase()),
    ].join(' ');
    return terms.every(haystack.contains);
  }

  return settingsSearchIndex
      .where((entry) => entry.isAvailable && matches(entry))
      .toList();
}

