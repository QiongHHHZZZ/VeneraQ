import 'package:flutter/material.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/image_provider/cached_image.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({super.key});

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage> {
  DownloadTask? firstTask;

  late final LocalManager manager = LocalManager();

  @override
  void initState() {
    super.initState();
    manager.addListener(update);
    _syncFirstTask();
  }

  @override
  void dispose() {
    manager.removeListener(update);
    firstTask?.removeListener(update);
    super.dispose();
  }

  void _syncFirstTask() {
    final currentFirstTask = manager.downloadingTasks.firstOrNull;
    if (!identical(currentFirstTask, firstTask)) {
      firstTask?.removeListener(update);
      firstTask = currentFirstTask;
      firstTask?.addListener(update);
    }
  }

  void update() {
    _syncFirstTask();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "",
      body: ListView.builder(
        itemCount: manager.downloadingTasks.length + 1,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return buildTop();
          }
          i--;

          return _DownloadTaskTile(
            key: ValueKey(manager.downloadingTasks[i]),
            task: manager.downloadingTasks[i],
            manager: manager,
          );
        },
      ),
    );
  }

  Widget buildTop() {
    int speed = 0;
    if (manager.downloadingTasks.isNotEmpty) {
      speed = manager.downloadingTasks.first.speed;
    }
    var first = manager.downloadingTasks.firstOrNull;
    final resumePending = manager.isDownloadResumePending;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          if (first?.isPaused == true && !resumePending)
            Text("Paused".tl, style: ts.s18.bold)
          else if (first?.isError == true)
            Text("Error".tl, style: ts.s18.bold)
          else
            Text("${bytesToReadableString(speed)}/s", style: ts.s18.bold),
          const Spacer(),
          if (!resumePending &&
              (first?.isPaused == true || first?.isError == true))
            OutlinedButton(
              child: Row(
                children: [
                  const Icon(Icons.play_arrow, size: 18),
                  const SizedBox(width: 4),
                  Text("Start".tl),
                ],
              ),
              onPressed: () {
                manager.resumeDownload(first!);
              },
            )
          else if (first != null)
            OutlinedButton(
              child: Row(
                children: [
                  const Icon(Icons.pause, size: 18),
                  const SizedBox(width: 4),
                  Text("Pause".tl),
                ],
              ),
              onPressed: () {
                manager.pauseDownload(first);
              },
            ),
        ],
      ).paddingHorizontal(16),
    );
  }
}

class _DownloadTaskTile extends StatefulWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.manager,
    super.key,
  });

  final DownloadTask task;
  final LocalManager manager;

  @override
  State<_DownloadTaskTile> createState() => _DownloadTaskTileState();
}

class _DownloadTaskTileState extends State<_DownloadTaskTile> {
  late DownloadTask task;

  /// Whether this task shows its per-chapter breakdown. Collapsed by default so
  /// a long queue stays scannable.
  bool _expanded = false;

  @override
  void initState() {
    task = widget.task;
    task.addListener(update);
    super.initState();
  }

  @override
  void dispose() {
    task.removeListener(update);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DownloadTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.task, widget.task)) {
      task.removeListener(update);
      task = widget.task;
      task.addListener(update);
    }
  }

  void update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.task.chapterProgress;
    // A task with chapters expands into them; one without (an archive, or a
    // task that has not fetched its page list yet) stays a single row.
    final expandable = chapters.isNotEmpty;
    final height = expandable && _expanded ? null : 136.0;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: expandable && _expanded
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: [
          Row(
            children: [
              Container(
                width: 82,
                height: 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: context.colorScheme.primaryContainer,
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.task.cover == null
                    ? null
                    : Image(
                        image: CachedImageProvider(widget.task.cover!),
                        filterQuality: FilterQuality.medium,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tapping the title row expands the chapter breakdown, which
                    // is where the per-chapter page counts live.
                    InkWell(
                      onTap: expandable
                          ? () => setState(() => _expanded = !_expanded)
                          : null,
                      child: Row(
                        children: [
                          if (expandable)
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          Expanded(
                            child: Text(
                              widget.task.title,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // The page count sits on the title row and stays
                          // visible in every state, so a paused or failed task
                          // still says how far it got.
                          const SizedBox(width: 8),
                          Text(
                            widget.task.progressLabel,
                            style: ts.s12.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The message explains what the task is doing now (fetching
                    // info, resuming); the count above already covers progress,
                    // so this line never hides it.
                    Text(
                      widget.task.message,
                      style: ts.s12,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: widget.task.progress),
                  ],
                ),
              ),
              MenuButton(
                entries: [
                  MenuEntry(
                    icon: Icons.close,
                    text: "Cancel".tl,
                    onClick: () {
                      widget.manager.cancelDownload(widget.task);
                    },
                  ),
                  MenuEntry(
                    icon: Icons.vertical_align_top,
                    text: "Move To First".tl,
                    onClick: () {
                      widget.manager.moveToFirst(widget.task);
                    },
                  ),
                ],
              ),
            ],
          ),
          if (expandable && _expanded) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: context.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            for (final chapter in chapters) _chapterRow(context, chapter),
          ],
        ],
      ),
    );
  }

  /// One chapter inside the expanded task: its own page count and progress.
  Widget _chapterRow(BuildContext context, DownloadChapterProgress chapter) {
    final color = chapter.active
        ? context.colorScheme.primary
        : context.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 94, right: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chapter.title,
              style: ts.s12.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${chapter.downloaded}/${chapter.total}",
            style: ts.s12.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
