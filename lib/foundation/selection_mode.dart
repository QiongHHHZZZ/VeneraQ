import 'package:flutter/foundation.dart';

/// Publishes "a page is in selection mode" to the app's title bar.
///
/// The title bar owns the back gesture. A page inside the navigator cannot refuse
/// that gesture — the navigator has nothing to pop, so the app would quit — so a
/// page with a selection mode registers a callback here and the bar calls it
/// instead of leaving.
class SelectionModeNotifier extends ChangeNotifier {
  static final instance = SelectionModeNotifier();

  bool _active = false;

  /// Whether a page currently holds a selection.
  bool get active => _active;

  /// Called by the owning page to leave its selection mode.
  VoidCallback? leave;

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  /// Asks the owning page to leave its selection mode.
  ///
  /// Returns whether a page claimed the gesture.
  bool leaveSelection() {
    final callback = leave;
    if (!_active || callback == null) return false;
    callback();
    return true;
  }
}
