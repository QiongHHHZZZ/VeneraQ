import 'package:flutter/material.dart';
import 'package:venera_next/foundation/app.dart';
import 'reader_page.dart';
import 'scaffold.dart';
import 'shell_data.dart';

/// Widget composition is the only shell layer that knows the reader State.
/// Page reports rebuild the shell while retaining the content subtree.
class ReaderShellHost extends StatelessWidget {
  const ReaderShellHost({super.key, required this.reader, required this.child});
  final ReaderState reader;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: reader.shellChanges,
    child: child,
    builder: (context, child) => ReaderScaffold(
      data: ReaderShellData(
        comicId: reader.cid,
        sourceKey: reader.type.sourceKey,
        title: reader.widget.name,
        chapterTitle: reader.widget.chapters?.titles.elementAtOrNull(
          reader.chapter - 1,
        ),
        hasChapters: reader.widget.chapters != null,
        vertical: reader.mode.isTopToBottom,
        gallery: reader.mode.isGallery,
        animating: reader.isPageAnimating,
        preferences: reader.preferences,
      ),
      progress: reader.createProgressRequest(),
      onExit: reader.requestExit,
      onFullscreen: App.isDesktop ? reader.fullscreen : null,
      readImagePickContext: reader.readImagePickContext,
      chapterNavigation: reader.chapterNavigation.action,
      imageWork: reader.imageWork,
      orientation: reader.readerOrientation,
      onRotate: App.isAndroid ? reader.cycleReaderOrientation : null,
      onSystemUiChanged: reader.updateSystemUi,
      createImageExport: reader.createImageExportRequest,
      createSettings: reader.createSettingsRequest,
      child: child!,
    ),
  );
}
