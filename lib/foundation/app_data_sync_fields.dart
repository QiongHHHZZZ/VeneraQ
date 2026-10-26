/// Fields retained locally by application-data imports. Keep content comparison
/// and import policy together so archive bookkeeping cannot create dirty data.
const appDataLocalFields = {
  'proxy',
  'disableSyncFields',
  'lastSyncTime',
};

List<String> splitAppDataFields(String value) => value
    .split(',')
    .map((field) => field.trim())
    .where((field) => field.isNotEmpty)
    .toList();
