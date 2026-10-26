import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/selection_mode.dart';
import 'package:venera_next/foundation/back_interceptor.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_page_route.dart';
import 'package:venera_next/foundation/consts.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/edge_back_gesture.dart';
import 'package:venera_next/foundation/widget_utils.dart';

import 'consts.dart';
import 'gesture.dart';

class PaneItemEntry {
  String label;

  IconData icon;

  IconData activeIcon;

  PaneItemEntry({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class PaneActionEntry {
  String label;

  IconData icon;

  VoidCallback onTap;

  PaneActionEntry({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class NaviPane extends StatefulWidget {
  const NaviPane({
    required this.paneItems,
    required this.paneActions,
    required this.pageBuilder,
    this.paneLeading,
    this.paneTitle,
    this.initialPage = 0,
    this.onPageChanged,
    required this.observer,
    required this.navigatorKey,
    super.key,
  });

  final List<PaneItemEntry> paneItems;

  final List<PaneActionEntry> paneActions;

  /// Optional control rendered before the title of the narrow top bar.
  ///
  /// A pane that provides none — every destination without a leading action —
  /// renders exactly as before, with the title kept off the left edge by the
  /// bar's own padding. The wide layouts drop the top bar entirely, so this
  /// slot has no side-bar counterpart.
  final Widget? paneLeading;

  /// Replaces the destination label with a page-supplied control.
  ///
  /// A destination whose own primary control is a picker — discovery chooses a
  /// source before showing anything — reads better with that picker in the bar
  /// than as a second row under it. The wide layouts keep the plain label.
  final Widget? paneTitle;

  final Widget Function(int page) pageBuilder;

  final void Function(int index)? onPageChanged;

  final int initialPage;

  final NaviObserver observer;

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<NaviPane> createState() => NaviPaneState();

  static NaviPaneState of(BuildContext context) {
    return context.findAncestorStateOfType<NaviPaneState>()!;
  }
}

typedef NaviItemTapListener = void Function(int);

class NaviPaneState extends State<NaviPane>
    with SingleTickerProviderStateMixin {
  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    widget.onPageChanged?.call(value);
  }

  void Function()? mainViewUpdateHandler;

  late AnimationController controller;

  final _naviItemTapListeners = <NaviItemTapListener>[];

  void addNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.add(listener);
  }

  void removeNaviItemTapListener(NaviItemTapListener listener) {
    _naviItemTapListeners.remove(listener);
  }

  static const _kBottomBarHeight = 58.0;

  static const _kFoldedSideBarWidth = 72.0;

  static const _kSideBarWidth = 224.0;

  static const _kTopBarHeight = 48.0;

  void onNavigatorStateChange() {
    onRebuild(context);
  }

  void updatePage(int index) {
    for (var listener in _naviItemTapListeners) {
      listener(index);
    }
    if (widget.observer.routes.length > 1) {
      widget.navigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
    if (currentPage == index) {
      return;
    }
    setState(() {
      currentPage = index;
    });
    mainViewUpdateHandler?.call();
  }

  @override
  void initState() {
    controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      lowerBound: 0,
      upperBound: 3,
      vsync: this,
    );
    widget.observer.addListener(onNavigatorStateChange);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant NaviPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.observer, widget.observer)) {
      oldWidget.observer.removeListener(onNavigatorStateChange);
      if (oldWidget.navigatorKey == widget.navigatorKey) {
        widget.observer._adoptRoutes(
          oldWidget.observer,
          widget.navigatorKey.currentState,
        );
      }
      widget.observer.addListener(onNavigatorStateChange);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    widget.observer.removeListener(onNavigatorStateChange);
    widget.observer._releaseDetachedNavigator();
    mainViewUpdateHandler = null;
    _naviItemTapListeners.clear();
    super.dispose();
  }

  double targetFormContext(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    double target = 0;
    if (width > changePoint) {
      target = 2;
    }
    if (width > changePoint2) {
      target = 3;
    }
    return target;
  }

  double? animationTarget;

  void onRebuild(BuildContext context) {
    double target = targetFormContext(context);
    if (controller.value != target || animationTarget != target) {
      if (controller.isAnimating) {
        if (animationTarget == target) {
          return;
        } else {
          controller.stop();
        }
      }
      controller.animateTo(target);
      animationTarget = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    onRebuild(context);
    final mq = MediaQuery.of(context);
    final sideInsets = (App.isMobile && mq.orientation == Orientation.landscape)
        ? EdgeInsets.only(
            left: math.max(mq.viewPadding.left, mq.systemGestureInsets.left),
            right: math.max(mq.viewPadding.right, mq.systemGestureInsets.right),
          )
        : EdgeInsets.zero;
    return _NaviPopScope(
      action: () {
        if (appNavigation.mainNavigatorKey!.currentState!.canPop()) {
          appNavigation.mainNavigatorKey!.currentState!.maybePop();
        } else {
          SystemNavigator.pop();
        }
      },
      popGesture: App.isIOS && context.width >= changePoint,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final value = controller.value;
          Widget content = Stack(
            children: [
              Positioned(
                left: _kFoldedSideBarWidth * ((value - 2.0).clamp(-1.0, 0.0)),
                top: 0,
                bottom: 0,
                child: buildLeft(),
              ),
              Positioned.fill(
                left:
                    _kFoldedSideBarWidth * ((value - 1).clamp(0, 1)) +
                    (_kSideBarWidth - _kFoldedSideBarWidth) *
                        ((value - 2).clamp(0, 1)),
                child: buildMainView(),
              ),
            ],
          );
          if (sideInsets != EdgeInsets.zero) {
            content = Padding(padding: sideInsets, child: content);
          }
          return content;
        },
      ),
    );
  }

  Widget buildMainView() {
    return HeroControllerScope(
      controller: MaterialApp.createMaterialHeroController(),
      child: PopScope(
        // Claim back here and forward it, instead of letting the shell route
        // answer the gesture itself.
        //
        // This scope sits above every pushed page. When it reported canPop:
        // true the gesture was resolved at this level, so a page never got to
        // refuse it: a chapter selection could not swallow back, and the whole
        // comic closed instead of just leaving selection mode. Forwarding to the
        // navigator first lets each page's own PopScope decide, and only an
        // empty navigator leaves the app.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          // A page that must not be left — an active chapter selection, for
          // instance — consumes the gesture here, before the navigator is asked
          // to pop. Otherwise the pop would be decided at the navigator, where a
          // page has no reliable way to refuse it.
          if (BackInterceptor.handle()) {
            return;
          }
          // A page's selection mode is the same kind of claim: while it is on,
          // back leaves the mode rather than the page. It cannot refuse from
          // inside the navigator, so it publishes the flag instead.
          if (SelectionModeNotifier.instance.leaveSelection()) {
            return;
          }
          final navigator = widget.navigatorKey.currentState;
          if (navigator != null && navigator.canPop()) {
            navigator.maybePop(result);
            return;
          }
          // Overlays pushed on the root navigator — the long-press menu, for
          // instance — are not part of this inner navigator, so canPop() cannot
          // see them. Asking the root navigator first lets such an overlay close
          // instead of the gesture falling through to SystemNavigator.pop and
          // quitting the app.
          final root = Navigator.of(
            context,
            rootNavigator: true,
          );
          if (root.canPop()) {
            root.maybePop(result);
            return;
          }
          // Nothing left to pop: back leaves the app, as before.
          SystemNavigator.pop();
        },
        child: Navigator(
          observers: [widget.observer],
          key: widget.navigatorKey,
          onGenerateRoute: (settings) => AppPageRoute(
            preventRebuild: false,
            builder: (context) {
              return _NaviMainView(state: this);
            },
          ),
        ),
      ),
    );
  }

  Widget buildMainViewContent() {
    return widget.pageBuilder(currentPage);
  }

  Widget buildTop() {
    final leading = widget.paneLeading;
    final custom = widget.paneTitle;
    final title = Text(
      widget.paneItems[currentPage].label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Material(
      child: Container(
        // A leading control occupies the row itself, so the bar only has to
        // keep the title off the edge when nothing precedes it.
        padding: EdgeInsets.only(left: leading == null ? 16 : 4, right: 4),
        height: _kTopBarHeight,
        width: double.infinity,
        child: Row(
          children: [
            ?leading,
            if (custom == null)
              // A tight constraint makes the title consume the free space, so
              // the actions sit flush against the right edge. A loose Flexible
              // would keep its intrinsic width and leave the gap before the
              // actions.
              Expanded(child: title)
            else ...[
              // Three equal columns put the page's control in the middle of the
              // bar itself. Centring it in whatever space the title left over
              // pushed it right, because the title is narrower than the icons.
              Expanded(child: Align(alignment: Alignment.centerLeft, child: title)),
              Expanded(child: Center(child: custom)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var action in widget.paneActions)
                        Tooltip(
                          message: action.label,
                          child: IconButton(
                            icon: Icon(action.icon),
                            onPressed: action.onTap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            // The actions are rendered once, here. When the page supplies its own
            // control they were also rendered inside the three-column block
            // above, which drew every icon twice.
            if (custom == null)
              for (var action in widget.paneActions)
                Tooltip(
                  message: action.label,
                  child: IconButton(
                    icon: Icon(action.icon),
                    onPressed: action.onTap,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget buildBottom() {
    return Material(
      textStyle: Theme.of(context).textTheme.labelSmall,
      elevation: 0,
      child: Container(
        height: _kBottomBarHeight,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: List<Widget>.generate(widget.paneItems.length, (index) {
            return Expanded(
              child: _SingleBottomNaviWidget(
                enabled: currentPage == index,
                entry: widget.paneItems[index],
                onTap: () {
                  updatePage(index);
                },
                key: ValueKey(index),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget buildLeft() {
    final value = controller.value;
    final topPadding = MediaQuery.paddingOf(context).top;
    final dividerColor = Theme.of(context).colorScheme.outlineVariant;
    const paddingHorizontal = 12.0;
    return Material(
      child: SizedBox(
        width:
            _kFoldedSideBarWidth +
            (_kSideBarWidth - _kFoldedSideBarWidth) * ((value - 2).clamp(0, 1)),
        height: double.infinity,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: paddingHorizontal,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  SizedBox(height: topPadding),
                  ...List<Widget>.generate(
                    widget.paneItems.length,
                    (index) => _SideNaviWidget(
                      enabled: currentPage == index,
                      entry: widget.paneItems[index],
                      showTitle: value == 3,
                      onTap: () {
                        updatePage(index);
                      },
                      key: ValueKey(index),
                    ),
                  ),
                  const Spacer(),
                  ...List<Widget>.generate(
                    widget.paneActions.length,
                    (index) => _PaneActionWidget(
                      entry: widget.paneActions[index],
                      showTitle: value == 3,
                      key: ValueKey(index + widget.paneItems.length),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Positioned(
              top: topPadding,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: dividerColor,
                child: const SizedBox(width: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNaviWidget extends StatelessWidget {
  const _SideNaviWidget({
    required this.enabled,
    required this.entry,
    required this.onTap,
    required this.showTitle,
    super.key,
  });

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(enabled ? entry.activeIcon : entry.icon);
    return ClickInkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 38,
        decoration: BoxDecoration(
          color: enabled ? colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: showTitle
            ? Row(
                children: [icon, const SizedBox(width: 12), Text(entry.label)],
              )
            : Align(alignment: Alignment.centerLeft, child: icon),
      ),
    ).paddingVertical(4);
  }
}

class _PaneActionWidget extends StatelessWidget {
  const _PaneActionWidget({
    required this.entry,
    required this.showTitle,
    super.key,
  });

  final PaneActionEntry entry;

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(entry.icon);
    return ClickInkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 38,
        child: showTitle
            ? Row(
                children: [icon, const SizedBox(width: 12), Text(entry.label)],
              )
            : Align(alignment: Alignment.centerLeft, child: icon),
      ),
    ).paddingVertical(4);
  }
}

class _SingleBottomNaviWidget extends StatefulWidget {
  const _SingleBottomNaviWidget({
    required this.enabled,
    required this.entry,
    required this.onTap,
    super.key,
  });

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  @override
  State<_SingleBottomNaviWidget> createState() =>
      _SingleBottomNaviWidgetState();
}

class _SingleBottomNaviWidgetState extends State<_SingleBottomNaviWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  bool isHovering = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SingleBottomNaviWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        controller.forward(from: 0);
      } else {
        controller.reverse(from: 1);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      value: widget.enabled ? 1 : 0,
      vsync: this,
      duration: fastAnimationDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (details) => setState(() => isHovering = true),
          onExit: (details) => setState(() => isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            child: buildContent(),
          ),
        );
      },
    );
  }

  Widget buildContent() {
    final value = controller.value;
    final colorScheme = Theme.of(context).colorScheme;
    final icon = Icon(
      widget.enabled ? widget.entry.activeIcon : widget.entry.icon,
    );
    return Center(
      child: Container(
        width: 64,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(32)),
          color: isHovering ? colorScheme.surfaceContainer : Colors.transparent,
        ),
        child: Center(
          child: Container(
            width: 32 + value * 32,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(32)),
              color: value != 0
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class NaviObserver extends NavigatorObserver implements Listenable {
  var routes = Queue<Route>();
  NavigatorState? _owner;

  void _adoptRoutes(NaviObserver previous, NavigatorState? owner) {
    _owner = owner;
    routes
      ..clear()
      ..addAll(previous.routes.where((route) => route.navigator == owner));
    previous._owner = null;
    previous.routes.clear();
  }

  void _releaseDetachedNavigator() {
    if (navigator == null) {
      _owner = null;
      routes.clear();
    }
  }

  void _bindNavigator() {
    if (!identical(_owner, navigator)) {
      _owner = navigator;
      routes.clear();
    }
  }

  int get pageCount {
    int count = 0;
    for (var route in routes) {
      if (route is AppPageRoute) {
        count++;
      }
    }
    return count;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _bindNavigator();
    routes.remove(route);
    notifyListeners();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _bindNavigator();
    routes.addLast(route);
    notifyListeners();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _bindNavigator();
    routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _bindNavigator();
    final stack = routes.toList();
    final index = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        stack.removeAt(index);
      } else {
        stack[index] = newRoute;
      }
      routes
        ..clear()
        ..addAll(stack);
    } else if (newRoute != null) {
      routes.addLast(newRoute);
    }
    notifyListeners();
  }

  List<VoidCallback> listeners = [];

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in List<VoidCallback>.of(listeners)) {
      if (listeners.contains(listener)) listener();
    }
  }
}

class _NaviPopScope extends StatefulWidget {
  const _NaviPopScope({
    required this.child,
    this.popGesture = false,
    required this.action,
  });

  final Widget child;
  final bool popGesture;
  final VoidCallback action;

  @override
  State<_NaviPopScope> createState() => _NaviPopScopeState();
}

class _NaviPopScopeState extends State<_NaviPopScope> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return EdgeBackGestureDetector(
      enabled: () => widget.popGesture,
      onStart: () => _progress = 0,
      onUpdate: (delta) => _progress = (_progress + delta).clamp(0, 1),
      onEnd: (velocity) {
        final shouldPop = velocity.abs() >= 1
            ? velocity > 0 && _progress >= 0.1
            : _progress >= 0.5;
        _progress = 0;
        if (shouldPop) widget.action();
      },
      onCancel: () => _progress = 0,
      child: widget.child,
    );
  }
}

class _NaviMainView extends StatefulWidget {
  const _NaviMainView({required this.state});

  final NaviPaneState state;

  @override
  State<_NaviMainView> createState() => _NaviMainViewState();
}

class _NaviMainViewState extends State<_NaviMainView> {
  NaviPaneState get state => widget.state;

  @override
  void initState() {
    state.mainViewUpdateHandler = _update;
    super.initState();
  }

  void _update() => setState(() {});

  void _detach(NaviPaneState previous) {
    if (previous.mainViewUpdateHandler == _update) {
      previous.mainViewUpdateHandler = null;
    }
  }

  @override
  void didUpdateWidget(covariant _NaviMainView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, state)) {
      _detach(oldWidget.state);
      state.mainViewUpdateHandler = _update;
    }
  }

  @override
  void dispose() {
    _detach(state);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var shouldShowAppBar = state.controller.value < 2;
    return Column(
      children: [
        if (shouldShowAppBar) state.buildTop().paddingTop(context.padding.top),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: shouldShowAppBar,
            child: AnimatedSwitcher(
              duration: fastAnimationDuration,
              child: state.buildMainViewContent(),
            ),
          ),
        ),
        if (shouldShowAppBar)
          state.buildBottom().paddingBottom(context.padding.bottom),
      ],
    );
  }
}
