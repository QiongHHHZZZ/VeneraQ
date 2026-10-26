import 'local_storage_guard.dart';

/// Drain accepted local storage work before the window closes.
///
/// This used to also cancel PDF import tasks, which no longer exist. The guard
/// still owns directory allocation for downloads and the exclusive migration
/// and recovery operations, so their work has to finish before exit.
Future<void Function()> prepareLocalImportsForExit() async {
  return await LocalComicStorageGuard.instance.prepareForExit();
}
