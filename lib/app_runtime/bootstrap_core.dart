import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:path/path.dart' as path;
import 'package:rhttp/rhttp.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/comic_source/source_data_storage.dart';
import 'package:venera_next/features/comic_source/source_transaction_journal.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/local_comics/download_network_guard.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/sync/app_data_import_journal.dart';
import 'package:venera_next/features/sync/data_sync_ownership.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/js_engine.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/opencc.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/network/cookie_jar.dart';

import 'core_bootstrap.dart';
import 'cache_settings.dart';
import 'core_infrastructure.dart';

/// Core startup never registers window callbacks or automatic sync timers.
/// The caller owns this bootstrap instance.
CoreBootstrap createCoreBootstrap({
  Future<void> Function()? environment,
  void Function()? onDataChanged,
}) {
  final cleanup = <CoreStartupCleanup>[];
  final producers = <CoreStartupCleanup>[];
  SqliteDataSyncOwnership? applicationOwnership;
  var storeCleanupIndex = 0;
  void registerProducer(String name, FutureOr<void> Function() close) {
    Future<void>? closing;
    final resource = (
      name: name,
      close: () => closing ??= Future<void>.sync(close),
    );
    cleanup.add(resource);
    producers.add(resource);
  }

  return CoreBootstrap(
    failureCleanup: cleanup,
    releaseOwnership: () => applicationOwnership?.release(),
    shutdownPreparation: () async {
      // A failed producer can still retain native resources. Keep its stores
      // and the remaining runtime dependencies available for diagnostics.
      for (final producer in producers.reversed) {
        try {
          await producer.close();
        } catch (error, stack) {
          throw CoreShutdownFailure([
            (store: producer.name, error: error, stack: stack),
          ]);
        }
      }
    },
    environment: environment ?? App.init,
    settings: () async {
      // One core owns this directory, including its isolates and accepted
      // descendants, until stores close. In-process snapshots still use
      // AppDataOperations; the lease also excludes other headless/UI processes.
      final ownershipForApplication = applicationOwnership =
          SqliteDataSyncOwnership.applicationData(() => App.dataPath);
      ownershipForApplication.acquire();
      final logDirectory = App.isAndroid
          ? (App.externalStoragePath ?? App.dataPath)
          : App.dataPath;
      final closeLogs = await Log.startFileSession(
        File(path.join(logDirectory, 'logs.txt')),
      );
      cleanup.add((name: 'logs', close: closeLogs));
      // Import recovery precedes settings fallback and every database opener.
      // No live application resource may observe a partly replaced snapshot.
      final ownership = SqliteDataSyncOwnership(() => App.dataPath);
      AppDataImportJournal? imports;
      final recoveryCleanup = (
        name: 'startup sync recovery',
        close: () {
          imports?.close();
          ownership.release();
        },
      );
      cleanup.add(recoveryCleanup);
      try {
        ownership.acquire();
        imports = AppDataImportJournal.open(App.dataPath);
        await imports.recoverPending();
        imports.close();
        await SourceTransactionJournal.recover(App.dataPath);
        await const SourceDataStorage().recover(App.dataPath);
        await appdata.init();
      } finally {
        recoveryCleanup.close();
        cleanup.remove(recoveryCleanup);
      }
    },
    infrastructure: () async {
      // Restore external-library grants before sources and stores touch them.
      // An unavailable provider is reported without discarding its bookmark.
      if (App.isIOS || App.isMacOS) {
        final failures = await const MethodChannel(
          'venera/method_channel',
        ).invokeMapMethod<String, String>('restoreDirectoryAccess');
        for (final failure in (failures ?? const <String, String>{}).entries) {
          Log.error(
            'Directory access',
            '${failure.key}: ${failure.value}. Select the directory again to renew access.',
          );
        }
      }
      final previousCookies = SingleInstanceCookieJar.instance;
      await initializeCoreInfrastructure(
        directory: App.dataPath,
        services: [
          Rhttp.init,
          () => _optional('SAF worker', () => SAFTaskWorker().init()),
          () => _optional('App translations', AppTranslation.init),
          () => _optional('Tag translations', TagsTranslation.readData),
          OpenCC.init,
        ],
      );
      final cookies = SingleInstanceCookieJar.instance;
      if (cookies != null && !identical(previousCookies, cookies)) {
        cleanup.add((
          name: 'cookies',
          close: () {
            cookies.dispose();
            // Data import replaces this application's connection. The core
            // owns its replacement too, but never a different database.
            final replacement = SingleInstanceCookieJar.instance;
            if (replacement != null &&
                path.equals(replacement.path, cookies.path)) {
              replacement.dispose();
            }
          },
        ));
      }
    },
    sources: () async {
      storeCleanupIndex = cleanup.length;
      cleanup.add((
        name: 'source bindings',
        close: () {
          configureComicSourceDataSavedHandler(null);
          configureRuntimeComicSourcesProvider(null);
        },
      ));
      configureComicTypeSourceKeyResolver();
      configureComicSourceDataSavedHandler(
        onDataChanged == null ? null : () async => onDataChanged(),
      );
      final engine = JsEngine();
      registerProducer('JS engine', engine.closeAndWait);
      await engine.init();
      final sources = ComicSourceManager();
      registerProducer('comic sources', sources.closeAndWait);
      await sources.init();
    },
    stores: () async {
      final history = HistoryManager();
      final favorites = LocalFavoritesManager();
      final local = LocalManager();
      final stores = <CoreStoreStartup>[
        (
          name: 'history',
          initialize: history.init,
          close: () async {
            try {
              if (history.hasPendingWrites) await history.waitForAsyncWrites();
            } finally {
              history.close();
            }
          },
        ),
        (
          name: 'favorites',
          initialize: favorites.init,
          close: favorites.closeAndWait,
        ),
        (name: 'local', initialize: local.init, close: local.dispose),
      ];
      await initializeCoreStores(stores);
      // The group handles its own failed attempt; retain only successful stores
      // for a failure in a later startup phase.
      cleanup.insertAll(
        storeCleanupIndex,
        stores.map((store) => (name: store.name, close: store.close)),
      );
      // Watch the link type so "Download on WiFi Only" takes effect while the
      // app runs, including after a reconnect.
      DownloadNetworkGuard.instance.start();
      registerProducer(
        'download network guard',
        () async => DownloadNetworkGuard.instance.stop(),
      );
    },
    finish: () async {
      await _checkOldConfigs();
      final cache = CacheManager();
      registerProducer('cache', cache.dispose);
      final cacheSettings = CacheSettingsBinding(appdata.settings, cache);
      registerProducer('cache settings', cacheSettings.dispose);
      // The cache owns and drains this scan; UI startup need not await it.
      unawaited(cache.start());
    },
  );
}

Future<void> _optional(
  String service,
  Future<void> Function() initialize,
) async {
  try {
    await initialize();
  } catch (error, stack) {
    Log.error('init', '$service unavailable: $error', stack);
  }
}

Future<void> _checkOldConfigs() async {
  await _migrateMainPageIndex();
  await _migrateDeviceSpecificReaderSettings();
}

/// Device-specific reader settings were removed. A profile that had them
/// enabled stored its overrides under `deviceSpecificSettings[deviceId]`, so
/// dropping that scope blindly would silently reset those users to defaults.
/// Fold this device's overrides into the global settings once, then drop the
/// retired container. Other devices' records are discarded with the feature.
Future<void> _migrateDeviceSpecificReaderSettings() async {
  const marker = 'deviceSpecificReaderSettingsMigrated';
  if (appdata.settings[marker] == true) return;
  await appdata.updateSettings((draft) {
    final container = draft['deviceSpecificSettings'];
    final deviceId = draft['deviceId'];
    if (container is Map && deviceId is String && deviceId.isNotEmpty) {
      final record = container[deviceId];
      if (record is Map && record['enabled'] == true) {
        for (final entry in record.entries) {
          // `enabled` is transport bookkeeping, not a reader setting.
          if (entry.key == 'enabled' || entry.key is! String) continue;
          draft[entry.key as String] = entry.value;
        }
      }
    }
    draft['deviceSpecificSettings'] = <String, dynamic>{};
    draft['deviceId'] = '';
    draft[marker] = true;
  }, sync: false);
}

/// The follow-up updates tab was removed, so every tab after it moved down one.
/// Older indices would otherwise open a different page than the user chose.
Future<void> _migrateMainPageIndex() async {
  const marker = 'mainPageIndexMigrated';
  if (appdata.settings[marker] == true) return;
  await appdata.updateSettings((draft) {
    final raw = draft['initialPage'];
    final index = raw is int ? raw : int.tryParse(raw?.toString().trim() ?? '');
    if (index != null && index >= 1 && index <= 3) {
      draft['initialPage'] = '${index - 1}';
    }
    draft[marker] = true;
  }, sync: false);
}
