import 'dart:async';
import 'package:venera_next/components/settings_save_state.dart';

import 'package:venera_next/features/reader/status_info.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/features/reader/progress_bar.dart';
import 'package:venera_next/features/reader/bottom_actions.dart';
import 'package:venera_next/features/reader/top_bar.dart';
import 'package:venera_next/features/reader/sidebar_binding.dart';
import 'package:venera_next/features/reader/brightness.dart';
import 'package:venera_next/features/reader/chapter_navigation.dart';
import 'package:venera_next/features/reader/chapter_navigation_button.dart';
import 'package:venera_next/features/reader/gesture_port.dart';
import 'package:venera_next/features/reader/platform_effects_controller.dart';
import 'shell_data.dart';
import 'progress_navigation.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/reader/image_export.dart';
import 'package:venera_next/features/reader/image_export_binding.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/features/reader/settings_effects.dart';
import 'package:venera_next/features/reader/settings_panel.dart';
import 'package:venera_next/features/reader/image_selection.dart';
import 'package:venera_next/features/reader/image_picker.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/routing/settings.dart';

class ReaderScaffold extends StatefulWidget {
  const ReaderScaffold({
    super.key,
    required this.data,
    required this.progress,
    required this.onExit,
    required this.onFullscreen,
    required this.readImagePickContext,
    required this.imageWork,
    required this.orientation,
    required this.onRotate,
    required this.onSystemUiChanged,
    required this.createImageExport,
    required this.createSettings,
    required this.chapterNavigation,
    required this.child,
  });

  final ReaderShellData data;
  final ReaderProgressRequest progress;
  final Future<void> Function() onExit;
  final VoidCallback? onFullscreen;
  final ReaderImagePickContext? Function() readImagePickContext;
  final ImageWork imageWork;
  final ReaderOrientation orientation;
  final VoidCallback? onRotate;
  final void Function(bool menuOpen) onSystemUiChanged;
  final ReaderImageExportRequest? Function() createImageExport;
  final ReaderSettingsRequest? Function() createSettings;
  final ReaderChapterNavigationAction? chapterNavigation;
  final Widget child;

  @override
  State<ReaderScaffold> createState() => ReaderScaffoldState();
}

class ReaderScaffoldState extends State<ReaderScaffold> {
  var _brightnessPreview = ReaderBrightnessPreview();

  bool _isOpen = false;

  bool _brightnessPanelOpen = false;

  static const kTopBarHeight = 56.0;

  bool get isOpen => _isOpen;

  ReaderGesturePort? _gesturePort;
  ReaderGesturePort? get gestureDetectorState => _gesturePort;
  void onGesturePortChanged(ReaderGesturePort port, bool attached) {
    if (!attached && !identical(_gesturePort, port)) return;
    _gesturePort = attached ? port : null;
  }

  @override
  void initState() {
    super.initState();
    _brightnessPreview.addListener(update);
  }

  @override
  void dispose() {
    _brightnessPreview.dispose();
    _sidebarBinding.dispose();
    _gesturePort = null;
    unawaited(_exporter?.dispose());
    _imagePicker.dispose();
    _selectionOverlay.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReaderScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.comicId != widget.data.comicId ||
        oldWidget.data.sourceKey != widget.data.sourceKey ||
        !identical(oldWidget.imageWork, widget.imageWork)) {
      _replaceBrightnessPreview();
    }
    if (!identical(oldWidget.imageWork, widget.imageWork)) {
      unawaited(_exporter?.dispose());
      _exporter = null;
    }
  }

  void _replaceBrightnessPreview() {
    _sidebarBinding.close();
    _brightnessPreview.dispose();
    _brightnessPreview = ReaderBrightnessPreview()..addListener(update);
  }

  void _applySystemUiMode() {
    widget.onSystemUiChanged(_isOpen);
  }

  void openOrClose() {
    setState(() {
      _isOpen = !_isOpen;
      if (!_isOpen) {
        _brightnessPanelOpen = false;
      }
    });
    _applySystemUiMode();
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brightnessPanelVisible = _isOpen && _brightnessPanelOpen;
    final menuDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final scaler = MediaQuery.textScalerOf(context);
    final titleScale = [12.0, 16.0, 18.0]
        .map((size) => scaler.scale(size) / size)
        .fold(1.0, (largest, scale) => scale > largest ? scale : largest);
    final topBarHeight = kTopBarHeight * titleScale;
    return Stack(
      children: [
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: widget.data.animating,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: ReaderBrightnessOverlay(
            enabled:
                _brightnessPreview.enabled ??
                widget.data.preferences.readerBrightnessEnabled,
            brightness:
                _brightnessPreview.brightness ??
                widget.data.preferences.readerBrightness,
          ),
        ),
        _buildInformation(),
        ReaderChapterNavigationButton(action: widget.chapterNavigation),
        AnimatedPositioned(
          duration: menuDuration,
          top: _isOpen ? 0 : -(topBarHeight + context.padding.top),
          left: 0,
          right: 0,
          // Insets change immediately when the native/custom frame changes.
          // Keep content height in sync; animate only its entrance position.
          child: SizedBox(
            height: topBarHeight + context.padding.top,
            child: _menuRegion(visible: _isOpen, child: buildTop()),
          ),
        ),
        AnimatedPositioned(
          duration: menuDuration,
          bottom: _isOpen
              ? 0
              : -(ReaderBottomBar.height +
                    MediaQuery.of(context).padding.bottom),
          left: 0,
          right: 0,
          child: _menuRegion(visible: _isOpen, child: buildBottom()),
        ),
        AnimatedPositioned(
          duration: menuDuration,
          curve: Curves.easeOut,
          right: 16 + context.padding.right,
          bottom: brightnessPanelVisible
              ? ReaderBottomBar.height + context.padding.bottom + 12
              : -context.height,
          child: _menuRegion(
            visible: brightnessPanelVisible,
            child: buildBrightnessPanel(),
          ),
        ),
      ],
    );
  }

  Widget _menuRegion({required bool visible, required Widget child}) =>
      ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
      );

  Widget buildTop() => ReaderTopBar(
    title: widget.data.title,
    chapterTitle: widget.data.chapterTitle,
    onBack: () => unawaited(widget.onExit()),
    actions: [
      Tooltip(
        message: "Settings".tl,
        child: IconButton(
          icon: const Icon(Icons.settings),
          onPressed: openSetting,
        ),
      ),
    ],
  );

  Future<int?> _pickImage() async {
    final selection = await _imagePicker.pick();
    return selection != null &&
            selection.isCurrent(widget.readImagePickContext())
        ? selection.index
        : null;
  }

  Widget buildBottom() => _buildBottom();

  Widget _buildBottom() {
    // Use maxPage for display (excluding chapter comments page)
    final progress = widget.progress;
    final displayPage = progress.page.clamp(1, progress.maxPage);
    var text = "E${progress.chapter} : P$displayPage";
    if (!widget.data.hasChapters) {
      text = "P$displayPage";
    }
    String edgeLabel(int direction) {
      final target = progress.chapter + direction;
      if (target >= 1 && target <= progress.maxChapter) {
        return direction < 0 ? 'Previous chapter'.tl : 'Next chapter'.tl;
      }
      return 'Page @page'.tlParams({
        'page': direction < 0 ? '1' : '${progress.maxPage}',
      });
    }

    final buttons = buildReaderBottomActions(
      context,
      onFullscreen: widget.onFullscreen,
      orientation: widget.orientation,
      onRotate: widget.onRotate,
      brightnessEnabled:
          _brightnessPreview.enabled ??
          widget.data.preferences.readerBrightnessEnabled,
      onBrightness: () =>
          setState(() => _brightnessPanelOpen = !_brightnessPanelOpen),
      onSave: saveCurrentImage,
    );

    return ReaderBottomBar(
      label: text,
      actions: buttons,
      page: progress.page,
      maxPage: progress.maxPage,
      reversed: progress.reversed,
      isOpen: isOpen,
      progressIdentity: progress.identity,
      onPageChanged: progress.selectPage,
      onPrevious: progress.previous,
      onNext: progress.next,
      previousTooltip: edgeLabel(progress.reversed ? 1 : -1),
      nextTooltip: edgeLabel(progress.reversed ? -1 : 1),
    );
  }

  Widget buildBrightnessPanel() => SettingsSaveScope(
    work: widget.imageWork,
    child: ReaderBrightnessSetting(
      comicId: widget.data.comicId,
      sourceKey: widget.data.sourceKey,
      preview: _brightnessPreview,
      panel: true,
      onChanged: _onSettingChanged,
    ),
  );

  Widget _buildInformation() {
    final preferences = widget.data.preferences;
    final showPage = preferences.showPageNumberInReader;
    final showStatus = preferences.enableClockAndBatteryInfoInReader;
    if (!showPage && !showStatus) return const SizedBox.shrink();
    final progress = widget.progress;
    final padding = context.padding;
    return Positioned(
      bottom: 13 + padding.bottom,
      left: 25 + padding.left,
      right: 25 + padding.right,
      child: IgnorePointer(
        child: OverflowBar(
          alignment: showPage
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          spacing: 12,
          overflowSpacing: 4,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            if (showPage)
              ReaderPageInfo(
                page: progress.page,
                maxPage: progress.maxPage,
                chapterTitle: widget.data.hasChapters
                    ? widget.data.chapterTitle ?? 'E${progress.chapter}'
                    : null,
              ),
            if (showStatus)
              const ReaderStatusInfo(
                key: ValueKey('reader-status-information'),
              ),
          ],
        ),
      ),
    );
  }

  ReaderImageExportBinding? _exporter;
  ReaderImageExportBinding get _imageExporter =>
      _exporter ??= ReaderImageExportBinding(
        context: context,
        work: widget.imageWork,
        cancelSelection: _selectionOverlay.cancel,
        createRequest: () => widget.createImageExport(),
        pick: _pickImage,
      );

  void saveCurrentImage() => unawaited(_imageExporter.export());

  void openSetting() {
    final request = widget.createSettings();
    if (request == null || !request.isCurrent()) return;
    final work = widget.imageWork;
    bool isCurrent() =>
        mounted && identical(widget.imageWork, work) && request.isCurrent();
    setState(() {
      _brightnessPanelOpen = false;
    });
    _openSideBar(
      ReaderSettingsPanel(
        request: request,
        work: work,
        onChanged: (key) {
          if (isCurrent()) {
            request.apply(key, applyShellEffect: _applyShellEffect);
          }
        },
        brightnessPreview: _brightnessPreview,
      ),
      width: 400,
    );
  }

  void _onSettingChanged(String key) {
    if (!mounted) return;
    widget.createSettings()?.apply(key, applyShellEffect: _applyShellEffect);
  }

  void _applyShellEffect(ReaderSettingEffect effect) {
    if (!mounted) return;
    switch (effect) {
      case ReaderSettingEffect.rebindImageGesture:
        // The gesture detector re-reads its request on every shell change, so
        // a notification is enough to pick up the new binding. Without this
        // case the shared effect list throws and the setting is not applied.
        update();
      case ReaderSettingEffect.updateSystemUi:
        _applySystemUiMode();
      case ReaderSettingEffect.rebuildShell:
        update();
      default:
        throw ArgumentError.value(effect, 'effect', 'Not a shell effect');
    }
  }

  late final _sidebarBinding = ReaderSidebarBinding(
    canOpen: () => mounted,
    acquireInteraction: () {
      final gesture = gestureDetectorState;
      gesture?.ignoreNextTap();
      return () => gesture?.clearIgnoreNextTap();
    },
    onError: (error, stack) {
      Log.error('Reader', 'Failed to open sidebar: $error', stack);
      if (mounted) context.showMessage(message: error.toString());
    },
  );

  void _openSideBar(Widget widget, {double width = 400}) =>
      _sidebarBinding.show(context, widget, width: width);

  late final _imagePicker = ReaderImagePicker(
    current: () => mounted ? widget.readImagePickContext() : null,
    selectPosition: _showSelectImageOverlay,
  );

  final _selectionOverlay = ReaderImageSelectionOverlay();

  Future<Offset?> _showSelectImageOverlay() {
    if (_isOpen) openOrClose();
    return _selectionOverlay.show(context);
  }
}
