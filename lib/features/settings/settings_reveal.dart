import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera_next/foundation/context.dart';

/// Scrolls a settings page to one row and flashes a highlight around it.
///
/// Matches how the upstream settings search hands off: after choosing a result
/// the destination opens already scrolled to the setting, with a short frame
/// drawn around it. Without this the user lands at the top of a long page and
/// has to hunt for the row they searched for.
class SettingsRevealScope extends InheritedWidget {
  const SettingsRevealScope({
    super.key,
    required this.title,
    required super.child,
  });

  /// Localized title of the row to reveal, or null for a normal visit.
  final String? title;

  static String? targetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsRevealScope>()?.title;

  @override
  bool updateShouldNotify(SettingsRevealScope oldWidget) =>
      title != oldWidget.title;
}

/// Wraps a settings destination and reveals [title] once after it first builds.
class SettingsReveal extends StatefulWidget {
  const SettingsReveal({super.key, required this.title, required this.child});

  /// Localized row title to find. Null means "show the page normally".
  final String? title;

  final Widget child;

  @override
  State<SettingsReveal> createState() => _SettingsRevealState();
}

class _SettingsRevealState extends State<SettingsReveal> {
  final _content = GlobalKey();
  final _stack = GlobalKey();

  Rect? _highlight;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// First descendant Text whose data equals the target title.
  Element? _find(String title) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Text && widget.data == title) {
        found = element;
      } else {
        element.visitChildren(visit);
      }
    }

    final root = _content.currentContext;
    if (root is Element) root.visitChildren(visit);
    return found;
  }

  /// The page's own vertical scrollable, so the reveal can walk down a long page.
  ScrollPosition? _scrollPosition() {
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (axisDirectionToAxis(position.axisDirection) == Axis.vertical) {
          found = position;
        }
      }
      if (found == null) element.visitChildren(visit);
    }

    final root = _content.currentContext;
    if (root is Element) root.visitChildren(visit);
    return found;
  }

  /// Scrolls down in page-sized steps until the row is built or the end is hit.
  Future<Element?> _locate(String title) async {
    for (var step = 0; step < 80 && mounted; step++) {
      final target = _find(title);
      if (target != null) return target;
      final position = _scrollPosition();
      if (position == null ||
          !position.hasContentDimensions ||
          position.pixels >= position.maxScrollExtent) {
        return null;
      }
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  Future<void> _reveal() async {
    final title = widget.title;
    if (_done || title == null || !mounted) return;
    _done = true;
    final target = await _locate(title);
    if (!mounted || target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.15,
      duration: const Duration(milliseconds: 200),
    );
    if (!mounted || !target.mounted) return;
    // Highlight the whole row, not just the label: a bare text hit reads as a
    // stray line of colour.
    BuildContext row = target;
    target.visitAncestorElements((element) {
      if (element.widget is ListTile || element.widget is SwitchListTile) {
        row = element;
        return false;
      }
      return true;
    });
    if (!mounted || !row.mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !row.mounted ||
        !(_stack.currentContext?.mounted ?? false)) {
      return;
    }
    final box = row.findRenderObject();
    final stack = _stack.currentContext?.findRenderObject();
    if (box is! RenderBox || stack is! RenderBox) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: stack);
    setState(() {
      _highlight = topLeft & box.size;
    });
    _timer?.cancel();
    // Long enough to notice after the scroll settles, short enough not to
    // linger as a leftover selection state.
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stack,
      children: [
        Positioned.fill(
          child: KeyedSubtree(key: _content, child: widget.child),
        ),
        if (_highlight case final rect?)
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
