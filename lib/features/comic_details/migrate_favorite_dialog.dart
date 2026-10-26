import 'package:flutter/material.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/image_provider/cached_image.dart';
import 'package:venera_next/foundation/translations.dart';

/// Similarity above which a record is treated as the match for this comic.
///
/// Mihon uses 0.4 to keep a search hit at all; showing one result as *the*
/// answer needs more confidence than that, so the bar here is higher.
const _kAutoMatchThreshold = 0.6;

/// Shortest title that may be treated as a substring match. Below this a shared
/// fragment says nothing — a two-character word appears inside many titles.
const _kMinContainmentLength = 4;

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

final _cjkChar = RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]');

/// Whether [shorter] is specific enough to count as contained in a longer title.
///
/// Four CJK characters name a series, but four Latin characters are usually one
/// short word, which would otherwise match every title starting with it. A
/// spaced Latin phrase is accepted at the same length.
bool _isSpecificEnough(String shorter) {
  if (shorter.length < _kMinContainmentLength) return false;
  if (_cjkChar.allMatches(shorter).length >= _kMinContainmentLength) return true;
  return shorter.contains(' ');
}

/// Comparable form of a title: case-folded, punctuation dropped, spaces
/// collapsed. Keeping letters and digits means CJK titles survive intact.
String normalizeTitle(String value) {
  final lowered = value.toLowerCase();
  final buffer = StringBuffer();
  var lastWasSpace = false;
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    if (_wordChar.hasMatch(char)) {
      buffer.write(char);
      lastWasSpace = false;
    } else if (!lastWasSpace && buffer.isNotEmpty) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }
  return buffer.toString().trim();
}

/// Normalized Levenshtein similarity in 0..1, where 1 means identical.
///
/// One title containing the other counts as a strong match, because a source
/// often appends a volume or season marker that the edit distance alone would
/// punish.
double titleSimilarity(String a, String b) {
  final x = normalizeTitle(a);
  final y = normalizeTitle(b);
  if (x.isEmpty && y.isEmpty) return 1;
  if (x.isEmpty || y.isEmpty) return 0;
  final shorter = x.length <= y.length ? x : y;
  final longer = x.length <= y.length ? y : x;
  if (_isSpecificEnough(shorter) && longer.contains(shorter)) {
    return 0.85;
  }
  return 1 - _levenshtein(x, y) / longer.length;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      current[j] = deletion < insertion
          ? (deletion < substitution ? deletion : substitution)
          : (insertion < substitution ? insertion : substitution);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// A favorite the reader can migrate onto the open comic.
class MigrateCandidate {
  const MigrateCandidate({
    required this.id,
    required this.sourceKey,
    required this.sourceName,
    required this.title,
    required this.type,
    this.author,
    this.cover,
    this.score = 0,
  });

  final String id;
  final String sourceKey;
  final String sourceName;
  final String title;
  final ComicType type;
  final String? author;
  final String? cover;

  /// Title similarity to the open comic, 0..1.
  final double score;

  /// Identity used to compare candidates, since ids collide across sources.
  String get ref => '$sourceKey/$id';
}

/// Lists the local favorites and returns the one to migrate onto this comic.
///
/// The current comic is excluded: migrating an entry onto itself is meaningless.
Future<MigrateCandidate?> showMigrateFavoriteDialog(
  BuildContext context, {
  required String currentId,
  required String currentSourceKey,
  required String currentTitle,
}) {
  return showDialog<MigrateCandidate>(
    context: context,
    builder: (context) => _MigrateFavoriteDialog(
      currentId: currentId,
      currentSourceKey: currentSourceKey,
      currentTitle: currentTitle,
    ),
  );
}

class _MigrateFavoriteDialog extends StatefulWidget {
  const _MigrateFavoriteDialog({
    required this.currentId,
    required this.currentSourceKey,
    required this.currentTitle,
  });

  final String currentId;
  final String currentSourceKey;
  final String currentTitle;

  @override
  State<_MigrateFavoriteDialog> createState() => _MigrateFavoriteDialogState();
}

class _MigrateFavoriteDialogState extends State<_MigrateFavoriteDialog> {
  late List<MigrateCandidate> _all;

  /// Set once the reader asks to see everything despite a match.
  bool _browsing = false;

  @override
  void initState() {
    super.initState();
    _all = _load();
  }

  /// Every stored record, scored against the open comic and ordered by that
  /// score so the likely match comes first.
  List<MigrateCandidate> _load() {
    final manager = FavoritesScope.read(context);
    final seen = <String>{};
    final items = <MigrateCandidate>[];
    for (final favorite in manager.getAllComics()) {
      // A comic can be filed in several folders; list it once.
      final key = '${favorite.sourceKey}/${favorite.id}';
      if (!seen.add(key)) continue;
      if (favorite.id == widget.currentId &&
          favorite.sourceKey == widget.currentSourceKey) {
        continue;
      }
      items.add(
        MigrateCandidate(
          id: favorite.id,
          sourceKey: favorite.sourceKey,
          sourceName:
              ComicSource.find(favorite.sourceKey)?.name ?? favorite.sourceKey,
          title: favorite.title,
          type: favorite.type,
          author: favorite.author.isEmpty ? null : favorite.author,
          cover: favorite.cover,
          score: titleSimilarity(widget.currentTitle, favorite.title),
        ),
      );
    }
    items.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return items;
  }

  /// The record that matches this comic, when one is convincing enough.
  MigrateCandidate? get _match {
    if (_all.isEmpty) return null;
    final best = _all.first;
    return best.score >= _kAutoMatchThreshold ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final showGrid = match == null || _browsing;
    return ContentDialog(
      title: 'Migrate'.tl,
      showClose: false,
      content: SizedBox(
        width: 420,
        height: showGrid ? 420 : null,
        child: showGrid ? _buildGrid() : _buildMatch(match),
      ),
    );
  }

  /// The matched record on its own: nothing to choose, so nothing else is shown.
  Widget _buildMatch(MigrateCandidate item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        _cover(item, width: 120, height: 162, marked: true),
        const SizedBox(height: 12),
        Text(
          item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          item.author == null
              ? item.sourceName
              : '${item.sourceName} · ${item.author}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(item),
            child: Text('Migrate'.tl),
          ),
        ),
        const SizedBox(height: 4),
        // The escape hatch, kept quiet: the match is usually right.
        TextButton(
          onPressed: () => setState(() => _browsing = true),
          child: Text('Choose another favorite'.tl),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    if (_all.isEmpty) return Center(child: Text('No favorites'.tl));
    final best = _match;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Smaller tiles than the shelf: this is a picker, and more rows visible
        // at once means less scrolling.
        final columns = (constraints.maxWidth / 86).floor().clamp(4, 8);
        return GridView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.62,
          ),
          itemCount: _all.length,
          itemBuilder: (context, index) {
            final item = _all[index];
            final isBest = best != null && item.ref == best.ref;
            return GestureDetector(
              onTap: () => Navigator.of(context).pop(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: _cover(item, expand: true, marked: isBest),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _cover(
    MigrateCandidate item, {
    double? width,
    double? height,
    bool expand = false,
    bool marked = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final cover = item.cover;
    final placeholder = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: colors.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined, size: 20),
    );
    Widget image;
    if (cover == null || cover.isEmpty) {
      image = expand
          ? ClipRRect(borderRadius: BorderRadius.circular(8), child: placeholder)
          : placeholder;
    } else {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: CachedImageProvider(
            cover,
            sourceKey: item.sourceKey,
            cid: item.id,
          ),
          fit: BoxFit.cover,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }
    if (!marked) return image;
    // A ring around the cover marks the match without repeating the entry.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary, width: 2),
      ),
      child: image,
    );
  }
}
