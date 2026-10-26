import 'package:display_mode/display_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/features/comic_details/comic_details.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/image_provider/cached_image.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/read_progress.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';

import 'core_bootstrap.dart';

/// Interactive startup uses the caller-owned, idempotent core bootstrap.
Future<void> init(CoreBootstrap core) async {
  await core.start();
  configureComicWidgets(
    comicPageBuilder:
        ({
          required String id,
          required String sourceKey,
          String? cover,
          String? title,
          int? heroID,
        }) => ComicPage(
          id: id,
          sourceKey: sourceKey,
          cover: cover,
          title: title,
          heroID: heroID,
        ),
    addFavorite: addFavorite,
    tileStateResolver: _resolveComicTileState,
    tileImageProviderResolver: _resolveComicTileImageProvider,
    addStateListener: (listener) {
      HistoryManager().addListener(listener);
      LocalFavoritesManager().addListener(listener);
    },
    removeStateListener: (listener) {
      HistoryManager().removeListener(listener);
      LocalFavoritesManager().removeListener(listener);
    },
    favoriteDisplayStateResolver: () => ComicFavoriteDisplayState(
      isGallery:
          (GlobalPreferenceStore(
            appdata.settings,
          ).read(FavoritePreferences.displayMode) ==
          'gallery'),
    ),
  );
  if (App.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      Log.error("Display Mode", "Failed to set high refresh rate: $e");
    }
  }
  FlutterError.onError = (details) {
    Log.error("Unhandled Exception", "${details.exception}\n${details.stack}");
  };
}

ComicTileState _resolveComicTileState(Comic comic) {
  // The history list carries no tile state.
  //
  // A row there records a comic the reader has already opened, so "chapters
  // left" is not an action this list offers, and the count only covered the
  // artwork for a comic that is also a favorite. Returning before the favorite
  // and read-mark lookups also keeps a long history list cheap to build.
  if (comic is History) return const ComicTileState();
  final type = _comicTypeOf(comic);
  final favorites = LocalFavoritesManager();
  final isFavorite = favorites.isExist(comic.id, type);
  final chapterCount = isFavorite
      ? favorites.chapterCountOf(comic.id, type)
      : null;
  // Unread counts chapters without a durable read mark.
  //
  // This used to subtract the stored reading position (`ep`), which only moves
  // when the reader opens a chapter; marking chapters read by hand updated the
  // read set but left the position alone, so the badge never changed. The marks
  // now outlive the history row, so clearing history no longer resets the badge
  // to "everything unread".
  final unread = unreadChapterCount(
    HistoryManager().readChapters(comic.id, type),
    chapterCount,
  );
  return ComicTileState(chapterCount: chapterCount, unreadChapters: unread);
}

ComicType _comicTypeOf(Comic comic) {
  if (comic is FavoriteItem) return comic.type;
  if (comic is History) return comic.type;
  if (comic is LocalComic) return comic.comicType;
  return ComicType.fromKey(comic.sourceKey);
}

ImageProvider? _resolveComicTileImageProvider(Comic comic) {
  if (comic is History) {
    // A history row can outlive its metadata: clearing history then reading the
    // comic again used to write the position back with an empty cover. Ask the
    // source to repair it instead of silently painting an empty tile. With no
    // installed source there is nothing to ask, so the tile stays blank rather
    // than showing a load error on every uninstalled comic.
    if (comic.cover.trim().isEmpty &&
        comic.type.comicSource == null &&
        LocalManager().find(comic.id, comic.type) == null) {
      return null;
    }
    return HistoryImageProvider(comic);
  }
  if (comic.cover.trim().isEmpty) return null;
  if (comic is LocalComic) return LocalComicImageProvider(comic);
  if (comic.sourceKey == 'local') {
    final localComic = LocalManager().find(comic.id, ComicType.local);
    return localComic == null ? null : FileImage(localComic.coverFile);
  }
  return CachedImageProvider(
    comic.cover,
    sourceKey: comic.sourceKey,
    cid: comic.id,
    fallback: comic is FavoriteItem
        ? () => _loadLocalCoverFallback(comic.sourceKey, comic.id)
        : null,
  );
}

Future<Uint8List?> _loadLocalCoverFallback(String sourceKey, String id) async {
  final localComic = LocalManager().find(id, ComicType.fromKey(sourceKey));
  if (localComic == null) return null;
  final file = localComic.coverFile;
  if (!await file.exists()) return null;
  final data = await file.readAsBytes();
  return data.isEmpty ? null : data;
}

void reloadComicSourcesForDebug() async {
  try {
    await ComicSourceManager().reloadForDebug();
  } catch (error, stack) {
    Log.error('Reload comic sources', error, stack);
    final context = appNavigation.rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      showToast(message: error.toString(), context: context);
    }
  }
}
