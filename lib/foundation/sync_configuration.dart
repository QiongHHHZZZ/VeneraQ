/// Stored names are part of the existing app-data archive protocol.
///
/// Only the version and excluded-field rules that local export/import depends
/// on remain here.
abstract final class SyncConfiguration {
  static String readExcludedFields(Object? value) =>
      value is String ? value : '';

  /// Versions decide whether imported data can replace local data. A malformed
  /// version must stop the import instead of silently becoming older.
  static int requireDataVersion(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid sync data version');
    }
    return value;
  }
}
