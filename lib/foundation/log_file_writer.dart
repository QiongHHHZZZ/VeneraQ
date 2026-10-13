import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Appends ordered batches without retaining an open sink between writes.
class LogFileWriter {
  LogFileWriter(
    this.file, {
    this.maxFileBytes = 2 * 1024 * 1024,
    this.maxPendingRecords = 500,
    this.onError,
  }) : assert(maxFileBytes > 0),
       assert(maxPendingRecords > 0);

  final File file;
  final int maxFileBytes;
  final int maxPendingRecords;
  final void Function(Object, StackTrace)? onError;
  final Queue<Uint8List> _pending = Queue();
  Future<void>? _writing;

  File get previousFile =>
      File('${file.parent.path}${Platform.pathSeparator}logs.previous.txt');

  void add(String record) {
    _pending.add(utf8.encode(record));
    _trimPending();
    _start();
  }

  void _trimPending() {
    while (_pending.length > maxPendingRecords) {
      _pending.removeFirst();
    }
  }

  void _start() {
    if (_writing != null || _pending.isEmpty) return;
    final complete = Completer<void>();
    _writing = complete.future;
    unawaited(() async {
      try {
        await _drain();
      } catch (error, stack) {
        // Diagnostics must not create an unhandled I/O failure or recursively
        // log another record to the same unavailable destination.
        onError?.call(error, stack);
      } finally {
        _writing = null;
        complete.complete();
      }
    }());
  }

  Future<void> flush() async {
    _start();
    while (_writing != null) {
      await _writing;
    }
  }

  Future<void> _drain() async {
    await file.parent.create(recursive: true);
    while (_pending.isNotEmpty) {
      final records = <Uint8List>[];
      var bytes = 0;
      final batchLimit = maxFileBytes < 64 * 1024 ? maxFileBytes : 64 * 1024;
      do {
        final record = _pending.removeFirst();
        records.add(record);
        bytes += record.length;
      } while (_pending.isNotEmpty &&
          bytes + _pending.first.length <= batchLimit);
      try {
        final size = await file.exists() ? await file.length() : 0;
        if (size > 0 && size + bytes > maxFileBytes) {
          if (await previousFile.exists()) await previousFile.delete();
          await file.rename(previousFile.path);
        }
        final builder = BytesBuilder(copy: false);
        for (final record in records) {
          builder.add(record);
        }
        await file.writeAsBytes(
          builder.takeBytes(),
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        for (final record in records.reversed) {
          _pending.addFirst(record);
        }
        _trimPending();
        rethrow;
      }
    }
  }
}
