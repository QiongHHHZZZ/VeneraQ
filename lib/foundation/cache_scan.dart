import 'dart:isolate';
import 'dart:io';
import 'sqlite_connection.dart';

class CacheScanResult {
  const CacheScanResult(this.totalSize, this.unmanagedFiles);
  final int totalSize;
  final List<String> unmanagedFiles;
}

typedef CacheScanner =
    Future<CacheScanResult> Function(String dbPath, String directory);

Future<CacheScanResult> scanCacheDirectory(String dbPath, String dir) async {
  return Isolate.run(() async {
    var totalSize = 0;
    final unmanagedFiles = <String>[];
    final db = openSqliteDatabase(dbPath);
    try {
      // One query, not one per file. A large cache holds thousands of files and
      // this scan sits in front of every cache lookup during startup, so the
      // per-file SELECT was the dominant cost of opening the app.
      final managed = <String>{
        for (final row in db.select('SELECT dir, name FROM cache;'))
          '${row['dir']}/${row['name']}',
      };
      await for (final file in Directory(dir).list(recursive: true)) {
        if (file is! File) continue;
        final segments = file.uri.pathSegments;
        final name = segments.last;
        final parent = segments.elementAtOrNull(segments.length - 2) ?? '*';
        if (managed.contains('$parent/$name')) {
          totalSize += await file.length();
        } else {
          unmanagedFiles.add(file.path);
        }
      }
    } finally {
      db.dispose();
    }
    return CacheScanResult(totalSize, unmanagedFiles);
  });
}
