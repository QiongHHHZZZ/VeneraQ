import 'preferences.dart';

abstract final class ReaderPreferences {
  static const modes = [
    'galleryLeftToRight',
    'galleryRightToLeft',
    'galleryTopToBottom',
    'continuousTopToBottom',
  ];
  // Stored 'waterfallTopToBottom' values normalize to this replacement mode.
  // The removed horizontal continuous modes are no longer valid choices, so
  // they also fall back to the remaining continuous mode on read.
  static const readerMode = ChoicePreference(
    'readerMode',
    'continuousTopToBottom',
    modes,
    aliases: {'waterfallTopToBottom': 'continuousTopToBottom'},
  );
  // `pagedReaderMode`, `longStripReaderMode` and `autoReaderMode` were removed
  // with automatic layout selection. Values left in existing user data are no
  // longer read, so they cannot influence the effective mode.
  // `longPressAction` and `longPressZoomPosition` were removed with the
  // long-press action group: the reader now always zooms at the press position
  // on long press. Stored `none`, `autoReading` or `center` values are no longer
  // read, so they cannot disable or redirect the gesture.
  // `autoScrollStyle`, `autoPageTurningInterval`, `autoScrollSpeed`,
  // `autoScrollFrequency`, `autoScrollDistance`, `readerScrollSpeed`,
  // `readerSideMargin`, `autoReadingKeepScreenOn`,
  // `autoReadingSkipUnavailableImages`, `autoReadingImageWaitSeconds` and
  // `autoReadingPauseOnLongPress` were removed with automatic reading and the
  // related display options. Values left in existing user data are no longer
  // read, so they cannot influence the reader.
  static const readerBrightness = NumericPreference(
    'readerBrightness',
    50,
    min: 20,
    max: 100,
    step: 1,
    integer: false,
  );
  static const readerScreenPicNumberForPortrait = NumericPreference(
    'readerScreenPicNumberForPortrait',
    1,
    min: 1,
    max: 5,
    step: 1,
    integer: true,
  );
  static const readerScreenPicNumberForLandscape = NumericPreference(
    'readerScreenPicNumberForLandscape',
    1,
    min: 1,
    max: 5,
    step: 1,
    integer: true,
  );

  /// Continue to the next chapter at the chapter end.
  ///
  /// The storage key is historical: the setting started as an automatic
  /// reading option and now also drives cross-chapter continuous reading. The
  /// key is kept unchanged so existing preferences keep their value.
  static const autoReadingAcrossChapters = BoolPreference(
    'autoReadingAcrossChapters',
    true,
  );
  static const enableTapToTurnPages = BoolPreference(
    'enableTapToTurnPages',
    true,
  );
  static const reverseTapToTurnPages = BoolPreference(
    'reverseTapToTurnPages',
    false,
  );
  static const enablePageAnimation = BoolPreference(
    'enablePageAnimation',
    true,
  );
  static const readerBrightnessEnabled = BoolPreference(
    'readerBrightnessEnabled',
    false,
  );
  static const limitImageWidth = BoolPreference('limitImageWidth', true);
  static const enableTurnPageByVolumeKey = BoolPreference(
    'enableTurnPageByVolumeKey',
    true,
  );
  static const enableClockAndBatteryInfoInReader = BoolPreference(
    'enableClockAndBatteryInfoInReader',
    true,
  );
  static const showPageNumberInReader = BoolPreference(
    'showPageNumberInReader',
    true,
  );
  static const showSingleImageOnFirstPage = BoolPreference(
    'showSingleImageOnFirstPage',
    false,
  );

  /// Double tap zooms in/out. A stored `false` keeps its original meaning and
  /// makes a single tap act immediately instead of waiting for the second one.
  static const enableDoubleTapToZoom = BoolPreference(
    'enableDoubleTapToZoom',
    true,
  );

  /// Long press zooms at the press position until release. Disabling it keeps
  /// the long press inert instead of turning it into another action.
  static const enableLongPressToZoom = BoolPreference(
    'enableLongPressToZoom',
    true,
  );

  static const showSystemStatusBar = BoolPreference(
    'showSystemStatusBar',
    false,
  );
  // `showChapterComments` and `showChapterCommentsAtEnd` were removed with the
  // chapter comments entry point; the reader no longer loads chapter comments.
  static const all = <Preference<Object>>[
    readerMode,
    readerBrightness,
    readerScreenPicNumberForPortrait,
    readerScreenPicNumberForLandscape,
    autoReadingAcrossChapters,
    enableTapToTurnPages,
    reverseTapToTurnPages,
    enablePageAnimation,
    readerBrightnessEnabled,
    limitImageWidth,
    enableTurnPageByVolumeKey,
    enableClockAndBatteryInfoInReader,
    showPageNumberInReader,
    showSingleImageOnFirstPage,
    enableDoubleTapToZoom,
    enableLongPressToZoom,
    showSystemStatusBar,
  ];
  static Map<String, Object?> get storageDefaults => {
    for (final preference in all) preference.key: preference.storageDefault,
  };
}
