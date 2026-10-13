import 'package:flutter/foundation.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/extensions.dart';
import 'log_file_writer.dart';

class LogItem {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time = DateTime.now();

  @override
  toString() => "${level.name} $title $time \n$content\n\n";

  LogItem(this.level, this.title, this.content);
}

enum LogLevel { error, warning, info }

class Log {
  static final List<LogItem> _logs = <LogItem>[];

  static List<LogItem> get logs => _logs;

  static const maxLogLength = 3000;

  static const maxLogNumber = 500;

  static bool ignoreLimitation = false;

  static bool isMuted = false;

  static void printWarning(String text) {
    debugPrint('\x1B[33m$text\x1B[0m');
  }

  static void printError(String text) {
    debugPrint('\x1B[31m$text\x1B[0m');
  }

  static LogFileWriter? _file;
  static final _beforeFile = <LogItem>[];

  static String? get filePath => _file?.file.path;

  /// A core session owns its destination; closing an old session cannot detach
  /// a replacement writer. Logs emitted before startup are replayed once.
  static Future<Future<void> Function()> startFileSession(File file) async {
    await _file?.flush();
    final writer = LogFileWriter(
      file,
      onError: (error, stack) {
        printWarning('Unable to persist logs: $error');
      },
    );
    _file = writer;
    for (final item in _beforeFile) {
      writer.add(item.toString());
    }
    _beforeFile.clear();
    return () async {
      if (identical(_file, writer)) _file = null;
      await writer.flush();
    };
  }

  static Future<void> flush() => _file?.flush() ?? Future<void>.value();

  static void addLog(LogLevel level, String title, String content) {
    if (isMuted) return;

    if (!ignoreLimitation && content.length > maxLogLength) {
      content = "${content.substring(0, maxLogLength)}...";
    }

    switch (level) {
      case LogLevel.error:
        printError(content);
      case LogLevel.warning:
        printWarning(content);
      case LogLevel.info:
        if (kDebugMode) {
          debugPrint(content);
        }
    }

    var newLog = LogItem(level, title, content);

    if (newLog == _logs.lastOrNull) {
      return;
    }

    _logs.add(newLog);
    final writer = _file;
    if (writer != null) {
      writer.add(newLog.toString());
    } else {
      _beforeFile.add(newLog);
      if (_beforeFile.length > maxLogNumber) _beforeFile.removeAt(0);
    }
    if (_logs.length > maxLogNumber) {
      var res = _logs.remove(
        _logs.firstWhereOrNull((element) => element.level == LogLevel.info),
      );
      if (!res) {
        _logs.removeAt(0);
      }
    }
  }

  static void info(String title, String content) {
    addLog(LogLevel.info, title, content);
  }

  static void warning(String title, String content) {
    addLog(LogLevel.warning, title, content);
  }

  static void error(String title, Object content, [Object? stackTrace]) {
    var info = content.toString();
    if (stackTrace != null) {
      info += "\n${stackTrace.toString()}";
    }
    addLog(LogLevel.error, title, info);
  }

  static void clear() {
    _logs.clear();
    _beforeFile.clear();
  }

  @override
  String toString() {
    var res = "Logs\n\n";
    for (var log in _logs) {
      res += log.toString();
    }
    return res;
  }
}
