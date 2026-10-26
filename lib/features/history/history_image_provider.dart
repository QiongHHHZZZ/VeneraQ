import 'package:venera_next/foundation/operation_failure.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'dart:async' show Future, Stream, StreamController;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/image_stream.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/foundation/image_provider/base_image_provider.dart';

class HistoryImageProvider extends BaseImageProvider<HistoryImageProvider> {
  /// Image provider for normal image.
  ///
  /// [url] is the url of the image. Local file path is also supported.
  const HistoryImageProvider(this.history);

  final History history;

  @protected
  Stream<ImageDownloadProgress> loadThumbnail(
    String url,
    String? sourceKey,
    String id,
  ) => ImageDownloader.loadThumbnail(url, sourceKey, id);

  @override
  Future<Uint8List> load(
    StreamController<ImageChunkEvent> chunkEvents,
    void Function() checkStop,
  ) async {
    checkStop();
    final id = history.id;
    final type = history.type;
    // Resolve the source without [ComicType.sourceKey], which throws when the
    // source was uninstalled or renamed. A history row outlives its source, so
    // that throw turned every such cover into a failed load; the stored URL is
    // still worth requesting, just without per-source image config.
    final sourceKey = type.comicSource?.key;
    var url = history.cover;
    if (!url.contains('/')) {
      var localComic = LocalManager().find(id, type);
      if (localComic != null) {
        final bytes = await localComic.coverFile.readAsBytes();
        checkStop();
        return bytes;
      }
      final loadComicInfo =
          type.comicSource?.loadComicInfo ??
          (throw OperationFailure.message("Comic source not found."));
      final updateMetadata = HistoryManager().metadataUpdaterFor(history);
      var comic = await loadComicInfo(id);
      checkStop();
      url = comic.data.cover;
      // A position-only entry is missing its whole metadata copy, not just the
      // cover, so an empty title is repaired here too. Otherwise the list keeps
      // showing a blank caption beside the recovered artwork.
      final blankTitle = history.title.trim().isEmpty;
      final updated = await updateMetadata(
        cover: url,
        title: blankTitle ? comic.data.title : null,
        subtitle: blankTitle ? (comic.data.subTitle ?? '') : null,
      );
      if (updated && history.id == id && history.type == type) {
        history.cover = url;
        if (blankTitle) {
          history.title = comic.data.title;
          history.subtitle = comic.data.subTitle ?? '';
        }
      }
      checkStop();
    }
    checkStop();
    final bytes = await readImageStream(
      loadThumbnail(url, sourceKey, id),
      cancelSignal: BaseImageProvider.cancelSignalOf(checkStop),
      checkStop: checkStop,
      onProgress: (progress) => chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.totalBytes,
        ),
      ),
    );
    checkStop();
    if (bytes == null) {
      throw OperationFailure.message("Error: Empty response body.");
    }
    return bytes;
  }

  @override
  Future<HistoryImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "history${history.id}${history.type.value}";
}
