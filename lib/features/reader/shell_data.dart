import 'package:venera_next/foundation/reader_settings.dart';

/// Immutable presentation input. No widget, viewport or live reader lookup.
class ReaderShellData {
  const ReaderShellData({
    required this.comicId,
    required this.sourceKey,
    required this.title,
    required this.chapterTitle,
    required this.hasChapters,
    required this.vertical,
    required this.gallery,
    required this.animating,
    required this.preferences,
  });
  final String comicId, sourceKey, title;
  final String? chapterTitle;
  final bool hasChapters, vertical, gallery, animating;
  final ReaderSettings preferences;
}
