import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/navigation_admission.dart';
import 'package:venera_next/foundation/persistence_failure.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'folder_name_validation.dart';

/// Renames a favorite folder.
///
/// Shares [validateFolderName] with the create dialog, so the two cannot drift
/// on what a legal name is. The name being renamed is excluded from the
/// duplicate check: keeping it unchanged is not a clash with itself.
class RenameFavoriteFolderDialog extends StatefulWidget {
  const RenameFavoriteFolderDialog({
    super.key,
    required this.initialName,
    required this.folders,
    required this.rename,
    this.isCurrent,
  });

  final String initialName;
  final Iterable<String> folders;
  final FutureOr<void> Function(String) rename;
  final bool Function()? isCurrent;

  @override
  State<RenameFavoriteFolderDialog> createState() =>
      _RenameFavoriteFolderDialogState();
}

class _RenameFavoriteFolderDialogState
    extends State<RenameFavoriteFolderDialog> {
  late final TextEditingController controller = TextEditingController(
    text: widget.initialName,
  );
  String? error;
  bool saving = false;
  bool _completed = false;
  WindowSelectionTask? _owner;
  NavigatorState? _navigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_owner == null) {
      _owner = WindowSelectionTask(context);
      _navigator = Navigator.of(context);
    }
  }

  bool get _canAct =>
      mounted &&
      _owner?.canPresent == true &&
      Navigator.maybeOf(context) == _navigator &&
      (widget.isCurrent?.call() ?? true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> rename() async {
    if (saving || !_canAct) return;
    if (_completed) {
      _navigator!.pop();
      return;
    }
    final task = WindowSelectionTask(context);
    if (!task.canPresent) return;
    final rename = widget.rename;
    final name = controller.text;
    final others = widget.folders.where((it) => it != widget.initialName);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final failure = await task.run<String?>((operation) async {
        final failure = validateFolderName(name, folders: others);
        operation.checkActive();
        if (failure != null) return failure;
        try {
          await rename(name);
          _completed = true;
        } on PersistenceFailure catch (writeFailure) {
          _completed =
              writeFailure.commitState != PersistenceCommitState.notCommitted;
          rethrow;
        }
        return null;
      });
      if (!_canAct) return;
      if (_completed) {
        _navigator!.pop();
      } else {
        setState(() => error = failure);
      }
    } on SelectionCancelled {
      // An accepted rename is awaited; a new one cannot start on exit.
    } catch (failure, stack) {
      Log.error('Rename favorite folder', failure, stack);
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => NavigationAdmission(
    allowsNavigation: () => _canAct,
    child: ContentDialog(
      title: "Rename Folder".tl,
      content: TextField(
        controller: controller,
        enabled: !saving && !_completed && _canAct,
        autofocus: true,
        decoration: InputDecoration(
          hintText: "Folder Name".tl,
          errorText: error,
        ),
        onChanged: (_) {
          if (saving || _completed || !_canAct) return;
          if (error != null) setState(() => error = null);
        },
        onSubmitted: (_) => rename(),
      ).paddingHorizontal(16),
      actions: [
        FilledButton(
          onPressed: saving || !_canAct ? null : rename,
          child: Text((_completed ? "OK" : "Rename").tl),
        ),
      ],
    ),
  );
}
