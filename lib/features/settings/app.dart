import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/features/settings/app_controls.dart';
import 'package:venera_next/features/settings/local_storage_settings.dart';
import 'package:venera_next/features/settings/settings_task_presenter.dart';
import 'package:venera_next/features/sync/sync.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/file_interaction.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key, this.title = 'Storage'});

  /// Heading shown when this page is pushed on its own.
  final String title;

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  final _tasks = SettingsTaskPresenter();
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text(widget.title.tl)),
        SettingPartTitle(title: "Data", icon: Icons.storage),
        const LocalStorageSettings().toSliver(),
        ListTile(
          title: Text("Cache Size".tl),
          subtitle: Text(bytesToReadableString(CacheManager().currentSize)),
        ).toSliver(),
        CallbackSetting(
          title: "Clear Cache".tl,
          actionTitle: "Clear".tl,
          callback: () async {
            await _tasks.run(
              context,
              task: (_) async {
                await CacheManager().clear();
                return null;
              },
              errorMessage: "Error".tl,
              successMessage: "Cache cleared".tl,
              onSuccess: () => setState(() {}),
            );
          },
        ).toSliver(),
        const CacheLimitSetting().toSliver(),
        const HistoryRetentionSetting().toSliver(),
        CallbackSetting(
          title: "Export App Data".tl,
          callback: () async {
            await _tasks.run(
              context,
              task: (operation) async {
                await operation.useTemporaryFile(
                  cacheDirectory: Directory(App.cachePath),
                  filename: 'data.venera',
                  prepare: (file) async {
                    await exportAppData(destination: file);
                  },
                  consume: (file) => saveFile(
                    operation: operation,
                    filename: 'data.venera',
                    file: file,
                    checkStop: operation.checkActive,
                  ),
                );
                return null;
              },
              errorMessage: "Error".tl,
            );
          },
          actionTitle: 'Export'.tl,
        ).toSliver(),
        CallbackSetting(
          title: "Import App Data".tl,
          callback: () async {
            await _tasks.run(
              context,
              task: (operation) async {
                final file = await operation.pickFile(
                  () => selectFile(
                    ext: ['venera', 'picadata'],
                    checkStop: operation.checkActive,
                  ),
                );
                if (file == null) return null;
                return operation.useFileCopy(
                  file,
                  cacheDirectory: Directory(App.cachePath),
                  consume: (cacheFile) async {
                    try {
                      // Compare the normalised extension: a copied download adds
                      // a " (2)" marker after it, which endsWith would miss.
                      if (fileExtension(file.name) == 'picadata') {
                        await importPicaData(cacheFile);
                      } else {
                        await importAppData(cacheFile);
                      }
                    } finally {
                      appNavigation.forceRebuild();
                    }
                    return null;
                  },
                );
              },
              errorMessage: "Failed to import data".tl,
            );
          },
          actionTitle: 'Import'.tl,
        ).toSliver(),
      ],
    );
  }
}
