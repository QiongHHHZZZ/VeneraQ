/// Immutable storage address of a displayed image. It is independent of the
/// reader's current chapter and of its display/processing page number.
class ReaderImageAddress {
  const ReaderImageAddress({
    required this.imageKey,
    required this.sourceKey,
    required this.comicId,
    required this.chapterId,
  });
  final String imageKey;
  final String? sourceKey;
  final String comicId;
  final String chapterId;

  String get cacheKey => '$imageKey@$sourceKey@$comicId@$chapterId';
}

/// A source image, independent of grouped display pages and viewport offsets.
/// Chapter and image numbers are one-based; chapter ID is the source identity.
class ReaderImagePosition {
  const ReaderImagePosition({
    required this.chapter,
    required this.chapterId,
    required this.imageNumber,
  });

  final int chapter;
  final String chapterId;
  final int imageNumber;
}
