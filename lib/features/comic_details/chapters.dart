import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/foundation/history_contract.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

/// One-based indices of every chapter earlier than [chapter].
///
/// Range actions pivot on a chapter the reader picked, so the maths lives here
/// where it can be tested without a widget.
Set<int> chaptersBefore(int chapter) => {for (var i = 1; i < chapter; i++) i};

/// One-based indices of every chapter later than [chapter], within [total].
Set<int> chaptersAfter(int chapter, int total) => {
  for (var i = chapter + 1; i <= total; i++) i,
};

class ComicChaptersView extends StatefulWidget {
  const ComicChaptersView({
    super.key,
    required this.chapters,
    this.readState,
    this.history,
    this.downloadedChapters,
    required this.readChapter,
    this.markChaptersRead,
    this.downloadChapters,
    this.deleteChapters,
    this.onSelectionChanged,
    this.selectionResetToken,
  });

  final ComicChapters chapters;

  /// Durable read marks. Preferred over [history], whose read set disappears
  /// with the history row; the fallback keeps older callers working.
  final ReadState? readState;

  /// Reading position only. Its `readEpisode` is ignored when [readState] is
  /// supplied.
  final History? history;

  /// Chapter ids stored on the device, so each row can show what is already
  /// available offline. Null means the caller has no library, and no badge is
  /// drawn rather than claiming every chapter is missing.
  final Set<String>? downloadedChapters;

  /// Downloads the selected chapters, one-based indices. Null leaves the
  /// selection bar without a download action.
  final void Function(Set<int> chapters)? downloadChapters;

  /// Deletes the stored pages of the selected chapters. Null leaves the
  /// selection bar without a delete action, which is the case for a caller that
  /// cannot reach the library.
  final void Function(Set<int> chapters)? deleteChapters;

  final void Function(int chapter) readChapter;

  /// Marks a batch of chapters read or unread, one-based indices. Null leaves
  /// the chapter list without selection mode, which is the case where the
  /// caller cannot persist history.
  final void Function(Set<int> chapters, bool read)? markChaptersRead;

  /// Reports whether a chapter selection is active, so the page can keep the
  /// back gesture from closing the whole comic while the user is picking rows.
  final ValueChanged<bool>? onSelectionChanged;

  /// Increments when the page wants selection mode to end, e.g. on back.
  final ValueListenable<int>? selectionResetToken;

  @override
  State<ComicChaptersView> createState() => _ComicChaptersViewState();
}

class _ComicChaptersViewState extends SettingsSaveState<ComicChaptersView> {
  bool? _preview;
  int _request = 0;

  bool get reverse {
    if (_preview != null) return _preview!;
    return GlobalPreferenceStore(
          appdata.settings,
        ).read(AppPreferences.chapterOrder) ==
        'descending';
  }

  @override
  void initState() {
    super.initState();
    appdata.settings.addListener(_refresh);
    _migrateLegacyReverse();
  }

  /// Folds the pre-choice "reverse" boolean into the choice, once.
  ///
  /// The old switch stored `reverseChapterOrder: true`, and reading it on every
  /// build made that stale flag outrank the new setting: choosing "Ascending"
  /// wrote `chapterOrder: ascending` and the page immediately recomputed
  /// descending again, so the control looked stuck. Translating it into the new
  /// key and dropping it lets the choice be the only authority.
  void _migrateLegacyReverse() {
    if (appdata.settings['reverseChapterOrder'] != true) return;
    unawaited(
      appdata
          .updateSettings((draft) {
            GlobalPreferenceStore(
              draft,
            ).write(AppPreferences.chapterOrder, 'descending');
            draft['reverseChapterOrder'] = null;
          })
          .catchError((Object error, StackTrace stack) {
            // A failed migration must not break the page; the legacy key stays
            // and the next visit retries.
            Log.error('Chapter order migration', error, stack);
          }),
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _setReverse(bool value) {
    if (!acceptsSettingsChanges || value == reverse) return;
    final request = ++_request;
    setState(() => _preview = value);
    saveSetting(
      AppPreferences.chapterOrder.key,
      () => appdata.updateSettings((draft) {
        GlobalPreferenceStore(draft).write(
          AppPreferences.chapterOrder,
          value ? 'descending' : 'ascending',
        );
      }),
      onSaved: () {
        if (request == _request) setState(() => _preview = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderControl = protectSettings(
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          settingsSaveStatus,
          _ChapterOrderSegment(reverse: reverse, onChanged: _setReverse),
        ],
      ),
    );
    return widget.chapters.isGrouped
        ? _GroupedComicChapters(
            chapters: widget.chapters,
            readState: widget.readState ?? widget.history,
            history: widget.history,
            downloadedChapters: widget.downloadedChapters,
            readChapter: widget.readChapter,
            reverse: reverse,
            orderControl: orderControl,
            markChaptersRead: widget.markChaptersRead,
            onSelectionChanged: widget.onSelectionChanged,
            selectionResetToken: widget.selectionResetToken,
          )
        : _NormalComicChapters(
            chapters: widget.chapters,
            readState: widget.readState ?? widget.history,
            history: widget.history,
            downloadedChapters: widget.downloadedChapters,
            readChapter: widget.readChapter,
            reverse: reverse,
            orderControl: orderControl,
            markChaptersRead: widget.markChaptersRead,
            downloadChapters: widget.downloadChapters,
            deleteChapters: widget.deleteChapters,
            onSelectionChanged: widget.onSelectionChanged,
            selectionResetToken: widget.selectionResetToken,
          );
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_refresh);
    super.dispose();
  }
}

class _NormalComicChapters extends StatefulWidget {
  const _NormalComicChapters({
    required this.chapters,
    this.readState,
    this.history,
    this.downloadedChapters,
    required this.readChapter,
    required this.reverse,
    required this.orderControl,
    this.markChaptersRead,
    this.downloadChapters,
    this.deleteChapters,
    this.onSelectionChanged,
    this.selectionResetToken,
  });

  final ComicChapters chapters;
  final bool reverse;
  final Widget orderControl;

  final ReadState? readState;

  final History? history;

  final Set<String>? downloadedChapters;

  final void Function(int chapter) readChapter;

  final void Function(Set<int> chapters, bool read)? markChaptersRead;

  final void Function(Set<int> chapters)? downloadChapters;

  final void Function(Set<int> chapters)? deleteChapters;

  final ValueChanged<bool>? onSelectionChanged;

  final ValueListenable<int>? selectionResetToken;

  @override
  State<_NormalComicChapters> createState() => _NormalComicChaptersState();
}

class _NormalComicChaptersState extends State<_NormalComicChapters> {
  bool showAll = false;

  /// Read marks this list renders as "visited".
  ReadState? get readState => widget.readState;

  /// Chapters picked for a batch read/unread change, by one-based index.
  ///
  /// Long press starts selection, which is how a reader catches up on chapters
  /// read elsewhere without opening each one.
  final _selected = <int>{};

  /// Whether the list is in selection mode.
  ///
  /// Deliberately separate from [_selected]: deselecting the last row used to
  /// drop the mode, so unticking everything kicked the user back to browsing.
  /// Only Cancel and a finished batch mark leave selection mode.
  bool _selecting = false;

  /// Chapter the current selection started from, used as the range pivot.
  int? _anchor;

  void _toggleSelected(int chapter) {
    setState(() {
      // The first chapter touched becomes the pivot for the range actions, so
      // "before/after" keeps meaning the chapter the reader started from even
      // after unticking it.
      if (!_selecting) _anchor = chapter;
      _selecting = true;
      if (!_selected.remove(chapter)) _selected.add(chapter);
    });
    _notifySelection();
  }

  /// Tells the page whether a selection is active so it can hold the back
  /// gesture; also reports the cleared state after a batch mark.
  void _notifySelection() => widget.onSelectionChanged?.call(_selecting);

  void _exitSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
      _anchor = null;
    });
    _notifySelection();
  }

  /// Whether anything currently ticked is stored on the device.
  ///
  /// Deleting is only meaningful for chapters that were actually downloaded, so
  /// the action stays disabled instead of reporting a no-op after the tap.
  bool get _hasDownloadedSelected {
    final downloaded = widget.downloadedChapters;
    if (downloaded == null || _selected.isEmpty) return false;
    for (final chapter in _selected) {
      if (widget.chapters.isChapterDownloaded(chapter, downloaded)) return true;
    }
    return false;
  }

  void _selectAll() {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll([for (var i = 1; i <= widget.chapters.length; i++) i]);
    });
  }

  /// Selects every chapter earlier than the pivot, in reading order.
  ///
  /// Mirrors the library's "mark previous as read": a reader who jumps into a
  /// long series wants to declare everything before it already read.
  void _selectBefore() {
    final at = _anchor;
    if (at == null) return;
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(chaptersBefore(at));
    });
  }

  /// Selects every chapter later than the pivot, in reading order.
  void _selectAfter() {
    final at = _anchor;
    if (at == null) return;
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addAll(chaptersAfter(at, widget.chapters.length));
    });
  }

  void _invertSelection() {
    setState(() {
      _selecting = true;
      final next = <int>{
        for (var i = 1; i <= widget.chapters.length; i++)
          if (!_selected.contains(i)) i,
      };
      _selected
        ..clear()
        ..addAll(next);
    });
  }

  void _applyMark(bool read) {
    final mark = widget.markChaptersRead;
    if (mark == null) return;
    final picked = Set<int>.of(_selected);
    _exitSelection();
    if (picked.isNotEmpty) mark(picked, read);
  }

  @override
  void initState() {
    super.initState();
    widget.selectionResetToken?.addListener(_onSelectionReset);
  }

  /// The page asks for selection to end, usually because back was pressed.
  void _onSelectionReset() {
    if (mounted && _selecting) _exitSelection();
  }

  @override
  void didUpdateWidget(covariant _NormalComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionResetToken != widget.selectionResetToken) {
      oldWidget.selectionResetToken?.removeListener(_onSelectionReset);
      widget.selectionResetToken?.addListener(_onSelectionReset);
    }
    // New marks arrive through the widget; nothing is copied into state.
  }

  @override
  void dispose() {
    widget.selectionResetToken?.removeListener(_onSelectionReset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        int length = chapters.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == chapters.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              // Selecting replaces the heading with the batch actions, the
              // same shape the library uses.
              child: _selecting
                  ? _ChapterSelectionBar(
                      count: _selected.length,
                      anchor: _anchor,
                      onCancel: _exitSelection,
                      onSelectAll: _selectAll,
                      onInvert: _invertSelection,
                      onSelectBefore: _anchor == null ? null : _selectBefore,
                      onSelectAfter: _anchor == null ? null : _selectAfter,
                      onMarkRead: () => _applyMark(true),
                      onMarkUnread: () => _applyMark(false),
                      onDownload: widget.downloadChapters == null
                          ? null
                          : () => widget.downloadChapters!(_selected),
                      // Disabled when nothing ticked is stored: there is nothing
                      // to delete, and a greyed entry explains that better than
                      // a tap that reports a no-op.
                      onDelete: widget.deleteChapters == null
                          ? null
                          : () => widget.deleteChapters!(_selected),
                      deleteEnabled: _hasDownloadedSelected,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Chapters".tl,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          widget.orderControl,
                        ],
                      ),
                    ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((context, i) {
                if (widget.reverse) {
                  i = chapters.length - i - 1;
                }
                var key = chapters.ids.elementAt(i);
                var value = chapters[key]!;
                bool visited =
                    readState != null &&
                    chapters.isChapterRead(i + 1, readState!);
                final downloaded = chapters.isChapterDownloaded(
                  i + 1,
                  widget.downloadedChapters,
                );
                final selected = _selected.contains(i + 1);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: selected
                        ? context.colorScheme.primaryContainer
                        : context.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: ClickInkWell(
                      // Tapping reads a chapter; in selection mode it picks one
                      // instead, so a batch mark does not start the reader.
                      onTap: _selecting
                          ? () => _toggleSelected(i + 1)
                          : () => widget.readChapter(i + 1),
                      onLongPress: widget.markChaptersRead == null
                          ? null
                          : () => _toggleSelected(i + 1),
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        children: [
                          if (_selecting)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: selected
                                    ? context.colorScheme.primary
                                    : context.colorScheme.outline,
                              ),
                            )
                          else
                            // Mirrors the badge and its trailing gap on the
                            // right, so a centered title stays in the middle.
                            const SizedBox(
                              width: _ChapterDownloadBadge._size + 8,
                            ),
                          Expanded(
                            child: Text(
                              value,
                              maxLines: 1,
                              textAlign: _selecting
                                  ? TextAlign.left
                                  : TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: visited
                                    ? context.colorScheme.outline
                                    : null,
                              ),
                            ),
                          ),
                          // Both sides keep the same width so a centered title
                          // does not shift when the badge appears.
                          _ChapterDownloadBadge(downloaded: downloaded),
                          if (!_selecting) const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                );
              }, childCount: length),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${chapters.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}

class _GroupedComicChapters extends StatefulWidget {
  const _GroupedComicChapters({
    required this.chapters,
    this.readState,
    this.history,
    this.downloadedChapters,
    required this.readChapter,
    required this.reverse,
    required this.orderControl,
    this.markChaptersRead,
    this.onSelectionChanged,
    this.selectionResetToken,
  });

  final ComicChapters chapters;
  final bool reverse;
  final Widget orderControl;

  final ReadState? readState;

  final History? history;

  final Set<String>? downloadedChapters;

  final void Function(int chapter) readChapter;

  final void Function(Set<int> chapters, bool read)? markChaptersRead;

  final ValueChanged<bool>? onSelectionChanged;

  final ValueListenable<int>? selectionResetToken;

  @override
  State<_GroupedComicChapters> createState() => _GroupedComicChaptersState();
}

class _GroupedComicChaptersState extends State<_GroupedComicChapters>
    with TickerProviderStateMixin {
  bool showAll = false;

  /// Read marks this list renders as "visited".
  ReadState? get readState => widget.readState;

  late TabController tabController;

  late int index;
  late List<String> _groups;

  @override
  void initState() {
    super.initState();
    _groups = widget.chapters.groups.toList();
    index = ((widget.history?.group ?? 1) - 1).clamp(
      0,
      math.max(0, _groups.length - 1),
    );
    _createTabs();
  }

  void _createTabs() {
    tabController = TabController(
      initialIndex: index,
      length: _groups.length,
      vsync: this,
    );
    tabController.addListener(onTabChange);
  }

  void onTabChange() {
    if (index != tabController.index) {
      setState(() {
        index = tabController.index;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GroupedComicChapters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final groups = widget.chapters.groups.toList();
    final previousGroup = _groups.elementAtOrNull(index);
    if (!listEquals(groups, _groups)) {
      tabController.removeListener(onTabChange);
      tabController.dispose();
      _groups = groups;
      index = math.max(0, groups.indexOf(previousGroup ?? ''));
      showAll = false;
      _createTabs();
    }
  }

  @override
  void dispose() {
    tabController.removeListener(onTabChange);
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    return SliverLayoutBuilder(
      builder: (context, constrains) {
        var group = _groups.isEmpty
            ? const <String, String>{}
            : chapters.getGroupByIndex(index);
        int length = group.length;
        bool canShowAll = showAll;
        if (!showAll) {
          var width = constrains.crossAxisExtent - 16;
          var crossItems = width ~/ 200;
          if (width % 200 != 0) {
            crossItems += 1;
          }
          length = math.min(length, crossItems * 8);
          if (length == group.length) {
            canShowAll = true;
          }
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "Chapters".tl,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    widget.orderControl,
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AppTabBar(
                withUnderLine: false,
                controller: tabController,
                tabs: chapters.groups.map((e) => Tab(text: e)).toList(),
              ),
            ),
            SliverPadding(padding: const EdgeInsets.only(top: 8)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((context, i) {
                if (widget.reverse) {
                  i = group.length - i - 1;
                }
                var key = group.keys.elementAt(i);
                var value = group[key]!;
                var chapterIndex = 0;
                for (var j = 0; j < chapters.groupCount; j++) {
                  if (j == index) {
                    chapterIndex += i;
                    break;
                  }
                  chapterIndex += chapters.getGroupByIndex(j).length;
                }
                // The shared check accepts both the grouped key and the plain
                // index, so a list that became grouped keeps its read marks.
                bool visited =
                    readState != null &&
                    chapters.isChapterRead(chapterIndex + 1, readState!);
                final downloaded = chapters.isChapterDownloaded(
                  chapterIndex + 1,
                  widget.downloadedChapters,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Material(
                    color: context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: ClickInkWell(
                      onTap: () => widget.readChapter(chapterIndex + 1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            // Mirrors the badge slot on the right, keeping the
                            // title centered whether or not it is drawn.
                            const SizedBox(width: _ChapterDownloadBadge._size),
                            Expanded(
                              child: Text(
                                value,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: visited
                                      ? context.colorScheme.outline
                                      : null,
                                ),
                              ),
                            ),
                            _ChapterDownloadBadge(downloaded: downloaded),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }, childCount: length),
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 250,
                itemHeight: 48,
              ),
            ).sliverPadding(const EdgeInsets.symmetric(horizontal: 8)),
            if (!canShowAll)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      setState(() {
                        showAll = true;
                      });
                    },
                    label: Text("${"Show all".tl} (${group.length})"),
                  ).paddingTop(12),
                ),
              ),
            const SliverToBoxAdapter(child: Divider()),
          ],
        );
      },
    );
  }
}

/// Batch actions shown while chapters are selected.
class _ChapterSelectionBar extends StatelessWidget {
  const _ChapterSelectionBar({
    required this.count,
    required this.anchor,
    required this.onCancel,
    required this.onSelectAll,
    required this.onInvert,
    required this.onSelectBefore,
    required this.onSelectAfter,
    required this.onMarkRead,
    required this.onMarkUnread,
    this.onDownload,
    this.onDelete,
    this.deleteEnabled = true,
  });

  final int count;

  /// Chapter the selection started from, used as the range pivot. Null means
  /// the range actions have nothing to be relative to.
  final int? anchor;

  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onInvert;
  final VoidCallback? onSelectBefore;
  final VoidCallback? onSelectAfter;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;

  /// Null when the caller has no library access, which leaves the action out
  /// rather than showing one that cannot work.
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  /// Whether the delete action can do anything for the current selection.
  ///
  /// Only a stored chapter can be deleted, so an all-undeleted selection greys
  /// the action out instead of letting the reader tap into a no-op.
  final bool deleteEnabled;

  @override
  Widget build(BuildContext context) {
    // Words instead of bare icons: three of these actions are not guessable
    // from a glyph, and tooltips are unreachable on touch.
    Widget action(String label, VoidCallback? onPressed) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: "Cancel".tl,
                icon: const Icon(Icons.close_rounded),
                onPressed: onCancel,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Selected @count".tlParams({"count": count}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    // Naming the pivot is what makes "before/after" mean
                    // something; without it the buttons are ambiguous.
                    if (anchor case final at?)
                      Text(
                        "Base chapter: @n".tlParams({"n": at}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Wrap so the labelled actions stay readable on a narrow screen.
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                action("Select All".tl, onSelectAll),
                action("Invert Selection".tl, onInvert),
                // Range selection, mirroring the library's "mark previous as
                // read": pick everything on one side of the pivot chapter.
                action("Chapters before".tl, onSelectBefore),
                action("Chapters after".tl, onSelectAfter),
                action("Mark as read".tl, count == 0 ? null : onMarkRead),
                action("Mark as unread".tl, count == 0 ? null : onMarkUnread),
                // Same shape as the library's batch actions: the download and
                // delete entries work on whatever is ticked, so the overflow
                // menu no longer has to carry a whole-comic download.
                if (onDownload != null)
                  action("Download".tl, count == 0 ? null : onDownload),
                if (onDelete != null)
                  action(
                    "Delete downloaded".tl,
                    count == 0 || !deleteEnabled ? null : onDelete,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a chapter whose pages are already stored on the device.
///
/// Reserves its width even when the chapter is not downloaded, so the chapter
/// titles stay aligned in a column instead of drifting per row.
///
/// Deliberately ignores pointers and carries no tooltip: a [Tooltip] shows on
/// long press by default, so it swallowed the long press that starts chapter
/// selection whenever the badge was touched. The row around it owns the tap and
/// long-press gestures.
class _ChapterDownloadBadge extends StatelessWidget {
  const _ChapterDownloadBadge({required this.downloaded});

  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    if (!downloaded) return const SizedBox(width: _size);
    return SizedBox(
      width: _size,
      // The label sits outside [IgnorePointer]: that widget drops its whole
      // subtree from the semantics tree, so a label inside it would never be
      // readable by an assistive client.
      child: Semantics(
        label: 'Downloaded'.tl,
        child: IgnorePointer(
          child: Icon(
            Icons.download_done_rounded,
            size: 16,
            color: context.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  static const double _size = 20;
}

class _ChapterOrderSegment extends StatelessWidget {
  const _ChapterOrderSegment({required this.reverse, required this.onChanged});

  final bool reverse;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "Order".tl,
      child: SegmentedButton<bool>(
        selected: {reverse},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        ),
        segments: [
          ButtonSegment<bool>(value: false, label: Text("Ascending".tl)),
          ButtonSegment<bool>(value: true, label: Text("Descending".tl)),
        ],
        onSelectionChanged: (selected) {
          onChanged(selected.first);
        },
      ),
    );
  }
}
