import 'dart:async';
import 'dart:convert';

import 'package:venera_next/features/comic_details/comic_details_cache.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/favorites/favorites_api.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/network/request_scope.dart';

import 'follow_update_queue.dart';
import 'follow_update_task.dart';

class ComicUpdateResult {
  final bool updated;
  final String? errorMessage;
  final bool cancelled;
  ComicUpdateResult(this.updated, this.errorMessage, {this.cancelled = false});
}

Future<ComicUpdateResult> updateComic(
  FavoriteItemWithUpdateInfo comic,
  String folder, {
  LocalFavoritesManager? manager,
  RequestScope? scope,
  int? generation,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final request = RequestScope(parent: scope, timeout: timeout);
  if (FollowUpdateJob._exitPreparation != null) {
    request.cancel();
    request.dispose();
    return ComicUpdateResult(false, null, cancelled: true);
  }
  final done = Completer<void>();
  FollowUpdateJob._updates[request] = done.future;
  try {
    request.check();
    final source = comic.type.comicSource;
    if (source?.loadComicInfo == null) {
      return ComicUpdateResult(false, 'Comic source not found');
    }
    final favorites = manager ?? LocalFavoritesManager();
    final sourceGeneration = generation ?? favorites.connectionGeneration;
    if (sourceGeneration != favorites.connectionGeneration) {
      throw StateError('Favorites database changed');
    }
    // Transient failures are retried by the JS bridge, once per source call.
    final response = await request.run(() => source!.loadComicInfo!(comic.id));
    request.check();
    if (response.error) return ComicUpdateResult(false, response.errorMessage);
    final info = response.data;
    final tags = <String>[];
    for (final entry in info.tags.entries) {
      if (const [
        'author',
        'artist',
        'time',
      ].contains(entry.key.toLowerCase())) {
        continue;
      }
      tags.addAll(entry.value.map((tag) => '${entry.key}:$tag'));
    }
    request.check();
    // The check already paid for the chapter list, so keep it for the details
    // page instead of making that page fetch the same chapters again.
    unawaited(ComicDetailsCache.instance.write(info));
    await favorites.applyFollowUpdate(
      folder,
      FavoriteItem(
        id: comic.id,
        name: info.title,
        coverPath: info.cover,
        author:
            info.subTitle ?? info.tags['author']?.firstOrNull ?? comic.author,
        type: comic.type,
        tags: tags,
      ),
      generation: sourceGeneration,
      checkActive: request.check,
      chapterCount: info.chapters?.length,
    );
    // The flag it used to report is gone; the check itself still succeeded.
    return ComicUpdateResult(true, null);
  } catch (error, stack) {
    if (scope?.isCancelled == true || error is RequestCancelled) {
      return ComicUpdateResult(false, null, cancelled: true);
    }
    Log.error('Check Updates', error, stack);
    return ComicUpdateResult(false, error.toString());
  } finally {
    request.dispose();
    FollowUpdateJob._updates.remove(request);
    done.complete();
  }
}

/// A shelf refresh leaves alone any comic whose folder row was checked this
/// recently, so pulling twice in a row does not repeat the same slow details
/// requests. The window is short enough that a user who waits still gets a
/// real check.
const Duration shelfRefreshSkipWindow = Duration(minutes: 15);

/// Comics a shelf refresh keeps in flight at once. The shelf checks every
/// folder in one pass, so this bounds the whole refresh and keeps a burst of
/// details requests away from a single comic source.
const int shelfRefreshConcurrency = 4;

/// One comic in a shelf-wide refresh together with the favorite folder whose
/// row records the result. Each folder owns its own metadata, chapter total and
/// check time, so one target is one independent write.
class ShelfUpdateTarget {
  const ShelfUpdateTarget(this.folder, this.comic);

  final String folder;
  final FavoriteItemWithUpdateInfo comic;
}

class UpdateProgress {
  final int total;
  final int current;
  final int errors;
  final int updated;
  final FavoriteItemWithUpdateInfo? comic;
  final String? errorMessage;

  /// Comics this refresh skipped because their folder row was already checked
  /// inside the job's skip window.
  final int skipped;
  UpdateProgress(
    this.total,
    this.current,
    this.errors,
    this.updated, [
    this.comic,
    this.errorMessage,
    this.skipped = 0,
  ]);
  double get fraction => total == 0 ? 1 : current / total;
}

/// One application-wide check. Replacing a job cancels its queue and writes.
class FollowUpdateJob implements FollowUpdateTask {
  FollowUpdateJob(
    this.folder,
    this.ignoreCheckTime, {
    LocalFavoritesManager? manager,
  }) : _favorites = manager ?? LocalFavoritesManager(),
       _shelfTargets = null,
       _recentSkipWindow = Duration.zero,
       _isCurrent = null,
       _concurrency = defaultFollowUpdateConcurrency,
       _perSourceConcurrency = defaultFollowUpdatePerSourceConcurrency,
       _sourceInterval = defaultFollowUpdateSourceInterval {
    _attach();
  }

  /// Checks an explicit shelf-wide plan in one bounded-concurrency pass instead
  /// of finishing one folder before starting the next.
  ///
  /// [recentSkipWindow] drops comics whose folder row was checked inside the
  /// window; they are reported through [progress] as skipped. [isCurrent] is
  /// re-evaluated before every comic, so a page that lost its manager, folder
  /// or data path cancels the queue instead of writing into a replacement
  /// database. The single pool ceiling is what keeps the sources from being
  /// flooded, since the shelf mixes every folder's comics together.
  FollowUpdateJob.shelf({
    required List<ShelfUpdateTarget> targets,
    required LocalFavoritesManager manager,
    required bool Function() isCurrent,
    Duration recentSkipWindow = shelfRefreshSkipWindow,
    int concurrency = shelfRefreshConcurrency,
  }) : folder = '',
       ignoreCheckTime = true,
       _favorites = manager,
       _shelfTargets = targets,
       _recentSkipWindow = recentSkipWindow,
       _isCurrent = isCurrent,
       _concurrency = concurrency,
       _perSourceConcurrency = concurrency,
       _sourceInterval = Duration.zero {
    _attach();
  }

  final LocalFavoritesManager _favorites;

  /// The explicit shelf plan; `null` means the legacy single-folder plan.
  final List<ShelfUpdateTarget>? _shelfTargets;
  final Duration _recentSkipWindow;
  final bool Function()? _isCurrent;
  final int _concurrency;
  final int _perSourceConcurrency;
  final Duration _sourceInterval;

  void _attach() {
    _controller = StreamController<UpdateProgress>(
      onListen: _start,
      onCancel: cancel,
    );
    // Existing callers consume progress only. Keep that error channel usable
    // while lifecycle owners can independently await a failed completion.
    _done.future.ignore();
    if (_exitPreparation == null) {
      _jobs.add(this);
    } else {
      cancel();
    }
  }

  static FollowUpdateJob? _active;
  static final _jobs = <FollowUpdateJob>{};
  static final _updates = <RequestScope, Future<void>>{};
  static Future<void Function()>? _exitPreparation;
  static bool get isChecking => _active != null && !_active!._scope.isCancelled;
  static void cancelActive() => _active?.cancel();

  /// Freeze both jobs and direct updates, then cancel their remaining checks.
  /// All accepted writes and final notifications settle before this returns.
  /// Cancelled source calls may still finish their own underlying transport;
  /// their late results cannot enter the update's guarded database writes.
  static Future<void Function()> prepareForExit() {
    final existing = _exitPreparation;
    if (existing != null) return existing;
    final ready = Completer<void Function()>();
    final preparation = _exitPreparation = ready.future;
    final jobs = _jobs.toList();
    final updates = Map<RequestScope, Future<void>>.of(_updates);
    for (final job in jobs) {
      job.cancel();
    }
    for (final scope in updates.keys) {
      scope.cancel();
    }
    void release() {
      if (identical(_exitPreparation, preparation)) _exitPreparation = null;
    }

    Future.wait([for (final job in jobs) job.done, ...updates.values]).then(
      (_) => ready.complete(release),
      onError: (Object error, StackTrace stack) {
        release();
        ready.completeError(error, stack);
      },
    );
    return preparation;
  }

  final String folder;
  final bool ignoreCheckTime;
  final _scope = RequestScope();
  final _done = Completer<void>();
  bool _started = false;
  bool _finished = false;
  late final StreamController<UpdateProgress> _controller;
  Stream<UpdateProgress> get progress => _controller.stream;
  @override
  Stream<int> get updatedCounts => progress.map((value) => value.updated);
  @override
  Future<void> get done => _done.future;
  bool get isCancelled => _scope.isCancelled;
  @override
  void cancel() {
    if (_finished) return;
    _scope.cancel();
    if (!_started) _finish();
  }

  void _start() {
    if (_finished) return;
    if (_exitPreparation != null || isCancelled) {
      cancel();
      return;
    }
    _started = true;
    _active?.cancel();
    _active = this;
    unawaited(_run());
  }

  void _finish([Object? failure, StackTrace? failureStack]) {
    _finished = true;
    if (identical(_active, this)) _active = null;
    _jobs.remove(this);
    _scope.dispose();
    if (failure != null) {
      if (_controller.hasListener) _controller.addError(failure, failureStack);
      _done.completeError(failure, failureStack);
    } else {
      _done.complete();
    }
    // A paused or absent subscriber must not delay task ownership release.
    unawaited(_controller.close());
  }

  /// The legacy single-folder plan: every comic whose check time the caller's
  /// day-long recency policy accepts.
  List<ShelfUpdateTarget> _folderTargets() => [
    for (final comic in _favorites.getComicsWithUpdatesInfo(folder))
      if (ignoreCheckTime ||
          comic.lastCheckTime == null ||
          DateTime.now().difference(comic.lastCheckTime!).inDays >= 1)
        ShelfUpdateTarget(folder, comic),
  ];

  Future<void> _run() async {
    var current = 0;
    var errors = 0;
    var updated = 0;
    var skipped = 0;
    final pending = <Future<void>>[];
    Object? failure;
    StackTrace? failureStack;
    try {
      final favorites = _favorites;
      final generation = favorites.connectionGeneration;
      final now = DateTime.now();
      final targets = <ShelfUpdateTarget>[];
      for (final target in _shelfTargets ?? _folderTargets()) {
        final checkedAt = target.comic.lastCheckTime;
        if (_recentSkipWindow > Duration.zero &&
            checkedAt != null &&
            now.difference(checkedAt) < _recentSkipWindow) {
          skipped++;
          continue;
        }
        targets.add(target);
      }
      void emit([FavoriteItemWithUpdateInfo? comic, String? error]) {
        if (!isCancelled) {
          _controller.add(
            UpdateProgress(
              targets.length,
              current,
              errors,
              updated,
              comic,
              error,
              skipped,
            ),
          );
        }
      }

      emit();
      await runFollowUpdateTasks(
        targets,
        scope: _scope,
        sourceKey: (target) => target.comic.type.sourceKey,
        concurrency: _concurrency,
        perSourceConcurrency: _perSourceConcurrency,
        sourceInterval: _sourceInterval,
        run: (target) {
          final work = () async {
            // A page that lost its manager, folder or data path must not keep
            // issuing requests; cancelling the scope stops the whole queue.
            if (_isCurrent?.call() == false) {
              _scope.cancel();
              return;
            }
            final result = await updateComic(
              target.comic,
              target.folder,
              scope: _scope,
              manager: _favorites,
              generation: generation,
            );
            if (isCancelled || result.cancelled) return;
            // Counting and its progress event share one synchronous block, so
            // concurrent workers can neither lose an increment nor publish a
            // half-updated snapshot.
            current++;
            if (result.updated) updated++;
            if (result.errorMessage != null) errors++;
            emit(target.comic, result.errorMessage);
          }();
          pending.add(work);
          return work;
        },
      );
    } catch (error, stack) {
      if (error is! RequestCancelled) {
        failure = error;
        failureStack = stack;
      }
    } finally {
      try {
        // The queue can finish its cancellation race before the underlying
        // update callback has run its finally block. Join that business work.
        await Future.wait(pending);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      try {
        if (updated > 0) _favorites.notifyChanges();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      } finally {
        _finish(failure, failureStack);
      }
    }
  }
}

Stream<UpdateProgress> updateFolder(
  String folder,
  bool ignoreCheckTime, {
  LocalFavoritesManager? manager,
}) => FollowUpdateJob(folder, ignoreCheckTime, manager: manager).progress;

/// The preview represents the user's follow-updates folder, while the update
/// badge and count are separate hints on top of that list.
List<FavoriteItemWithUpdateInfo> getFollowUpdatesPreviewComics(
  String folder, {
  LocalFavoritesManager? manager,
}) {
  return (manager ?? LocalFavoritesManager()).getComicsWithUpdatesInfo(folder);
}

Future<String> getUpdatedComicsAsJson(
  String folder, {
  LocalFavoritesManager? manager,
}) async {
  var comics = (manager ?? LocalFavoritesManager()).getComicsWithUpdatesInfo(
    folder,
  );
  // The per-row update flag is gone, so this lists every comic in the folder
  // rather than only the ones flagged as changed.
  var jsonList = comics
      .map(
        (c) => {
          'id': c.id,
          'name': c.name,
          'coverUrl': c.coverPath,
          'author': c.author,
          'type': c.type.sourceKey,
          'updateTime': c.updateTime,
          'tags': c.tags,
        },
      )
      .toList();
  return jsonEncode(jsonList);
}
