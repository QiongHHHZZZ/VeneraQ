import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges the shelf page's own controls to the single navigation bar.
///
/// The shelf used to render a second app bar below the navigation bar, which
/// left two titles and two search buttons on screen. The page now publishes the
/// current folder and the actions it owns; the navigation bar renders them.
class ShelfToolbar extends ChangeNotifier {
  static final instance = ShelfToolbar();

  String? _folder;
  bool _hasFolders = false;
  bool _filterActive = false;
  bool _searching = false;
  VoidCallback? _openFolders;
  VoidCallback? _openFilter;
  VoidCallback? _toggleSearch;
  VoidCallback? _openDisplay;
  VoidCallback? _openFolderMenu;
  bool _canFolderMenu = false;
  bool _foldersOpenable = false;
  /// Folder currently shown, or null when the shelf shows its empty prompt.
  String? get folder => _folder;

  /// Whether the folder picker is reachable from the title.
  bool get hasFolders => _hasFolders;

  bool get filterActive => _filterActive;

  /// Whether the shelf is showing its own inline search field.
  bool get searching => _searching;

  bool get canFilter => _openFilter != null;


  bool get canSearch => _toggleSearch != null;

  /// Whether the shelf offers a display-mode chooser.
  bool get canChangeDisplay => _openDisplay != null;

  /// Rename / reorder / export / delete apply only to a real folder.
  bool get canFolderMenu => _canFolderMenu && _openFolderMenu != null;

  /// Whether the title bar can open the folder sidebar right now.
  ///
  /// Two things have to hold: the shelf's layout has to keep the folder list
  /// behind a drawer (the two-panel layout shows it already, so there is
  /// nothing to open), and a mounted shelf has to have published its picker.
  /// The navigation bar asks this instead of inferring it from the folder
  /// count or the window size.
  ///
  /// The layout answer outlives [unbind] — it describes the shelf, not the
  /// bound session — but a stored answer alone never offers the button.
  bool get canOpenFolders => _foldersOpenable && _openFolders != null;

  /// Publishes the state of the mounted shelf page.
  ///
  /// A null handler means "this caller has no such control" and leaves an
  /// existing handler in place. The outer favorites page owns only the folder
  /// picker while the inner list owns filter and search; overwriting with nulls
  /// made the toolbar buttons appear and disappear as either page republished.
  void bind({
    required String? folder,
    required bool hasFolders,
    required bool filterActive,
    required bool searching,
    VoidCallback? openFolders,
    VoidCallback? openFilter,
    VoidCallback? toggleSearch,
    VoidCallback? openDisplay,
    VoidCallback? openFolderMenu,
    bool canFolderMenu = false,
  }) {
    final changed =
        _folder != folder ||
        _hasFolders != hasFolders ||
        _filterActive != filterActive ||
        _searching != searching ||
        _canFolderMenu != canFolderMenu;
    _folder = folder;
    _hasFolders = hasFolders;
    _filterActive = filterActive;
    _searching = searching;
    if (openFolders != null) _openFolders = openFolders;
    if (openFilter != null) _openFilter = openFilter;
    if (toggleSearch != null) _toggleSearch = toggleSearch;
    if (openDisplay != null) _openDisplay = openDisplay;
    if (openFolderMenu != null) _openFolderMenu = openFolderMenu;
    _canFolderMenu = canFolderMenu;
    if (changed) notifyListeners();
  }

  /// Drops handlers when the shelf page leaves, so the bar cannot call a page
  /// that is no longer mounted.
  /// Drops handlers when a shelf page leaves.
  ///
  /// The folder opener belongs to the outer favorites page, which outlives the
  /// per-folder list underneath it. Clearing it here made the title-bar button
  /// unavailable for a frame on every folder switch, so a leaving list keeps it.
  void unbind({bool keepFolderOpener = false}) {
    if (_folder == null &&
        !_hasFolders &&
        (_openFolders == null || keepFolderOpener) &&
        _openFilter == null &&
        _toggleSearch == null) {
      return;
    }
    _folder = null;
    _hasFolders = false;
    _filterActive = false;
    _searching = false;
    if (!keepFolderOpener) _openFolders = null;
    _openFilter = null;
    _toggleSearch = null;
    _openDisplay = null;
    _openFolderMenu = null;
    _canFolderMenu = false;
    notifyListeners();
  }

  /// Publishes whether the shelf's layout keeps the folder list behind a
  /// drawer.
  ///
  /// The shelf page owns the breakpoint, so it answers this from its own build
  /// instead of letting the navigation bar guess. The value is stored at once —
  /// readers later in the same frame see the truth — while the notification is
  /// deferred to the end of that frame, because the navigation bar listening
  /// here is an ancestor of the page that publishes.
  void setFoldersOpenable(bool value) {
    if (_foldersOpenable == value) return;
    _foldersOpenable = value;
    unawaited(Future.microtask(notifyListeners));
  }

  void openFolders() => _openFolders?.call();

  void openFilter() => _openFilter?.call();

  /// Enters the shelf's inline search instead of opening a separate page.
  void toggleSearch() => _toggleSearch?.call();

  void openDisplay() => _openDisplay?.call();

  void openFolderMenu() => _openFolderMenu?.call();

}
