import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/foundation/translations.dart';

import 'local.dart';

/// Opens the on-device directory that holds a downloaded comic.
///
/// Kept apart from any page: the local comics list is gone, but the folders it
/// managed still exist, so downloads and imports can still reveal their files.
/// The caller owns [context]'s route; a retired one never launches a fallback
/// application.
Future<void> openComicFolder(
  BuildContext context,
  LocalComic comic, {
  Future<void> Function(String path)? openDirectory,
}) async {
  if (!context.mounted) return;
  final owner = WindowSelectionTask(context);
  if (!owner.canPresent) return;
  try {
    final folderPath = comic.baseDir;
    await owner.run<void>((operation) async {
      operation.checkActive();
      if (openDirectory != null) {
        await openDirectory(folderPath);
        return;
      }
      if (App.isWindows) {
        await Process.run('explorer', [folderPath]);
      } else if (App.isMacOS) {
        await Process.run('open', [folderPath]);
      } else {
        if (App.isLinux) {
          for (final command in ['xdg-open', 'nautilus', 'dolphin', 'thunar']) {
            operation.checkActive();
            try {
              await Process.run(command, [folderPath]);
              return;
            } catch (_) {
              // Keep the existing fallback order while the original caller lives.
              operation.checkActive();
            }
          }
        }
        operation.checkActive();
        await launchUrlString('file://$folderPath');
      }
    }, reportFailureOnClose: true);
  } on SelectionCancelled {
    // Do not launch fallback applications for a retired caller.
  } catch (e, s) {
    Log.error("Open Folder", "Failed to open comic folder: $e", s);
    if (context.mounted && owner.canPresent) {
      context.showMessage(message: '${"Failed to open folder".tl}: $e');
    }
  }
}
