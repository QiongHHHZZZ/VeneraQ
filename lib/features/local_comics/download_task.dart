import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:venera_next/foundation/comic_type.dart';
import 'local_comic_model.dart';

/// How far one chapter of a running download has got.
class DownloadChapterProgress {
  const DownloadChapterProgress({
    required this.title,
    required this.downloaded,
    required this.total,
    required this.active,
  });

  /// Chapter name as the source reported it.
  final String title;

  /// Pages already written for this chapter.
  final int downloaded;

  /// Pages this chapter holds, or 0 before the page list is known.
  final int total;

  /// Whether this is the chapter the task is working on right now.
  final bool active;

  double get progress => total == 0 ? 0 : downloaded / total;
}

abstract class DownloadTask with ChangeNotifier {
  /// 0-1
  double get progress;

  /// Human-readable progress for the title row, e.g. `3/120`.
  ///
  /// Shown in every state, so a paused or failed task still reports how far it
  /// got instead of hiding the count. A task that cannot count pages (an
  /// archive arriving as one stream) reports nothing rather than a fake count.
  String get progressLabel => '';

  /// One entry per chapter in this task, in download order.
  ///
  /// Lets the queue expand a task into the chapters it is working through. A
  /// task without chapters, or one that has not fetched its page list yet,
  /// reports none and the queue shows the task on its own.
  List<DownloadChapterProgress> get chapterProgress => const [];

  bool get isError;

  bool get isPaused;

  /// bytes per second
  int get speed;

  void cancel();

  void pause();

  /// Work already accepted by pause/cancel, including transfer and file cleanup.
  Future<void> get pendingCleanup;

  void resume();

  String get title;

  String? get cover;

  String get message;

  /// root path for the comic. If null, the task is not scheduled.
  String? path;

  /// convert current state to json, which can be used to restore the task
  Map<String, dynamic> toJson();

  LocalComic toLocalComic();

  String get id;

  ComicType get comicType;

  @override
  bool operator ==(Object other) {
    return other is DownloadTask &&
        other.id == id &&
        other.comicType == comicType;
  }

  @override
  int get hashCode => Object.hash(id, comicType);
}
