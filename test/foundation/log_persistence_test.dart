import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'session replays early logs and persists all levels across restarts',
    () async {
      final root = await Directory.systemTemp.createTemp('log-session-');
      final file = File('${root.path}/logs.txt');
      final muted = Log.isMuted;
      Log.isMuted = false;
      Log.clear();
      Future<void> Function()? close;
      try {
        await file.writeAsString('previous run\n');
        Log.info('startup', 'early information');
        close = await Log.startFileSession(file);
        Log.info('source', 'extension information');
        Log.warning('source', 'warning text');
        Log.error('reader', 'error text', 'stack text');
        await close();
        close = null;
        var text = await file.readAsString();
        expect(text, startsWith('previous run\n'));
        expect(text, contains('early information'));
        expect(text, contains('extension information'));
        expect(text, contains('warning text'));
        expect(text, contains('error text\nstack text'));
        close = await Log.startFileSession(file);
        Log.info('startup', 'second session');
        await close();
        close = null;
        text = await file.readAsString();
        expect('early information'.allMatches(text), hasLength(1));
        expect(text, contains('second session'));
        expect(Log.filePath, isNull);
      } finally {
        await close?.call();
        Log.isMuted = muted;
        Log.clear();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'late close retains the original file and preserves a replacement owner',
    () async {
      final root = await Directory.systemTemp.createTemp('log-owners-');
      final oldFile = File('${root.path}/old/logs.txt');
      final newFile = File('${root.path}/new/logs.txt');
      final muted = Log.isMuted;
      Log.isMuted = false;
      Log.clear();
      final oldClose = await Log.startFileSession(oldFile);
      Log.info('old', 'old destination');
      final newClose = await Log.startFileSession(newFile);
      try {
        await oldClose();
        Log.info('new', 'new destination');
        await Log.flush();
        expect(Log.filePath, newFile.path);
        expect(await oldFile.readAsString(), contains('old destination'));
        expect(
          await oldFile.readAsString(),
          isNot(contains('new destination')),
        );
        expect(await newFile.readAsString(), contains('new destination'));
      } finally {
        await oldClose();
        await newClose();
        Log.isMuted = muted;
        Log.clear();
        await root.delete(recursive: true);
      }
    },
  );
}
