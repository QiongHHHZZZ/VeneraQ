import 'dart:convert';

import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/log.dart';

import 'github_source_search.dart';

/// The last completed discovery sweep, so reopening the screen is instant.
///
/// A sweep reaches hundreds of repositories and costs a minute or two, dominated
/// by catalog reads that each take 0.5-4 seconds. Repeating that on every visit
/// would make the screen feel broken, so the previous answer is handed back
/// immediately and refreshed in the background.
///
/// The cache is deliberately short-lived: a stale catalog is worse than a slow
/// one, because the sources in it change and break without notice.
class GitHubDiscoveryCache {
  const GitHubDiscoveryCache._();

  static const fileName = 'github_discovery.json';

  /// How long a cached sweep is reused without asking GitHub again.
  static const maxAge = Duration(days: 1);

  static File _file() =>
      File(FilePath.join(App.cachePath, 'source_discovery', fileName));

  /// A cached sweep, or null when it is missing, unreadable or too old.
  static Future<List<VerifiedSourceRepository>?> read() async {
    try {
      final file = _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final savedAt = decoded['savedAt'];
      final items = decoded['repositories'];
      if (savedAt is! int || items is! List) return null;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
      if (age > maxAge) return null;
      final repositories = <VerifiedSourceRepository>[];
      for (final item in items) {
        final parsed = VerifiedSourceRepository.fromJson(item);
        if (parsed != null) repositories.add(parsed);
      }
      // An empty list is not a usable answer: a sweep that found nothing is more
      // likely a failed run than a network with no source repositories.
      return repositories.isEmpty ? null : repositories;
    } catch (error, stack) {
      Log.error('Source discovery cache', error, stack);
      return null;
    }
  }

  /// When the cached sweep was taken, for the "refreshed just now" line.
  static Future<DateTime?> savedAt() async {
    try {
      final file = _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final savedAt = decoded['savedAt'];
      return savedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(savedAt)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Replaces the cached sweep. Best effort: a cache that cannot be written must
  /// not fail the search that produced it.
  static Future<void> write(List<VerifiedSourceRepository> repositories) async {
    try {
      final file = _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'repositories': [
            for (final repository in repositories) repository.toJson(),
          ],
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (error, stack) {
      Log.error('Source discovery cache', error, stack);
    }
  }

  /// Drops the cache, so the next visit searches again.
  static Future<void> clear() async {
    try {
      final file = _file();
      if (await file.exists()) await file.delete();
    } catch (error, stack) {
      Log.error('Source discovery cache', error, stack);
    }
  }
}
