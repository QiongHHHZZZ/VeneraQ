import 'preferences.dart';

abstract final class AppPreferences {
  static const language = ChoicePreference('language', 'system', [
    'system',
    'zh-CN',
    'zh-TW',
    'en-US',
  ]);
  static const checkUpdateOnStart = BoolPreference('checkUpdateOnStart', false);
  // The editor range is not a storage limit: older settings may retain history
  // longer. 100 million days fit DateTime/Duration without integer overflow.
  static const historyRetentionDays = RoundedIntPreference(
    'historyRetentionDays',
    0,
    min: 0,
    max: 100000000,
  );
  static const historyRetentionEditorMax = 182.0;
  static const historyRetentionEditorStep = 7.0;
  // Largest whole MiB value whose byte count fits a signed 64-bit integer.
  static const maxCacheSizeMb = 8796093022207;
  static const cacheSize = NumericPreference(
    'cacheSize',
    2048,
    min: 0,
    max: 8796093022207.0,
    step: 1,
    integer: true,
  );
  /// Chapter list order on a comic's detail page.
  ///
  /// It replaces a "reverse" switch: a switch named for its opposite left the
  /// reader translating, while "Descending" states the result. Descending is the
  /// default because new chapters are what a reader looks for first.
  static const chapterOrder = ChoicePreference('chapterOrder', 'descending', [
    'ascending',
    'descending',
  ]);
  static const all = <Preference<Object>>[
    language,
    checkUpdateOnStart,
    historyRetentionDays,
    cacheSize,
    chapterOrder,
  ];
}

abstract final class NetworkPreferences {
  static const proxy = StringPreference('proxy', 'system');
  static const enableDnsOverrides = BoolPreference('enableDnsOverrides', false);
  static const dnsOverrides = StringMapPreference('dnsOverrides');
  static const sni = BoolPreference('sni', true);
  static const ignoreBadCertificate = BoolPreference(
    'ignoreBadCertificate',
    false,
  );
  static const downloadThreads = NumericPreference(
    'downloadThreads',
    5,
    min: 1,
    max: 16,
    step: 1,
    integer: true,
  );
  static const downloadWifiOnly = BoolPreference('downloadWifiOnly', false);

  /// Pages the reader fetches ahead of the one on screen.
  ///
  /// Kept under its original key so an existing value survives the move from
  /// Reading settings, where it used to be a per-comic reader preference.
  static const preloadImageCount = NumericPreference(
    'preloadImageCount',
    4,
    min: 1,
    max: 16,
    step: 1,
    integer: true,
  );

  static const all = <Preference<Object>>[
    proxy,
    enableDnsOverrides,
    dnsOverrides,
    sni,
    ignoreBadCertificate,
    downloadThreads,
    downloadWifiOnly,
    preloadImageCount,
  ];
}

abstract final class AppearancePreferences {
  static const themeMode = ChoicePreference('theme_mode', 'system', [
    'system',
    'light',
    'dark',
  ]);
  // Yellow and cyan are supported by existing saved configurations even though
  // the current selector does not offer them.
  static const color = ChoicePreference('color', 'system', [
    'system',
    'red',
    'pink',
    'purple',
    'green',
    'orange',
    'blue',
    'yellow',
    'cyan',
  ]);
  static const all = <Preference<Object>>[themeMode, color];
}

abstract final class DiscoveryPreferences {
  static const comicDisplayMode = ChoicePreference(
    'comicDisplayMode',
    'brief',
    ['detailed', 'brief'],
  );
  /// Cover size for the grid ("brief") arrangement.
  static const comicTileScale = NumericPreference(
    'comicTileScale',
    1.0,
    min: 0.5,
    max: 1.5,
    step: 0.05,
  );

  /// Cover size for the list ("detailed") arrangement.
  ///
  /// Kept apart from the grid value so choosing a small cover in the list does
  /// not also shrink the grid; each arrangement remembers its own size.
  static const comicListTileScale = NumericPreference(
    'comicListTileScale',
    1.0,
    min: 0.5,
    max: 1.5,
    step: 0.05,
  );
  static const initialPage = StringIndexPreference(
    'initialPage',
    '0',
    length: 3,
  );
  static const explorePages = StringListPreference('explore_pages');
  static const favoritePages = StringListPreference('favorites');
  static const all = <Preference<Object?>>[
    comicDisplayMode,
    comicTileScale,
    comicListTileScale,
    initialPage,
    explorePages,
    favoritePages,
  ];
}

abstract final class FavoritePreferences {
  static const displayMode = ChoicePreference('favoritesDisplayMode', 'gallery', [
    'list',
    'gallery',
  ]);

  /// Thumbnail size for the home shelf only.
  ///
  /// It used to be governed by the Explore setting, which meant resizing covers
  /// on the discovery pages also resized the shelf. The shelf owns its own value
  /// so the two screens can be tuned independently.
  static const tileScale = ChoicePreference('favoritesTileScale', 'medium', [
    'small',
    'medium',
    'large',
  ]);

  /// Cover size for the shelf's list arrangement.
  ///
  /// Separate from the grid value so a small list cover does not also shrink the
  /// grid; each arrangement keeps its own choice.
  static const listTileScale = ChoicePreference(
    'favoritesListTileScale',
    'medium',
    ['small', 'medium', 'large'],
  );

  /// How many covers fit across the shelf's grid.
  ///
  /// Stored as a string so "auto" and a number share one preference. Auto derives
  /// the count from the cover size and the window width; a number pins it, and
  /// the cover size then controls how much of each cell the cover fills.
  static const gridColumns = ChoicePreference(
    'favoritesGridColumns',
    'auto',
    ['auto', '2', '3', '4', '5', '6', '7'],
  );

  /// What tapping a comic in the favorites list does.
  static const onClickFavorite = ChoicePreference(
    'onClickFavorite',
    'viewDetail',
    ['viewDetail', 'read'],
  );
  static const all = <Preference<Object?>>[
    displayMode,
    tileScale,
    listTileScale,
    gridColumns,
    onClickFavorite,
  ];
}

Map<String, Object?> get applicationPreferenceDefaults => {
  for (final preference in [
    ...AppPreferences.all,
    ...NetworkPreferences.all,
    ...AppearancePreferences.all,
    ...DiscoveryPreferences.all,
      ...FavoritePreferences.all,
  ])
    preference.key: preference.storageDefault,
};
