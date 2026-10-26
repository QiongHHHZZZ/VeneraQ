import 'package:flutter/foundation.dart';

/// A page-level claim on the system back gesture.
///
/// The app shell owns the back gesture: it receives it, then forwards it to the
/// navigator, which pops the top route. A route's `PopScope` can veto that pop,
/// but only once the navigator asks — and a page that must not be left at all
/// (an active chapter selection) needs the decision to happen earlier.
///
/// A page registers here while it wants the next back, so the shell consumes the
/// gesture before the navigator can act on it. This mirrors the platform's back
/// dispatcher, where the innermost enabled handler wins.
class BackInterceptor {
  BackInterceptor._();

  static VoidCallback? _handler;

  /// Claims the next back gesture.
  ///
  /// One page is on top at a time, so the newest claim wins; a page that forgets
  /// to release its claim cannot block a later page's back.
  static void register(VoidCallback handler) => _handler = handler;

  /// Releases a claim. Harmless when another page has already taken over.
  static void unregister(VoidCallback handler) {
    if (identical(_handler, handler)) _handler = null;
  }

  /// Drops any claim. Used when a page goes away without releasing.
  static void clear() => _handler = null;

  /// Runs the active claim, reporting whether it consumed the gesture.
  static bool handle() {
    final handler = _handler;
    if (handler == null) return false;
    handler();
    return true;
  }
}
