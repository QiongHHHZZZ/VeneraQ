import 'package:venera_next/foundation/preferences.dart';
import 'reader_preferences.dart';

/// Immutable, validated effective settings. Storage keys remain compatible with
/// existing JSON; UI and reading policies consume named, typed properties.
class ReaderSettings {
  ReaderSettings._(Map<String, Object?> values)
    : _values = Map.unmodifiable(values);

  final Map<String, Object?> _values;

  factory ReaderSettings.resolve({required Map global, Map? comic}) {
    final comicEnabled = comic?['enabled'] == true;
    Object? scopedValue(String key) =>
        (comicEnabled ? comic![key] : null) ?? global[key];
    final values = <String, Object?>{};
    for (final entry in _fields.entries) {
      values[entry.key] = entry.value.normalize(scopedValue(entry.key));
    }

    // Manual comic mode is independent of the other-settings switch. An
    // explicit default/invalid override must not revive the old readerMode.
    final Object? override;
    if (comic?.containsKey('readerModeOverride') == true) {
      final value = comic?['readerModeOverride'];
      override = value is String && value != 'default' ? value : null;
    } else {
      final value = comicEnabled ? comic!['readerMode'] : null;
      override = value is String ? value : null;
    }
    // Reading mode is the stored `readerMode` unless the comic overrides it.
    // The removed automatic layout selection no longer rewrites this value.
    // This deliberately reads the global value rather than the comic scope:
    // `override` above already applies a comic's `readerMode`, so consulting
    // the comic layer again here would revive a manual choice that an invalid
    // or cleared override is supposed to drop.
    values['readerMode'] = _mode(override ?? global['readerMode']);
    // The removed `longPressAction` choice described this same gesture. Keep a
    // stored `none` working as "long press does nothing" instead of silently
    // re-enabling zoom for users who had turned it off.
    if (scopedValue('enableLongPressToZoom') is! bool &&
        scopedValue('longPressAction') == 'none') {
      values['enableLongPressToZoom'] = false;
    }
    return ReaderSettings._(values);
  }

  static String _mode(Object? value) =>
      ReaderPreferences.readerMode.normalize(value);

  static final _fields = {
    for (final preference in ReaderPreferences.all) preference.key: preference,
  };

  T read<T extends Object>(Preference<T> preference) =>
      preference.normalize(_values[preference.key]);

  String get readerMode => _values['readerMode'] as String;
  double get readerBrightness => _values['readerBrightness'] as double;
  int get readerScreenPicNumberForPortrait =>
      _values['readerScreenPicNumberForPortrait'] as int;
  int get readerScreenPicNumberForLandscape =>
      _values['readerScreenPicNumberForLandscape'] as int;
  bool get autoReadingAcrossChapters =>
      _values['autoReadingAcrossChapters'] as bool;
  bool get enableTapToTurnPages => _values['enableTapToTurnPages'] as bool;
  bool get reverseTapToTurnPages => _values['reverseTapToTurnPages'] as bool;
  bool get enablePageAnimation => _values['enablePageAnimation'] as bool;
  bool get readerBrightnessEnabled =>
      _values['readerBrightnessEnabled'] as bool;
  bool get limitImageWidth => _values['limitImageWidth'] as bool;
  bool get enableTurnPageByVolumeKey =>
      _values['enableTurnPageByVolumeKey'] as bool;
  bool get enableClockAndBatteryInfoInReader =>
      _values['enableClockAndBatteryInfoInReader'] as bool;
  bool get showPageNumberInReader => _values['showPageNumberInReader'] as bool;
  bool get showSingleImageOnFirstPage =>
      _values['showSingleImageOnFirstPage'] as bool;
  bool get enableDoubleTapToZoom => _values['enableDoubleTapToZoom'] as bool;
  bool get enableLongPressToZoom => _values['enableLongPressToZoom'] as bool;
  bool get showSystemStatusBar => _values['showSystemStatusBar'] as bool;
}
