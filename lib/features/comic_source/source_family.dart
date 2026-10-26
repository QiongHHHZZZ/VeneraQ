import 'parser.dart' show compareSemVer;

import 'source_repositories.dart' show SourceCatalogEntry;

/// Three numeric parts, optionally followed by a suffix.
///
/// This is the shape [SourceRepositories.parseCatalog] accepts, so a catalog
/// entry always matches it; a source installed from a file or a link may not.
final _semver = RegExp(r'^\d+\.\d+\.\d+(?:[.\-].+)?$');

/// Newest version first.
///
/// [compareSemVer] parses three numeric parts and throws on anything else, and
/// an installed source's version is not guaranteed to be one of those. Versions
/// that do not look like a version fall back to a string comparison instead of
/// taking a page down.
int compareSourceVersions(String a, String b) {
  if (_semver.hasMatch(a) && _semver.hasMatch(b)) {
    if (compareSemVer(a, b)) return -1;
    if (compareSemVer(b, a)) return 1;
    return 0;
  }
  return b.compareTo(a);
}

/// One place a source key was found, with the version that place publishes.
///
/// [origin] is whatever the caller needs to act on the copy — a configured
/// repository for the overview page, a verified GitHub repository for discovery.
/// [entry] is the catalog record itself, so a caller can install or replace with
/// exactly the copy it is showing.
class SourceFamilyEntry<T> {
  const SourceFamilyEntry({
    required this.source,
    required this.name,
    required this.version,
    required this.entry,
    required this.origin,
  });

  /// Where this copy lives, already displayable ("Repo A").
  final String source;

  /// The name this copy spells the source as.
  final String name;

  final String version;

  /// The catalog record to install; [entryUrl] is its address.
  final SourceCatalogEntry entry;

  final T origin;
}

/// Every copy of one source key, wherever it was found.
///
/// The key is the app's source identity, so it is also the only safe thing to
/// group by. Grouping by display name instead would merge sources that merely
/// share a name, and grouping by neither is what leaves a list showing the same
/// source forty times.
class SourceFamily<T> {
  SourceFamily(this.key);

  final String key;
  final List<SourceFamilyEntry<T>> entries = [];

  bool get isDuplicated => entries.length > 1;

  /// The name most sources agree on. Sources rename each other, so the majority
  /// spelling is the least surprising one.
  String get name {
    final counts = <String, int>{};
    for (final entry in entries) {
      counts[entry.name] = (counts[entry.name] ?? 0) + 1;
    }
    var best = entries.first.name;
    var bestCount = 0;
    counts.forEach((candidate, count) {
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    });
    return best;
  }

  int get versionCount => entries.map((entry) => entry.version).toSet().length;

  bool get hasVersionConflict => versionCount > 1;

  List<String> get versions {
    final versions = entries.map((entry) => entry.version).toSet().toList();
    versions.sort(compareSourceVersions);
    return versions;
  }

  /// Newest first, so [recommended] is the copy to try first if the version
  /// number were the whole truth. It is not: the same key is often a different
  /// fix in every place that carries it, which is why every copy is shown
  /// instead of silently keeping one.
  void sortEntries() =>
      entries.sort((a, b) => compareSourceVersions(a.version, b.version));

  SourceFamilyEntry<T> get recommended => entries.first;
}
