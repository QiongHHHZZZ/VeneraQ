import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:venera_next/foundation/file_system.dart';

/// Control files left in a comic directory by the retired import feature.
///
/// Importing from a directory used to reserve an output directory, write an
/// intent before copying, then a completion record, then a registration
/// receipt. The feature is gone, but those files may still exist on a device
/// that used it, and a library relocation must be able to read and retire them.
///
/// Nothing here writes an intent any more. Only the cleanup path survives, so
/// [prepare], [resume], [complete] and the verification helpers are gone with
/// the importer that called them.
class ComicCopyRecord {
  ComicCopyRecord._(this.directory, this._intent, this.metadata);

  static const intentName = '.venera-copy-intent.json';
  static const completionName = '.venera-copy-complete.json';
  static const registrationName = '.venera-copy-registered.json';
  static const stagingName = '.venera-copy-staging';
  static const _names = {
    intentName,
    completionName,
    registrationName,
    stagingName,
  };

  final Directory directory;
  final String _intent;

  /// The import intent's captured metadata, when the intent carried any.
  final String? metadata;

  String get intentDigest => sha256.convert(utf8.encode(_intent)).toString();

  File get _intentFile => File(FilePath.join(directory.path, intentName));
  File get _completionFile =>
      File(FilePath.join(directory.path, completionName));
  File get _registrationFile =>
      File(FilePath.join(directory.path, registrationName));

  static bool exists(Directory directory, {bool recursive = false}) => directory
      .listSync(recursive: recursive)
      .any((entry) => _names.contains(entry.name.toLowerCase()));

  static ComicCopyRecord read(Directory directory) {
    final receiptPath = FilePath.join(directory.path, registrationName);
    if (File(receiptPath).existsSync() || Directory(receiptPath).existsSync()) {
      throw StateError('Copy cleanup receipt cannot authorize registration');
    }
    return _fromIntent(
      directory,
      File(FilePath.join(directory.path, intentName)).readAsStringSync(),
    );
  }

  static ComicCopyRecord _fromIntent(Directory directory, String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> ||
        (value['version'] != 1 && value['version'] != 2) ||
        value['id'] is! String ||
        !Uuid.isValidUUID(fromString: value['id'] as String) ||
        value['source'] is! String ||
        (value['metadata'] != null && value['metadata'] is! String)) {
      throw const FormatException('Invalid comic copy intent');
    }
    return ComicCopyRecord._(directory, text, value['metadata'] as String?);
  }

  /// Cleanup may already have removed intent/completion. Its durable receipt
  /// retains the exact intent, but must never authorize a new registration.
  static ComicCopyRecord readForCleanup(Directory directory) {
    final receipt = File(FilePath.join(directory.path, registrationName));
    if (!receipt.existsSync()) return read(directory);
    final value = jsonDecode(receipt.readAsStringSync());
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['intent'] is! String ||
        value['registration'] is! String) {
      throw const FormatException('Invalid comic copy registration receipt');
    }
    return _fromIntent(directory, value['intent'] as String);
  }

  String _registrationReceipt(String registration) => jsonEncode({
    'version': 1,
    'intent': _intent,
    'registration': registration,
  });

  /// The registration snapshot comes from the actual current database row.
  bool hasRegistration(String registration) {
    if (!_registrationFile.existsSync() &&
        !Directory(_registrationFile.path).existsSync()) {
      return false;
    }
    if (_registrationFile.readAsStringSync() !=
        _registrationReceipt(registration)) {
      throw FileSystemException(
        'Copy cleanup registration has changed',
        directory.path,
      );
    }
    return true;
  }

  void _checkIntent() {
    if (_intentFile.readAsStringSync() != _intent) {
      throw FileSystemException('Comic copy intent changed', directory.path);
    }
  }

  void _checkCompletion() {
    final completion = jsonDecode(_completionFile.readAsStringSync());
    if (completion is! Map<String, dynamic> ||
        completion['version'] != 1 ||
        completion['intent'] != intentDigest) {
      throw FileSystemException(
        'Copy completion belongs to another intent',
        directory.path,
      );
    }
  }

  /// The caller has verified this exact database registration. Persist a
  /// cleanup receipt before removing either original record; a later retry
  /// must supply the same registration and never touches comic payload.
  void removeAfterRegistration(String registration) {
    if (!hasRegistration(registration)) {
      _checkIntent();
      _checkCompletion();
      final receipt = _registrationReceipt(registration);
      _registrationFile.writeAsStringSync(receipt, flush: true);
      if (!hasRegistration(registration)) {
        throw FileSystemException(
          'Copy cleanup receipt was not written',
          directory.path,
        );
      }
    }
    // Check both originals before deleting either one. An unexpected directory
    // or changed record is a conflict, never something to remove recursively.
    final hasIntent =
        _intentFile.existsSync() || Directory(_intentFile.path).existsSync();
    final hasCompletion =
        _completionFile.existsSync() ||
        Directory(_completionFile.path).existsSync();
    if (hasIntent) _checkIntent();
    if (hasCompletion) _checkCompletion();
    if (hasCompletion) _completionFile.deleteSync();
    if (hasIntent) {
      _checkIntent();
      _intentFile.deleteSync();
    }
    if (hasRegistration(registration)) _registrationFile.deleteSync();
  }
}
