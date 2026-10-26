import 'package:flutter/widgets.dart';

import 'history_manager.dart';

/// The history store used by pages and reading sessions in this view.
class HistoryScope extends InheritedWidget {
  const HistoryScope({super.key, required this.manager, required super.child});

  final HistoryManager manager;

  static HistoryManager read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HistoryScope>()?.manager ??
      HistoryManager();

  @override
  bool updateShouldNotify(HistoryScope oldWidget) =>
      !identical(manager, oldWidget.manager);
}
