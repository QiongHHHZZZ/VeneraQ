import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/log_file_writer.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('log-writer-'),
  );
  tearDown(() async => await root.delete(recursive: true));

  test(
    'concurrent additions retain order and append to an existing file',
    () async {
      final file = File('${root.path}/logs.txt');
      await file.writeAsString('previous session\n');
      final writer = LogFileWriter(file);
      writer.add('first\n');
      final flushing = writer.flush();
      for (var i = 0; i < 100; i++) {
        writer.add('record $i\n');
      }
      await flushing;
      await writer.flush();
      expect(await file.readAsLines(), [
        'previous session',
        'first',
        for (var i = 0; i < 100; i++) 'record $i',
      ]);
      await file.rename('${root.path}/closed.txt');
    },
  );

  test(
    'rotation counts UTF-8 bytes and keeps only the previous file',
    () async {
      final file = File('${root.path}/logs.txt');
      final writer = LogFileWriter(file, maxFileBytes: 40);
      writer.add('第一条日志记录\n');
      await writer.flush();
      final first = await file.readAsString();
      writer.add('第二条日志记录\n');
      await writer.flush();
      expect(await writer.previousFile.readAsString(), first);
      final second = await file.readAsString();
      writer.add('第三条日志记录\n');
      await writer.flush();
      expect(await writer.previousFile.readAsString(), second);
      expect(await file.readAsString(), '第三条日志记录\n');
      expect(await root.list().length, 2);
    },
  );

  test(
    'failed writes retain a bounded queue and recover on the next flush',
    () async {
      final blocker = File('${root.path}/blocked');
      await blocker.writeAsString('not a directory');
      final errors = <Object>[];
      final writer = LogFileWriter(
        File('${blocker.path}/logs.txt'),
        maxPendingRecords: 3,
        onError: (error, stack) => errors.add(error),
      );
      for (var i = 0; i < 5; i++) {
        writer.add('pending $i\n');
      }
      await writer.flush();
      expect(errors, hasLength(1));
      await blocker.delete();
      await writer.flush();
      expect(
        await writer.file.readAsString(),
        'pending 2\npending 3\npending 4\n',
      );
    },
  );
}
