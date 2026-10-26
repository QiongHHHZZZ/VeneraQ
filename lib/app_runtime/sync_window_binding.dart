import 'package:flutter/widgets.dart';
import 'package:venera_next/components/window_frame.dart';
import 'package:venera_next/features/follow_updates/follow_updates_manager.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_import_lifecycle.dart';

/// Window-close behavior exists only while the interactive window is mounted.
class SyncWindowBinding extends StatefulWidget {
  const SyncWindowBinding({
    required this.child,
    required this.waitForHistoryWrites,
    this.isFinalizing,
    this.prepareInteractive,
    this.prepareDownloads,
    this.prepareImages,
    this.prepareImports,
    this.cancelStartupUpdates,
    this.closeStartupUpdates,
    super.key,
  });
  final Future<VoidCallback> Function()? prepareInteractive;
  final Future<VoidCallback> Function()? prepareDownloads;
  final Future<VoidCallback> Function()? prepareImages;
  final Future<VoidCallback> Function()? prepareImports;
  final VoidCallback? cancelStartupUpdates;
  final Future<void> Function()? closeStartupUpdates;
  final Widget child;
  final Future<void> Function() waitForHistoryWrites;
  final bool Function()? isFinalizing;

  @override
  State<SyncWindowBinding> createState() => _SyncWindowBindingState();
}

class _SyncWindowBindingState extends State<SyncWindowBinding> {
  WindowFrameController? _window;
  VoidCallback? _releaseInteractive;
  VoidCallback? _releaseFollowUpdates;
  VoidCallback? _releaseDownloads;
  VoidCallback? _releaseImages;
  VoidCallback? _releaseImports;
  bool _preparing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = WindowFrame.of(context);
    if (identical(window, _window)) return;
    _window?.removeExitTask(_waitThenClose);
    _window?.removeCloseFailureListener(_releasePreparedWork);
    _window?.removeCloseStartListener(_cancelStartupUpdates);
    _window = window;
    window.addExitTask(_waitThenClose);
    window.addCloseFailureListener(_releasePreparedWork);
    window.addCloseStartListener(_cancelStartupUpdates);
    if (window.isClosing) _cancelStartupUpdates();
  }

  void _cancelStartupUpdates() => widget.cancelStartupUpdates?.call();

  Future<void> _waitThenClose() async {
    final waitForHistoryWrites = widget.waitForHistoryWrites;
    _preparing = true;
    try {
      await widget.closeStartupUpdates?.call();
      if (!mounted) return;
      final prepareInteractive = widget.prepareInteractive;
      if (prepareInteractive != null) {
        _releaseInteractive = await prepareInteractive();
        if (!mounted) return;
      }
      _releaseFollowUpdates = await FollowUpdateJob.prepareForExit();
      if (!mounted) return;
      _releaseImports =
          await (widget.prepareImports ?? prepareLocalImportsForExit)();
      if (!mounted) return;
      _releaseDownloads =
          await (widget.prepareDownloads ??
              LocalManager.prepareDownloadsForExit)();
      if (!mounted) return;
      final prepareImages = widget.prepareImages;
      if (prepareImages != null) {
        _releaseImages = await prepareImages();
        if (!mounted) return;
      }
      await waitForHistoryWrites();
    } catch (_) {
      _releasePreparedWork();
      rethrow;
    } finally {
      _preparing = false;
      if (!mounted) _releasePreparedWork();
    }
  }

  void _releasePreparedWork() {
    if (widget.isFinalizing?.call() == true) return;
    final images = _releaseImages;
    _releaseImages = null;
    final downloads = _releaseDownloads;
    final imports = _releaseImports;
    final followUpdates = _releaseFollowUpdates;
    final interactive = _releaseInteractive;
    _releaseDownloads = null;
    _releaseImports = null;
    _releaseFollowUpdates = null;
    _releaseInteractive = null;
    try {
      images?.call();
    } finally {
      try {
        downloads?.call();
      } finally {
        try {
          imports?.call();
        } finally {
          try {
            followUpdates?.call();
          } finally {
            interactive?.call();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _window?.removeCloseStartListener(_cancelStartupUpdates);
    _window?.removeExitTask(_waitThenClose);
    _window?.removeCloseFailureListener(_releasePreparedWork);
    try {
      // A pending hold must finish before earlier owners resume producing work.
      // The preparation finally releases all holds after detachment.
      if (!_preparing) _releasePreparedWork();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
