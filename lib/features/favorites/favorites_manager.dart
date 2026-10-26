import 'package:venera_next/foundation/operation_failure.dart';
import 'network_favorite_import.dart';
import 'favorite_folder_import.dart';
import 'favorite_updates_service.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/persistence_failure.dart';
import 'package:venera_next/foundation/sqlite_transaction.dart';
import 'favorite_identity_index.dart';
import 'package:venera_next/foundation/file_replacement.dart';
import 'favorites_repository.dart';
import 'favorite_models.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'favorite_cover_cache.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/sqlite_connection.dart';
import 'dart:io';

import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/comic_type.dart';

typedef FollowUpdatesChangeListener = void Function();

FollowUpdatesChangeListener? _followUpdatesChangeListener;

void registerFollowUpdatesChangeListener(
  FollowUpdatesChangeListener? listener,
) {
  _followUpdatesChangeListener = listener;
}

void _notifyFollowUpdatesChanged() {
  AppDataOperations.instance.publish(
    () => _followUpdatesChangeListener?.call(),
  );
}

/// Folder a brand-new library starts with, so the first favorite has a home.
///
/// It keeps the name the old tracking folder used, so an upgraded install sees
/// the same folder it always had; nothing marks it as special any more.
const defaultFolderName = '漫画';

class LocalFavoritesManager with ChangeNotifier {
  factory LocalFavoritesManager() => _cache ??= LocalFavoritesManager._create();

  LocalFavoritesManager._create();

  /// An independently owned store; it does not replace the default application store.
  factory LocalFavoritesManager.independent() =>
      LocalFavoritesManager._create();

  Future<void>? _mutationTail;

  /// Acquire global admission before joining this owner's local mutation queue.
  /// Paths and connection generations belong to admission, never late execution.
  Future<T> _mutate<T>(FutureOr<T> Function() action) =>
      AppDataOperations.instance.access(() {
        if (_database == null || _isClosed) {
          throw StateError('Favorites database is closed');
        }
        final generation = _connectionGeneration;
        final path = _dbPath;
        final result = Completer<T>();
        void execute() {
          Future<T>.sync(() {
            if (generation != _connectionGeneration ||
                path != _dbPath ||
                _isClosed) {
              throw StateError(
                'Favorites mutation belongs to a closed connection',
              );
            }
            return action();
          }).then(result.complete, onError: result.completeError);
        }

        final previous = _mutationTail;
        late Future<void> settled;
        settled = result.future
            .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
            .whenComplete(() {
              if (identical(_mutationTail, settled)) _mutationTail = null;
            });
        _mutationTail = settled;
        if (previous == null) {
          execute();
        } else {
          previous.then((_) => execute());
        }
        return result.future;
      });

  Future<void> updateOrder(List<String> folders) {
    final captured = List<String>.of(folders);
    return _mutate(() => _updateOrder(captured));
  }

  Future<void> addTagTo(String folder, String id, String tag) =>
      _mutate(() => _addTagTo(folder, id, tag));

  Future<String> createFolder(
    String name, [
    bool renameWhenInvalidName = false,
  ]) => _mutate(() => _createFolder(name, renameWhenInvalidName));

  Future<void> linkFolderToNetwork(
    String folder,
    String source,
    String networkFolder,
  ) => _mutate(() => _linkFolderToNetwork(folder, source, networkFolder));

  Future<bool> addComic(
    String folder,
    FavoriteItem comic, [
    int? order,
    String? updateTime,
    int? chapterCount,
  ]) {
    final captured = comic.detached();
    return _mutate(
      () => _addComic(folder, captured, order, updateTime, chapterCount),
    );
  }

  /// One accepted selection commits atomically, then publishes its exact result.
  Future<int> addComics(String folder, Iterable<FavoriteItem> comics) {
    final captured = comics.map((comic) => comic.detached()).toList();
    return _mutate(() {
      final added = _commitFavoriteTransaction(
        () => runSqliteTransaction(_db, () {
          if (!existsFolder(folder)) {
            throw StateError('Favorite folder no longer exists');
          }
          final append = true;
          return [
            for (final comic in captured)
              if (_repository.addComic(
                folder,
                comic,
                translatedTags: _translateTags(comic.tags),
                append: append,
              ))
                comic,
          ];
        }),
      );
      if (added.isNotEmpty) {
        _publishCommittedFavorites([
          folder,
        ], added.map((comic) => (comic.id, comic.type.value)));
      }
      return added.length;
    });
  }

  /// Borrow this connection's path while holding its mutation queue. The
  /// callback commits an addition in a coordinated SQLite transaction and
  /// returns its exact identity; caches and notifications are published here.
  Future<void> addComicWithStorage(
    String folder,
    List<String> tags,
    FavoriteItem Function(
      String databasePath,
      String translatedTags,
      bool append,
    )
    commit,
  ) {
    final capturedTags = List<String>.of(tags);
    return _mutate(() {
      if (!existsFolder(folder)) {
        throw const FormatException('Favorite folder no longer exists');
      }
      final comic = commit(_dbPath, _translateTags(capturedTags), true);
      // Read the committed count; do not increment a possibly stale cache after
      // a transaction that also changed another database.
      _publishCommittedFavorites([folder], [(comic.id, comic.type.value)]);
    });
  }

  Future<void> moveFavorite(
    String sourceFolder,
    String targetFolder,
    String id,
    ComicType type,
  ) => _mutate(() => _moveFavorite(sourceFolder, targetFolder, id, type));

  Future<void> batchMoveFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    final captured = items.map((item) => item.detached()).toList();
    return _mutate(
      () => _batchMoveFavorites(sourceFolder, targetFolder, captured),
    );
  }

  Future<void> batchCopyFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    final captured = items.map((item) => item.detached()).toList();
    return _mutate(
      () => _batchCopyFavorites(sourceFolder, targetFolder, captured),
    );
  }

  Future<void> deleteFolder(String name) => _mutate(() => _deleteFolder(name));

  Future<void> transferFavorites(
    String source,
    Iterable<String> targets,
    List<FavoriteItem> items, {
    required bool move,
  }) {
    final destinations = targets
        .where((folder) => folder != source)
        .toSet()
        .toList();
    final identities = items.map((item) => (item.id, item.type.value)).toList();
    return _mutate(() {
      if (destinations.isEmpty || identities.isEmpty) return;
      _commitFavoriteTransaction(
        () => _repository.transferToFolders(
          source,
          destinations,
          identities,
          move: move,
        ),
      );
      _publishCommittedFavorites([source, ...destinations], identities);
    });
  }

  Future<void> deleteComicWithId(String folder, String id, ComicType type) =>
      _mutate(() => _deleteComicWithId(folder, id, type));

  Future<void> batchDeleteComics(String folder, List<FavoriteItem> comics) {
    final captured = comics.map((item) => item.detached()).toList();
    return _mutate(() => _batchDeleteComics(folder, captured));
  }

  /// Removes these comics from the library entirely, whichever folders hold
  /// them.
  ///
  /// The shelf's "All" view shows comics from every folder at once, so removing
  /// one from "the current folder" means nothing there. This is the operation
  /// that view can offer: it drops every membership of the selected comics.
  Future<void> batchRemoveFromLibrary(List<FavoriteItem> comics) {
    final captured = comics.map((item) => item.detached()).toList();
    return _mutate(() {
      for (final comic in captured) {
        final folders = find(comic.id, comic.type);
        for (final folder in folders) {
          _deleteComicWithId(folder, comic.id, comic.type);
        }
      }
    });
  }

  Future<void> reorder(List<FavoriteItem> newFolder, String folder) {
    final captured = newFolder.map((item) => item.detached()).toList();
    return _mutate(() => _reorder(captured, folder));
  }

  Future<void> rename(String before, String after) =>
      _mutate(() => _rename(before, after));

  Future<void> onRead(
    String id,
    ComicType type, {
    int? generation,
    void Function()? checkActive,
  }) => _mutate(() {
    if (generation != null) _checkSourceGeneration(generation);
    checkActive?.call();
    _markAsRead(id, type);
  });

  Future<void> editTags(String id, String folder, List<String> tags) {
    final captured = List<String>.of(tags);
    return _mutate(() => _editTags(id, folder, captured));
  }

  /// Moves [oldId]'s placement onto [newId] and removes the old entry.
  ///
  /// Used when the reader finds the same comic on a working source: the shelf
  /// should keep one entry, carrying the old folders and ordering.
  void moveFavoriteOnto({
    required Iterable<String> folders,
    required String oldId,
    required ComicType oldType,
    required String newId,
    required ComicType newType,
  }) {
    _repository.moveOnto(folders, oldId, oldType.value, newId, newType.value);
    _refreshIdentityCounts([(oldId, oldType.value), (newId, newType.value)]);
    refreshUpdateIds();
    notifyListeners();
  }

  int get connectionGeneration => _connectionGeneration;

  void _checkSourceGeneration(int generation) {
    if (generation != _connectionGeneration) {
      throw StateError(
        'Favorite source response belongs to a replaced database',
      );
    }
  }

  Future<void> updateInfo(
    String folder,
    FavoriteItem comic, {
    required int generation,
    void Function()? checkActive,
  }) {
    final captured = comic.detached();
    return _mutate(() {
      _checkSourceGeneration(generation);
      checkActive?.call();
      _updateInfo(folder, captured);
    });
  }

  /// Stores the chapter total for one favorite.
  ///
  /// The update timestamp and its flag are gone with the tracking feature; only
  /// the total remains, because the unread badge is derived from it.
  Future<void> applyFollowUpdate(
    String folder,
    FavoriteItem comic, {
    required int generation,
    required void Function() checkActive,
    int? chapterCount,
  }) {
    final captured = comic.detached();
    return _mutate(() {
      _checkSourceGeneration(generation);
      checkActive();
      _repository.applyChapterRefresh(
        folder,
        captured,
        DateTime.now().millisecondsSinceEpoch,
        chapterCount: chapterCount,
      );
    });
  }

  Future<NetworkFavoriteImportCommit> importNetworkFavorites(
    String folder,
    String source,
    String folderId,
    List<FavoriteItem> items, {
    required bool oldToNew,
    void Function()? checkActive,
    int? generation,
  }) {
    final captured = items.map((item) => item.detached()).toList();
    return _mutate(() {
      if (generation != null) _checkSourceGeneration(generation);
      checkActive?.call();
      return _importNetworkFavorites(
        folder,
        source,
        folderId,
        captured,
        oldToNew: oldToNew,
      );
    });
  }

  Future<void> fromJson(String json) => _mutate(() => _fromJson(json));

  Future<bool> prepareTableForFollowUpdates(
    String table, {
    bool clearData = true,
    int? generation,
    bool Function()? isCurrent,
  }) => _mutate(() {
    if (generation != null) _checkSourceGeneration(generation);
    if (isCurrent?.call() == false) return false;
    _prepareTableForFollowUpdates(table, clearData);
    return true;
  });

  Future<void> updateUpdateTime(
    String folder,
    String id,
    ComicType type,
    String updateTime,
  ) => _mutate(() => _updateUpdateTime(folder, id, type, updateTime));

  Future<void> updateCheckTime(String folder, String id, ComicType type) =>
      _mutate(() => _updateCheckTime(folder, id, type));

  Future<void> markAsRead(String id, ComicType type, {bool notify = true}) =>
      _mutate(() => _markAsRead(id, type, notify: notify));

  /// The confirmation owns a folder and immutable identities. A later tracking
  /// selection must not redirect these writes to a different folder.
  Future<void> markAllAsRead(String folder, List<FavoriteItem> comics) {
    final identities = comics
        .map((comic) => (comic.id, comic.type.value))
        .toList();
    return _mutate(() async {
      _commitFavoriteTransaction(
        () => _repository.markComicsAsRead(folder, identities),
      );
      await _finishFolderMutation(() => appdata.saveData(), () => false);
    });
  }

  @override
  void notifyListeners() =>
      AppDataOperations.instance.publish(super.notifyListeners);

  static LocalFavoritesManager? _cache;

  static LocalFavoritesManager? get cache => _cache;

  Database? _database;

  Database get _db =>
      _database ?? (throw StateError('Favorites database is closed'));

  Future<void>? _initialization;
  Future<void>? _closing;
  Future<void>? _clearing;
  Future<void>? _clearRequest;
  final _pendingReads = <Future<void>>{};
  int _connectionGeneration = 0;

  FavoritesRepository get _repository => FavoritesRepository(_db);

  late String _dbPath;

  String get databasePath {
    if (_database == null || _isClosed) {
      throw StateError('Favorites database is closed');
    }
    return _dbPath;
  }

  /// Reconcile external additions before any import completion notifications.
  void refreshImportedFavorites(Map<String, List<FavoriteItem>> folders) {
    for (final folder in folders.keys) {
      counts[folder] = count(folder);
    }
    _refreshIdentityCounts(
      folders.values
          .expand((items) => items)
          .map((item) => (item.id, item.type.value)),
    );
    refreshUpdateIds();
  }

  void notifyImportedFavorites(Iterable<String> folders) {
    _publishFavoriteChanges([notifyListeners]);
  }

  Map<String, int> counts = {};

  final _identityIndex = FavoriteIdentityIndex();

  late final _updates = FavoriteUpdatesService(
    repository: () => _repository,
    folders: () => folderNames,
  );

  Future<void>? _hashedIdsRefresh;
  final _pendingSettingsRepairs = <String>{};

  bool _isClosed = true;

  int get totalComics {
    return _identityIndex.length;
  }

  int folderComics(String folder) {
    return counts[folder] ?? 0;
  }

  Future<void> init({void Function(void Function())? publishChange}) =>
      AppDataOperations.instance.access(
        () => _initializeAfterTransitions(
          '${App.dataPath}/local_favorite.db',
          publishChange: publishChange,
        ),
      );

  Future<void> _initializeAfterTransitions(
    String path, {
    void Function(void Function())? publishChange,
  }) {
    final clearing = _clearing;
    if (clearing != null) {
      if (path != _dbPath) {
        return Future.error(
          StateError('Favorites is clearing a different data path'),
        );
      }
      return clearing;
    }
    final closing = _closing;
    if (closing != null) {
      return closing.then(
        (_) => _initializeAfterTransitions(path, publishChange: publishChange),
      );
    }
    return _startInitialization(path, publishChange: publishChange);
  }

  Future<void> _startInitialization(
    String path, {
    void Function(void Function())? publishChange,
    bool retryPendingSettings = true,
  }) {
    final existing = _initialization;
    if (existing != null) {
      if (_dbPath != path) {
        return Future.error(
          StateError('Close favorites before changing its data path'),
        );
      }
      return existing;
    }
    final attempt = Completer<void>();
    _initialization = attempt.future;
    _dbPath = path;
    final generation = ++_connectionGeneration;
    Future<void>.sync(
      () => _initialize(
        path,
        generation,
        publishChange: publishChange,
        retryPendingSettings: retryPendingSettings,
      ),
    ).then(
      (_) {
        if (generation != _connectionGeneration) {
          attempt.completeError(
            StateError('Favorites initialization was closed'),
          );
        } else {
          attempt.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_initialization, attempt.future)) {
          _initialization = null;
        }
        attempt.completeError(error, stack);
      },
    );
    return attempt.future;
  }

  void _checkInitialization(int generation) {
    if (_connectionGeneration != generation) {
      throw StateError('Favorites initialization was closed');
    }
  }

  Future<void> _initialize(
    String path,
    int generation, {
    void Function(void Function())? publishChange,
    bool retryPendingSettings = true,
  }) async {
    Database? database;
    var published = false;
    try {
      if (App.isInitialized) await appdata.ensureInit();
      _checkInitialization(generation);
      database = openSqliteDatabase(path);
      final repository = FavoritesRepository(database);
      repository.initializeMetadata();
      var folders = repository.folderNames();
      if (folders.isEmpty) {
        // Collecting needs somewhere to put the comic. An empty library gets one
        // plain folder so the first favorite works; it is an ordinary folder and
        // can be renamed or deleted afterwards.
        repository.createFolder(defaultFolderName);
        folders = repository.folderNames();
      }
      repository.migrateTranslatedTags(folders, _translateTags);
      _checkInitialization(generation);
      _database = database;
      published = true;
      _isClosed = false;
      _identityIndex.clear();
      counts = {};
      final retryingWrite =
          retryPendingSettings && _pendingSettingsRepairs.contains(path);
      try {
        if (retryingWrite) await appdata.saveData(false);
        _pendingSettingsRepairs.remove(path);
      } catch (_) {
        _pendingSettingsRepairs.add(path);
        rethrow;
      }
      _checkInitialization(generation);
      await _initCounts(publishChange: publishChange);
    } catch (_) {
      if (!published) {
        database?.dispose();
      } else if (identical(_database, database)) {
        close();
      }
      rethrow;
    }
  }

  Future<void> _initCounts({
    void Function(void Function())? publishChange,
  }) async {
    for (var folder in folderNames) {
      counts[folder] = count(folder);
    }
    refreshUpdateIds();
    await _refreshHashedIds(publishChange: publishChange);
  }

  Future<void> refreshHashedIds() => _refreshHashedIds();

  /// The folder a fresh install starts with.
  ///

  Future<void> _refreshHashedIds({
    void Function(void Function())? publishChange,
  }) {
    late Future<void> refresh;
    refresh = _mutate(() async {
      final folders = folderNames;
      final generation = _identityIndex.beginRefresh();
      try {
        if (folders.isEmpty) {
          _identityIndex.completeRefresh(generation, {});
          return;
        }
        final value = await _startRead((path) => _initHashedIds(folders, path));
        if (_isClosed || !_identityIndex.completeRefresh(generation, value)) {
          return;
        }
        if (publishChange == null) {
          notifyListeners();
        } else {
          AppDataOperations.instance.publish(
            () => publishChange(notifyListeners),
          );
        }
      } catch (_) {
        _identityIndex.failRefresh(generation);
        rethrow;
      }
    });
    refresh.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!_isClosed && identical(_hashedIdsRefresh, refresh)) {
          Log.error('LocalFavoritesManager', error, stack);
        }
      },
    );
    _hashedIdsRefresh = refresh;
    return refresh;
  }

  @visibleForTesting
  Future<void> debugWaitForHashedIdsRefresh() async {
    // Initialization may still be queued behind settings before starting its
    // identity read. Do not accidentally await the previous connection's read.
    await _initialization;
    await _hashedIdsRefresh;
  }

  void refreshUpdateIds() => _updates.refresh();

  void _refreshIdentityCounts(Iterable<(String, int)> identities) {
    final requested = identities.toSet();
    final counts = _repository.referenceCounts(folderNames, requested);
    for (final identity in requested) {
      _identityIndex.setCount(identity, counts[identity] ?? 0);
    }
  }

  static Future<Map<(String, int), int>> _initHashedIds(
    List<String> folders,
    String dbPath,
  ) {
    return Isolate.run(() {
      var db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      try {
        var identities = <(String, int), int>{};
        for (var folder in folders) {
          for (final (id, type) in FavoritesRepository(db).identities(folder)) {
            final identity = (id, type);
            identities[identity] = (identities[identity] ?? 0) + 1;
          }
        }
        return identities;
      } finally {
        db.dispose();
      }
    });
  }

  List<String> find(String id, ComicType type) =>
      _repository.findFolders(folderNames, id, type.value);

  Future<List<String>> findWithModel(FavoriteItem item) {
    final id = item.id;
    final type = item.type;
    return _mutate(() => find(id, type));
  }

  void _updateOrder(List<String> folders) {
    _repository.updateOrder(folders);
    notifyListeners();
  }

  int count(String folderName) => _repository.count(folderName);

  List<String> get folderNames => _repository.folderNames();

  int maxValue(String folder) => _repository.maxValue(folder);

  int minValue(String folder) => _repository.minValue(folder);

  List<FavoriteItem> getFolderComics(String folder) =>
      _repository.getFolderComics(folder);

  Future<T> _runRead<T>(Future<T> Function(String path) read) =>
      _mutate(() => _startRead(read));

  Future<T> _startRead<T>(Future<T> Function(String path) read) {
    if (_database == null || _isClosed) {
      return Future.error(StateError('Favorites database is closed'));
    }
    final generation = _connectionGeneration;
    final path = _dbPath;
    final result = Future<T>.sync(() => read(path)).then((value) {
      if (generation != _connectionGeneration || _isClosed) {
        throw StateError('Favorites read belongs to a closed connection');
      }
      return value;
    });
    // Observe completion for draining without consuming the caller's error.
    late Future<void> settled;
    settled = result
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
        .whenComplete(() => _pendingReads.remove(settled));
    _pendingReads.add(settled);
    return result;
  }

  static Future<List<FavoriteItem>> _getFolderComicsAsync(
    String folder,
    String dbPath,
  ) {
    return Isolate.run(() {
      var db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      try {
        return FavoritesRepository(db).getFolderComics(folder);
      } finally {
        db.dispose();
      }
    });
  }

  /// Start a new isolate to get the comics in the folder
  Future<List<FavoriteItem>> getFolderComicsAsync(String folder) {
    return _runRead((path) => _getFolderComicsAsync(folder, path));
  }

  List<FavoriteItem> getAllComics() => _repository.getAllComics(folderNames);

  static Future<List<FavoriteItem>> _getAllComicsAsync(
    List<String> folders,
    String dbPath,
  ) {
    return Isolate.run(() {
      var db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      try {
        return FavoritesRepository(db).getAllComics(folders);
      } finally {
        db.dispose();
      }
    });
  }

  /// Start a new isolate to get all the comics
  Future<List<FavoriteItem>> getAllComicsAsync() {
    return _runRead((path) => _getAllComicsAsync(folderNames, path));
  }

  void _addTagTo(String folder, String id, String tag) {
    _repository.addTagTo(folder, id, tag);
    notifyListeners();
  }

  List<FavoriteItemWithFolderInfo> allComics() =>
      _repository.allComics(folderNames);

  bool existsFolder(String name) {
    return folderNames.contains(name);
  }

  /// create a folder
  String _createFolder(String name, [bool renameWhenInvalidName = false]) {
    if (name.isEmpty) {
      if (renameWhenInvalidName) {
        int i = 0;
        while (existsFolder(i.toString())) {
          i++;
        }
        name = i.toString();
      } else {
        throw OperationFailure.message("name is empty!");
      }
    }
    if (existsFolder(name)) {
      if (renameWhenInvalidName) {
        var prevName = name;
        int i = 0;
        while (existsFolder(i.toString())) {
          i++;
        }
        name = prevName + i.toString();
      } else {
        throw Exception("Folder is existing");
      }
    }
    _repository.createFolder(name);
    counts[name] = 0;
    notifyListeners();
    return name;
  }

  void _linkFolderToNetwork(
    String folder,
    String source,
    String networkFolder,
  ) => _repository.linkFolderToNetwork(folder, source, networkFolder);

  bool isLinkedToNetworkFolder(
    String folder,
    String source,
    String networkFolder,
  ) => _repository.isLinkedToNetworkFolder(folder, source, networkFolder);

  (String?, String?) findLinked(String folder) =>
      _repository.findLinked(folder);

  bool comicExists(String folder, String id, ComicType type) =>
      _repository.comicExists(folder, id, type.value);

  FavoriteItem getComic(String folder, String id, ComicType type) =>
      _repository.findComic(folder, id, type.value) ??
      (throw Exception("Comic not found"));

  String _translateTags(List<String> tags) {
    var res = <String>[];
    for (var tag in tags) {
      var translated = tag.translateTagsToCN;
      if (translated != tag) {
        res.add(translated);
      }
    }
    return res.join(",");
  }

  /// add comic to a folder.
  /// return true if success, false if already exists
  bool _addComic(
    String folder,
    FavoriteItem comic, [
    int? order,
    String? updateTime,
    int? chapterCount,
  ]) {
    if (!existsFolder(folder)) {
      throw Exception("Folder does not exists");
    }
    final added = _repository.addComic(
      folder,
      comic,
      translatedTags: _translateTags(comic.tags),
      append: true,
      order: order,
      updateTime: updateTime,
      chapterCount: chapterCount,
    );
    if (!added) return false;
    _publishCommittedFavorites([folder], [(comic.id, comic.type.value)]);
    return true;
  }

  void _moveFavorite(
    String sourceFolder,
    String targetFolder,
    String id,
    ComicType type,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }

    if (!_repository.moveFavorite(sourceFolder, targetFolder, id, type.value)) {
      return;
    }

    _publishCommittedFavorites(
      [sourceFolder, targetFolder],
      [(id, type.value)],
    );
  }

  void _batchMoveFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }
    if (items.isEmpty || sourceFolder == targetFolder) {
      return;
    }

    try {
      _repository.moveMany(
        sourceFolder,
        targetFolder,
        items.map((item) => (item.id, item.type.value)),
      );
    } catch (e) {
      Log.error("Batch Move Favorites", e.toString());
      rethrow;
    }

    _publishCommittedFavorites([
      sourceFolder,
      targetFolder,
    ], items.map((item) => (item.id, item.type.value)));
  }

  void _batchCopyFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) {
    if (!existsFolder(sourceFolder)) {
      throw Exception("Source folder does not exist");
    }
    if (!existsFolder(targetFolder)) {
      throw Exception("Target folder does not exist");
    }
    if (items.isEmpty || sourceFolder == targetFolder) {
      return;
    }

    try {
      _repository.copyMany(
        sourceFolder,
        targetFolder,
        items.map((item) => (item.id, item.type.value)),
      );
    } catch (e) {
      Log.error("Batch Copy Favorites", e.toString());
      rethrow;
    }

    _publishCommittedFavorites([
      targetFolder,
    ], items.map((item) => (item.id, item.type.value)));
  }

  /// delete a folder
  Future<void> _deleteFolder(String name) async {
    final removedIdentities = _repository.identities(name);
    _commitFavoriteTransaction(() => _repository.deleteFolder(name));
    try {
      counts.remove(name);
      _refreshIdentityCounts(removedIdentities);
    } catch (error, stack) {
      _throwCommittedFailure(error, stack);
    }
  }

  T _commitFavoriteTransaction<T>(T Function() commit) {
    try {
      return commit();
    } on SqliteTransactionRollbackError catch (error, stack) {
      Error.throwWithStackTrace(
        PersistenceFailure(
          commitState: PersistenceCommitState.unknown,
          cause: error.operationError,
          stackTrace: error.operationStack,
          cleanupFailures: [
            (error: error.rollbackError, stackTrace: error.rollbackStack),
          ],
        ),
        stack,
      );
    } catch (error, stack) {
      Error.throwWithStackTrace(
        PersistenceFailure(
          commitState: PersistenceCommitState.notCommitted,
          cause: error,
          stackTrace: stack,
        ),
        stack,
      );
    }
  }

  Never _throwCommittedFailure(Object error, StackTrace stack) {
    if (error is PersistenceFailure &&
        error.commitState == PersistenceCommitState.committed) {
      Error.throwWithStackTrace(error, stack);
    }
    Error.throwWithStackTrace(
      PersistenceFailure(
        commitState: PersistenceCommitState.committed,
        cause: error,
        stackTrace: stack,
      ),
      stack,
    );
  }

  void _publishCommittedFavorites(
    Iterable<String> folders,
    Iterable<(String, int)> identities,
  ) {
    final affected = folders.toSet();
    _publishFavoriteChanges([
      for (final folder in affected) () => counts[folder] = count(folder),
      () => _refreshIdentityCounts(identities),
      // The chapter total written by this collect lives in the database, while
      // the shelf badge reads a cached snapshot; refresh it in place so the
      // number shows up without waiting for a manual pull-to-refresh.
      refreshUpdateIds,
      notifyListeners,
    ]);
  }

  /// A committed write is not undone by an observer failure. Attempt each
  /// independent publication and preserve all failures for the original owner.
  void _publishFavoriteChanges(
    Iterable<void Function()> actions, {
    Iterable<({Object error, StackTrace stackTrace})> priorFailures = const [],
    PersistenceCommitState commitState = PersistenceCommitState.committed,
  }) {
    final failures = [...priorFailures];
    for (final action in actions) {
      try {
        action();
      } catch (error, stack) {
        failures.add((error: error, stackTrace: stack));
      }
    }

    if (failures.isNotEmpty) {
      final first = failures.first;
      Error.throwWithStackTrace(
        PersistenceFailure(
          commitState: commitState,
          cause: first.error,
          stackTrace: first.stackTrace,
          cleanupFailures: failures.skip(1),
        ),
        first.stackTrace,
      );
    }
  }

  /// SQL may already be committed. Publish the resulting state even if the
  /// settings draft cannot persist, retaining the outcome and all failures.
  Future<void> _finishFolderMutation(
    Future<void> Function() saveSettings,
    bool Function() followChanged, {
    PersistenceCommitState commitState = PersistenceCommitState.committed,
  }) async {
    final failures = <({Object error, StackTrace stackTrace})>[];
    try {
      await saveSettings();
    } catch (error, stack) {
      failures.add((error: error, stackTrace: stack));
    }
    _publishFavoriteChanges(
      [
        refreshUpdateIds,
        () {
          if (followChanged()) _notifyFollowUpdatesChanged();
        },
        notifyListeners,
      ],
      priorFailures: failures,
      commitState: commitState,
    );
  }

  void _applyDeletedComics(Map<String, List<(String, int)>> removed) {
    if (removed.isEmpty) return;
    final identities = removed.values.expand((items) => items).toSet();
    _publishFavoriteChanges([
      for (final folder in removed.keys) () => counts[folder] = count(folder),
      () => _refreshIdentityCounts(identities),
      () {
        // Covers are shared across folders and cannot participate in rollback.
        // Release them only after commit and after checking the last reference.
        final folders = folderNames;
        for (final (id, type) in identities) {
          if (_repository.findFolders(folders, id, type).isNotEmpty) continue;
          try {
            deleteFavoriteCover(
              dataDirectory: App.dataPath,
              id: id,
              intKey: type,
            );
          } catch (error, stack) {
            Log.error('Favorite cover cleanup', error, stack);
          }
        }
      },
      notifyListeners,
    ]);
  }

  /// Publish deletions committed by a coordinated database transaction.
  void refreshDeletedFavorites(Map<String, List<(String, int)>> removed) =>
      _applyDeletedComics(removed);

  void _deleteComicWithId(String folder, String id, ComicType type) {
    _applyDeletedComics(_repository.deleteComics([folder], [(id, type.value)]));
  }

  void _batchDeleteComics(String folder, List<FavoriteItem> comics) {
    if (comics.isEmpty) return;
    late Map<String, List<(String, int)>> removed;
    try {
      removed = _commitFavoriteTransaction(
        () => _repository.deleteComics([
          folder,
        ], comics.map((comic) => (comic.id, comic.type.value))),
      );
    } catch (error) {
      Log.error('Batch Delete Comics', error.toString());
      rethrow;
    }
    try {
      _applyDeletedComics(removed);
    } catch (error, stack) {
      _throwCommittedFailure(error, stack);
    }
  }

  Future<void> clearAll() {
    final existing = _clearRequest;
    if (existing != null) return existing;
    if (_database == null || _isClosed) {
      return Future.error(StateError('Favorites database is closed'));
    }
    final path = _dbPath;
    final attempt = Completer<void>();
    _clearRequest = attempt.future;
    AppDataOperations.instance
        .run(() async {
          if (_dbPath != path) {
            throw StateError('Favorites clear belongs to another data path');
          }
          _clearing = attempt.future;
          await _clearDatabase(path);
        })
        .then(
          (_) {
            _clearing = null;
            _clearRequest = null;
            attempt.complete();
          },
          onError: (Object error, StackTrace stack) {
            _clearing = null;
            _clearRequest = null;
            attempt.completeError(error, stack);
          },
        );
    return attempt.future;
  }

  Future<void> _clearDatabase(String path) async {
    await _closeAndWait();
    Directory? backupDirectory;
    FileReplacement? replacement;
    var prepared = false;
    try {
      backupDirectory = File(path).parent.createTempSync('.favorite_clear_');
      replacement = FileReplacement(
        path,
        '${backupDirectory.path}/local_favorite.db',
      );
      replacement.backup();
      prepared = true;
      await _startInitialization(path);
    } catch (error, stack) {
      final failures = <({Object error, StackTrace stackTrace})>[];
      Future<bool> recover(FutureOr<void> Function() action) async {
        try {
          await action();
          return true;
        } catch (error, stack) {
          failures.add((error: error, stackTrace: stack));
          return false;
        }
      }

      final closed = await recover(_closeAndWait);
      final restored =
          closed && (!prepared || await recover(() => replacement!.restore()));
      await recover(() => appdata.restoreSettingsFields({}, persist: false));
      if (restored) {
        // An unavailable settings file must not prevent reopening the restored
        // database. The separate flush below still reports durability failure.
        await recover(
          () => _startInitialization(path, retryPendingSettings: false),
        );
      }
      if (await recover(() => appdata.saveData(false))) {
        _pendingSettingsRepairs.remove(path);
      } else {
        _pendingSettingsRepairs.add(path);
      }
      // An unsuccessful restore must retain its backup for manual recovery.
      if (replacement == null || !replacement.backupFile.existsSync()) {
        await recover(() => _removeClearBackupDirectory(backupDirectory));
      }
      if (failures.isNotEmpty) {
        Error.throwWithStackTrace(
          PersistenceFailure(
            commitState: PersistenceCommitState.unknown,
            cause: error,
            stackTrace: stack,
            cleanupFailures: failures,
          ),
          stack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
    final failures = <({Object error, StackTrace stackTrace})>[];
    try {
      replacement.commit();
    } catch (error, stack) {
      failures.add((error: error, stackTrace: stack));
    }
    try {
      _removeClearBackupDirectory(backupDirectory);
    } catch (error, stack) {
      failures.add((error: error, stackTrace: stack));
    }
    if (failures.isNotEmpty) {
      // Clearing succeeded; cleanup failures must not roll back the new DB.
      Error.throwWithStackTrace(
        PersistenceFailure(
          commitState: PersistenceCommitState.committed,
          cause: failures.first.error,
          stackTrace: failures.first.stackTrace,
          cleanupFailures: failures.skip(1),
        ),
        failures.first.stackTrace,
      );
    }
  }

  void _removeClearBackupDirectory(Directory? directory) {
    if (directory == null || !directory.existsSync()) return;
    directory.deleteSync();
  }

  void _reorder(List<FavoriteItem> newFolder, String folder) {
    if (!existsFolder(folder)) {
      throw Exception("Failed to reorder: folder not found");
    }
    try {
      _repository.reorder(
        folder,
        newFolder.map((item) => (item.id, item.type.value)),
      );
    } catch (e) {
      Log.error("Reorder", e.toString());
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _rename(String before, String after) async {
    if (existsFolder(after)) {
      throw OperationFailure.message("Name already exists!");
    }
    if (after.contains('"')) {
      throw OperationFailure.message("Invalid name");
    }
    _repository.renameFolder(before, after);
    counts[after] = counts[before] ?? 0;
    counts.remove(before);
  }

  List<FavoriteItem> searchInFolder(String folder, String keyword) =>
      _repository.searchInFolder(folder, keyword);

  List<FavoriteItem> search(String keyword) =>
      _repository.search(folderNames, keyword);

  void _editTags(String id, String folder, List<String> tags) {
    _repository.editTags(folder, id, tags);
    notifyListeners();
  }

  bool isExist(String id, ComicType type) {
    return _identityIndex.contains(id, type.value);
  }

  /// Chapters recorded by the last update check, or null when unknown.
  int? chapterCountOf(String id, ComicType type) =>
      _updates.chapterCountFor(id, type.value);

  void _updateInfo(String folder, FavoriteItem comic, [bool notify = true]) {
    _commitFavoriteTransaction(() => _repository.updateInfo(folder, comic));
    if (notify) {
      try {
        notifyListeners();
      } catch (error, stack) {
        _throwCommittedFailure(error, stack);
      }
    }
  }

  String folderToJson(String folder) {
    return jsonEncode({
      "info": "Generated by VeneraQ",
      "name": folder,
      "comics": _repository
          .exportComics(folder)
          .map((item) => item.toJson())
          .toList(),
    });
  }

  NetworkFavoriteImportCommit _importNetworkFavorites(
    String folder,
    String source,
    String folderId,
    List<FavoriteItem> items, {
    required bool oldToNew,
  }) {
    final added = commitNetworkFavorites(
      _repository,
      folder: folder,
      source: source,
      folderId: folderId,
      items: items,
      append: true,
      oldToNew: oldToNew,
      translateTags: _translateTags,
    );
    return NetworkFavoriteImportCommit(
      folder,
      added,
      owner: this,
      generation: _connectionGeneration,
    );
  }

  /// Retryable publication of an already committed import; never writes SQL.
  Future<void> publishNetworkFavoriteImport(
    NetworkFavoriteImportCommit result,
  ) => _mutate(() {
    // Reopening rebuilds the current cache. An old receipt has no authority to
    // publish into that connection, even when the path and folder are reused.
    if (!identical(result.owner, this) ||
        result.generation != _connectionGeneration) {
      return;
    }
    _publishFavoriteChanges([
      () => counts[result.folder] = count(result.folder),
      () => _refreshIdentityCounts(result.identities),
      refreshUpdateIds,
      notifyListeners,
    ]);
  });

  void _fromJson(String json) {
    final (folder, comics) = importFavoriteFolder(
      json,
      _repository,
      append: true,
      translateTags: _translateTags,
    );
    _publishFavoriteChanges([
      () => refreshImportedFavorites({folder: comics}),
      notifyListeners,
    ]);
  }

  void _prepareTableForFollowUpdates(String table, [bool clearData = true]) {
    _repository.prepareForFollowUpdates(table, clearData: clearData);
    refreshUpdateIds();
  }

  /// Comics in [folder] with their chapter totals, for the shelf refresh.
  ///
  /// The update flag this used to carry is gone; the totals still feed the
  /// unread badge.
  List<FavoriteItemWithUpdateInfo> getComicsWithUpdatesInfo(String folder) =>
      existsFolder(folder) ? _repository.getComicsWithUpdatesInfo(folder) : [];

  void _updateUpdateTime(
    String folder,
    String id,
    ComicType type,
    String updateTime,
  ) {
    _repository.updateUpdateTime(
      folder,
      id,
      type.value,
      updateTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _updateCheckTime(String folder, String id, ComicType type) =>
      _repository.updateCheckTime(
        folder,
        id,
        type.value,
        DateTime.now().millisecondsSinceEpoch,
      );

  void _markAsRead(String id, ComicType type, {bool notify = true}) {
    // Marking read is no longer tied to a tracked folder or a per-row flag: the
    // read set lives in history, so this only reports the change.
    if (notify) {
      _publishFavoriteChanges([notifyListeners]);
    }
  }

  /// Freeze new accesses and wait for accepted reads/writes before closing.
  Future<void> closeAndWait() =>
      AppDataOperations.instance.run(() => _closeAfterClear());

  Future<void> _closeAfterClear() {
    final clearing = _clearing;
    if (clearing != null) {
      return clearing.then(
        (_) => _closeAndWait(),
        onError: (Object error, StackTrace stack) => _closeAndWait(),
      );
    }
    return _closeAndWait();
  }

  Future<void> _closeAndWait() {
    final existing = _closing;
    if (existing != null) return existing;
    close();
    late Future<void> closing;
    closing = Future.wait(List<Future<void>>.of(_pendingReads))
        .then<void>((_) {})
        .whenComplete(() {
          if (identical(_closing, closing)) _closing = null;
        });
    _closing = closing;
    return closing;
  }

  void close() => AppDataOperations.instance.accessSync(_closeImmediately);

  void _closeImmediately() {
    _connectionGeneration++;
    _initialization = null;
    _isClosed = true;
    _identityIndex.clear();
    _updates.clear();
    counts.clear();
    final database = _database;
    _database = null;
    database?.dispose();
  }

  void notifyChanges() {
    refreshUpdateIds();
    notifyListeners();
  }
}
