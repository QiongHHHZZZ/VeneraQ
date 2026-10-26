import 'package:venera_next/foundation/application_preferences.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        SelectSetting.preference(
          title: "Theme Mode".tl,
          preference: AppearancePreferences.themeMode,
          optionTranslation: {
            "system": "System".tl,
            "light": "Light".tl,
            "dark": "Dark".tl,
          },
          onChanged: () async {
            appNavigation.forceRebuild();
          },
        ).toSliver(),
        SelectSetting.preference(
          title: "Theme Color".tl,
          preference: AppearancePreferences.color,
          optionTranslation: {
            "system": "System".tl,
            "red": "Red".tl,
            "pink": "Pink".tl,
            "purple": "Purple".tl,
            "green": "Green".tl,
            "orange": "Orange".tl,
            "blue": "Blue".tl,
          },
          onChanged: () async {
            await App.init();
            appNavigation.forceRebuild();
          },
        ).toSliver(),
        // The interface language is an appearance preference, so it shares this
        // page instead of a "Language & Security" destination of its own.
        SelectSetting.preference(
          title: "Language".tl,
          preference: AppPreferences.language,
          optionTranslation: const {
            "system": "System",
            "zh-CN": "简体中文",
            "zh-TW": "繁體中文",
            "en-US": "English",
          },
          onChanged: () {
            appNavigation.forceRebuild();
          },
        ).toSliver(),
        // Which screen the app opens on belongs with the shell's other
        // presentation choices, not with how comics are discovered.
        SelectSetting.preference(
          title: "Initial Page".tl,
          preference: DiscoveryPreferences.initialPage,
          optionTranslation: {
            '0': "Home".tl,
            '1': "Discover".tl,
            '2': "Settings".tl,
          },
        ).toSliver(),
        // Named for the result rather than for a toggle: a "reverse" switch made
        // the reader translate before choosing.
        SelectSetting.preference(
          title: "Chapter order".tl,
          preference: AppPreferences.chapterOrder,
          optionTranslation: {
            'ascending': "Ascending".tl,
            'descending': "Descending".tl,
          },
        ).toSliver(),
      ],
    );
  }
}
