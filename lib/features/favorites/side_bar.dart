import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/favorites/favorite_actions.dart';
import 'package:venera_next/features/favorites/favorites_constants.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/favorites/folder_order_dialog.dart';
import 'package:venera_next/features/favorites/rename_favorite_folder_dialog.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';
import 'package:venera_next/routing/settings.dart';

abstract interface class FolderList {
  void update();

  void updateFolders();
}

class FavoritesFolderSidebar extends StatefulWidget {
  const FavoritesFolderSidebar({
    super.key,
    required this.selectedFolder,
    required this.isNetworkSelected,
    required this.onFolderSelected,
    this.onFolderListReady,
    this.onSelected,
    this.withAppbar = false,
  });

  final String? selectedFolder;

  final bool isNetworkSelected;

  final void Function(bool isNetwork, String? folder) onFolderSelected;

  final ValueChanged<FolderList>? onFolderListReady;

  final VoidCallback? onSelected;

  final bool withAppbar;

  @override
  State<FavoritesFolderSidebar> createState() => _FavoritesFolderSidebarState();
}

class _FavoritesFolderSidebarState extends State<FavoritesFolderSidebar>
    implements FolderList {
  var folders = <String>[];

  var networkFolders = <String>[];
  late final FavoriteStoreBinding _store;
  late final LocalFavoritesManager _manager;
  late final int _managerGeneration;

  bool get _hasManager =>
      _store.isCurrent && _manager.connectionGeneration == _managerGeneration;

  void findNetworkFolders() {
    networkFolders.clear();
    // A source that is not logged in has no reachable favorites: listing it
    // would open a page that can only report "Not login".
    var all = ComicSource.all()
        .where((e) => e.favoriteData != null && e.isLogged)
        .map((e) => e.favoriteData!.key)
        .toList();
    var settings = GlobalPreferenceStore(
      appdata.settings,
    ).read(DiscoveryPreferences.favoritePages);
    for (var p in settings) {
      if (all.contains(p) && !networkFolders.contains(p)) {
        networkFolders.add(p);
      }
    }
  }

  @override
  void initState() {
    _store = FavoritesScope.capture(context);
    _manager = _store.manager;
    _managerGeneration = _manager.connectionGeneration;
    widget.onFolderListReady?.call(this);
    folders = _manager.folderNames;
    findNetworkFolders();
    appdata.settings.addListener(updateFolders);
    _manager.addListener(updateFolders);
    super.initState();
  }

  @override
  void didUpdateWidget(FavoritesFolderSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The highlight is drawn from widget.selectedFolder, so a new selection has
    // to rebuild. Without this the drawer only updated when reopened.
    if (oldWidget.selectedFolder != widget.selectedFolder ||
        oldWidget.isNetworkSelected != widget.isNetworkSelected) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    appdata.settings.removeListener(updateFolders);
    _manager.removeListener(updateFolders);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        children: [
          // The drawer needs no heading of its own: the navigation bar above it
          // already names the destination, and repeating it wasted a whole row.
          Expanded(
            child: ListView.builder(
              padding: widget.withAppbar
                  ? EdgeInsets.zero
                  : EdgeInsets.only(top: context.padding.top),
              // Extra rows at the end: one each for the local title, the "All"
              // folder and the network title. The library entry that used to
              // follow the network folders is gone with the local comics page.
              itemCount: folders.length + networkFolders.length + 3,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return buildLocalTitle();
                }
                index--;
                if (index == 0) {
                  return buildLocalFolder(localAllFolderLabel);
                }
                index--;
                if (index < folders.length) {
                  return buildLocalFolder(folders[index]);
                }
                index -= folders.length;
                if (index == 0) {
                  return buildNetworkTitle();
                }
                index--;
                return buildNetworkFolder(networkFolders[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocalTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.local_activity, color: context.colorScheme.secondary),
          const SizedBox(width: 12),
          // "Local" alone collides with the local comics library, which holds
          // downloaded files; this section is the local favorites. The title
          // yields to the menu on narrow sidebars.
          Expanded(
            child: Text(
              "Local Favorites".tl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          MenuButton(
            entries: [
              MenuEntry(
                icon: Icons.add,
                text: 'Create Folder'.tl,
                onClick: () {
                  if (!_hasManager) return;
                  newFolder(
                    context,
                    onChanged: (next) {
                      if (!mounted || !_hasManager) return;
                      setState(() => folders = next);
                    },
                  );
                },
              ),
              MenuEntry(
                icon: Icons.reorder,
                text: 'Sort'.tl,
                onClick: () {
                  if (!_hasManager) return;
                  final owner = WindowSelectionTask(context);
                  if (!owner.canPresent) return;
                  sortFolders(context).then<void>(
                    (_) {
                      if (owner.canPresent && _hasManager) updateFolders();
                    },
                    onError: (Object error, StackTrace stack) {
                      Log.error('Favorite folder list', error, stack);
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget buildNetworkTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud, color: context.colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Network Favorites".tl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showPopUpWidget(
                appNavigation.rootContext,
                setFavoritesPagesWidget(),
              );
            },
          ),
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget buildLocalFolder(String name) {
    bool isSelected =
        name == widget.selectedFolder && !widget.isNetworkSelected;
    // "All" is a view over every folder, not a folder of its own, so it cannot
    // be renamed or deleted.
    final canManage = _canManageFolders && name != localAllFolderLabel;
    int count = 0;
    if (_hasManager) {
      count = name == localAllFolderLabel
          ? _manager.totalComics
          : _manager.folderComics(name);
    }
    var folderName = name == localAllFolderLabel
        ? "All".tl
        : getFavoriteDataOrNull(name)?.title ?? name;
    return ClickInkWell(
      onTap: () {
        if (isSelected) {
          return;
        }
        widget.onFolderSelected(false, name);
        widget.onSelected?.call();
      },
      // "All" is not a real folder; only a stored one can be renamed or
      // deleted, so the menu is offered on the named ones alone.
      onLongPress: canManage ? () => _showFolderMenu(name) : null,
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.toOpacity(0.36)
              : null,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? context.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(child: Text(folderName)),
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(count.toString()),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether [name] is a folder the reader can rename or delete.
  bool get _canManageFolders => _hasManager;

  /// Rename and delete for one folder.
  ///
  /// Long press rather than a permanent icon: these rows are narrow, and the
  /// actions are rare next to opening a folder.
  void _showFolderMenu(String name) {
    if (!_canManageFolders) return;
    final owner = WindowSelectionTask(context);
    if (!owner.canPresent) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text('Rename Folder'.tl),
              onTap: () {
                Navigator.pop(sheetContext);
                _renameFolder(name);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: sheetContext.colorScheme.error,
              ),
              title: Text(
                'Delete Folder'.tl,
                style: TextStyle(color: sheetContext.colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteFolder(name);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFolder(String name) async {
    if (!_canManageFolders) return;
    final target = name;
    final manager = _manager;
    final generation = _managerGeneration;
    bool current() =>
        mounted && _hasManager && manager.connectionGeneration == generation;
    await showDialog<void>(
      context: context,
      builder: (_) => RenameFavoriteFolderDialog(
        initialName: target,
        folders: manager.folderNames,
        isCurrent: current,
        rename: (next) => manager.rename(target, next),
      ),
    );
    if (!current()) return;
    updateFolders();
  }

  Future<void> _deleteFolder(String name) async {
    if (!_canManageFolders) return;
    final target = name;
    final manager = _manager;
    final generation = _managerGeneration;
    bool current() =>
        mounted && _hasManager && manager.connectionGeneration == generation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete folder?'.tl),
        content: Text(
          'The favorites in "@folder" are removed as well. The comics '
                  'themselves are not touched.'
              .tlParams({'folder': target}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete'.tl),
          ),
        ],
      ),
    );
    if (confirmed != true || !current()) return;
    try {
      await AppDataOperations.instance.access(() async {
        if (!current()) return;
        await manager.deleteFolder(target);
      });
    } catch (error, stack) {
      Log.error('Delete favorite folder', error, stack);
      if (mounted) context.showMessage(message: error.toString());
      return;
    }
    if (!current()) return;
    // The open folder may have just gone; fall back to "All" so the shelf is
    // never left pointing at a folder that no longer exists.
    if (widget.selectedFolder == target) {
      widget.onFolderSelected(false, localAllFolderLabel);
    }
    updateFolders();
  }

  Widget buildNetworkFolder(String key) {
    var data = getFavoriteDataOrNull(key);
    if (data == null) {
      return const SizedBox();
    }
    bool isSelected = key == widget.selectedFolder && widget.isNetworkSelected;
    return ClickInkWell(
      onTap: () {
        if (isSelected) {
          return;
        }
        widget.onFolderSelected(true, key);
        widget.onSelected?.call();
      },
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.toOpacity(0.36)
              : null,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? context.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Text(data.title),
      ),
    );
  }

  @override
  void update() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void updateFolders() {
    if (!mounted || !_hasManager) return;
    setState(() {
      folders = _manager.folderNames;
      findNetworkFolders();
    });
  }
}
