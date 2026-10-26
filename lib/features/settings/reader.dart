import 'package:venera_next/foundation/preferences.dart';
import 'package:venera_next/foundation/reader_preferences.dart';
import 'package:venera_next/foundation/reader_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/reader/brightness.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/features/settings/reader_mode.dart';
import 'package:venera_next/features/settings/reader_brightness.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class ReaderSettings extends StatefulWidget {
  const ReaderSettings({
    super.key,
    this.onChanged,
    this.comicId,
    this.comicSource,
    this.currentReaderMode,
    this.brightnessPreview,
  });

  final void Function(String key)? onChanged;
  final String? comicId;
  final String? comicSource;
  final String Function()? currentReaderMode;
  final ReaderBrightnessPreview? brightnessPreview;

  @override
  State<ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends SettingsSaveState<ReaderSettings> {
  @override
  void initState() {
    super.initState();
    appdata.settings.addListener(_refresh);
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ReaderPreferenceStore get _store => ReaderPreferenceStore(
    settings: appdata.settings,
    comicId: widget.comicId,
    sourceKey: widget.comicSource,
  );

  T _value<T extends Object>(Preference<T> preference) {
    if (widget.comicId != null &&
        widget.comicSource != null &&
        identical(preference, ReaderPreferences.readerMode) &&
        widget.currentReaderMode != null) {
      return preference.normalize(widget.currentReaderMode!());
    }
    return _store.read(preference);
  }

  String get _activeReaderMode => _value(ReaderPreferences.readerMode);

  bool _usesMode(bool Function(String mode) matches) =>
      matches(_activeReaderMode);

  Future<bool> _saveScope(Object key, void Function(Settings) edit) {
    final target = (widget.comicId, widget.comicSource);
    return saveSetting(
      key,
      () => appdata.updateSettings(edit),
      onSaved: () => widget.onChanged?.call('readerMode'),
      isCurrent: () => target == (widget.comicId, widget.comicSource),
    );
  }

  Widget _modeSettings() => ReaderModeSettings(
    comicId: widget.comicId,
    sourceKey: widget.comicSource,
    currentMode: widget.currentReaderMode,
    onChanged: () {
      widget.onChanged?.call('readerMode');
      _refresh();
    },
  ).toSliver();

  @override
  Widget build(BuildContext context) {
    final comicId = widget.comicId;
    final sourceKey = widget.comicSource;
    final key = "$comicId@$sourceKey";

    bool isEnabledSpecificSettings =
        comicId != null &&
        appdata.settings.isComicSpecificSettingsEnabled(comicId, sourceKey);

    return protectSettings(
      SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text("Reading".tl)),
          settingsSaveStatus.toSliver(),
          if (comicId != null) _modeSettings(),
          if (comicId != null && sourceKey != null)
            SliverMainAxisGroup(
              slivers: [
                SwitchListTile(
                  title: Text('Customize other settings for this comic'.tl),
                  value: isEnabledSpecificSettings,
                  onChanged: (b) {
                    _saveScope((comicId, sourceKey, 'scope'), (draft) {
                      draft.setEnabledComicSpecificSettings(
                        comicId,
                        sourceKey,
                        b,
                      );
                    });
                  },
                ).toSliver(),
                if (isEnabledSpecificSettings)
                  Center(
                    child: TextButton(
                      onPressed: () {
                        _saveScope((comicId, sourceKey, 'scope'), (draft) {
                          draft.resetComicReaderSettings(key);
                        });
                      },
                      child: Text('Reset all settings for this comic'.tl),
                    ),
                  ).toSliver(),
              ],
            ),
          if (comicId == null) _modeSettings(),
          // A section heading draws its own rule right below the title, so a
          // separate divider here would show a second line just above it.
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SettingPartTitle(title: "Display", icon: Icons.visibility_outlined),
          SwitchSetting.reader(
            title: "Page animation".tl,
            preference: ReaderPreferences.enablePageAnimation,
            onChanged: () {
              widget.onChanged?.call("enablePageAnimation");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          ReaderBrightnessSetting(
            comicId: widget.comicId,
            sourceKey: widget.comicSource,
            preview: widget.brightnessPreview,
            onChanged: widget.onChanged,
          ).toSliver(),
          SliverAnimatedVisibility(
            visible: _usesMode((mode) => mode.startsWith('gallery')),
            child: ChoiceNumberSetting(
              title:
                  "The number of pic in screen for landscape (Only Gallery Mode)"
                      .tl,
              preference: ReaderPreferences.readerScreenPicNumberForLandscape,
              onChanged: () {
                setState(() {});
                widget.onChanged?.call("readerScreenPicNumberForLandscape");
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
            ),
          ),
          SliverAnimatedVisibility(
            visible: _usesMode((mode) => mode.startsWith('gallery')),
            child: ChoiceNumberSetting(
              title:
                  "The number of pic in screen for portrait (Only Gallery Mode)"
                      .tl,
              preference: ReaderPreferences.readerScreenPicNumberForPortrait,
              onChanged: () {
                widget.onChanged?.call("readerScreenPicNumberForPortrait");
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
            ),
          ),
          SliverAnimatedVisibility(
            visible:
                _usesMode((mode) => mode.startsWith('gallery')) &&
                (_value(ReaderPreferences.readerScreenPicNumberForLandscape) >
                        1 ||
                    _value(ReaderPreferences.readerScreenPicNumberForPortrait) >
                        1),
            child: SwitchSetting.reader(
              title: "Show single image on first page".tl,
              preference: ReaderPreferences.showSingleImageOnFirstPage,
              onChanged: () {
                widget.onChanged?.call("showSingleImageOnFirstPage");
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
            ),
          ),
          SwitchSetting.reader(
            title: 'Limit image width'.tl,
            subtitle: 'When using Continuous(Top to Bottom) mode'.tl,
            preference: ReaderPreferences.limitImageWidth,
            onChanged: () {
              widget.onChanged?.call('limitImageWidth');
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: "Display time & battery info in reader".tl,
            preference: ReaderPreferences.enableClockAndBatteryInfoInReader,
            onChanged: () {
              widget.onChanged?.call("enableClockAndBatteryInfoInReader");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: "Show system status bar".tl,
            preference: ReaderPreferences.showSystemStatusBar,
            onChanged: () {
              widget.onChanged?.call("showSystemStatusBar");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: "Show Page Number".tl,
            preference: ReaderPreferences.showPageNumberInReader,
            onChanged: () {
              widget.onChanged?.call("showPageNumberInReader");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: 'Continue to the next chapter at chapter end'.tl,
            preference: ReaderPreferences.autoReadingAcrossChapters,
            onChanged: () =>
                widget.onChanged?.call('autoReadingAcrossChapters'),
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SettingPartTitle(title: "Gestures", icon: Icons.touch_app),
          SwitchSetting.reader(
            title: "Tap to turn Pages".tl,
            preference: ReaderPreferences.enableTapToTurnPages,
            onChanged: () {
              widget.onChanged?.call("enableTapToTurnPages");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: "Reverse tap to turn Pages".tl,
            preference: ReaderPreferences.reverseTapToTurnPages,
            onChanged: () {
              widget.onChanged?.call("reverseTapToTurnPages");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: 'Double tap to zoom'.tl,
            preference: ReaderPreferences.enableDoubleTapToZoom,
            onChanged: () {
              widget.onChanged?.call('enableDoubleTapToZoom');
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          SwitchSetting.reader(
            title: 'Long press to zoom'.tl,
            preference: ReaderPreferences.enableLongPressToZoom,
            onChanged: () {
              widget.onChanged?.call('enableLongPressToZoom');
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          ).toSliver(),
          if (App.isAndroid)
            SwitchSetting.reader(
              title: 'Turn page by volume keys'.tl,
              preference: ReaderPreferences.enableTurnPageByVolumeKey,
              onChanged: () {
                widget.onChanged?.call('enableTurnPageByVolumeKey');
              },
              comicId: isEnabledSpecificSettings ? widget.comicId : null,
              comicSource: isEnabledSpecificSettings
                  ? widget.comicSource
                  : null,
            ).toSliver(),
        ],
      ),
    );
  }
}
