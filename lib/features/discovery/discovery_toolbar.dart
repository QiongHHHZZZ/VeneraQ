import 'package:flutter/material.dart';

/// Publishes the discovery page's source picker to the app's title bar.
///
/// The picker is the page's primary control: nothing is shown until a source is
/// chosen, so it belongs in the bar with the destination name rather than as a
/// second row underneath it. The page owns the widget and the state behind it;
/// the bar only renders what the page last published.
class DiscoveryToolbar extends ChangeNotifier {
  static final instance = DiscoveryToolbar();

  Widget? _title;

  /// The picker to show in the title bar, or null when discovery is not the
  /// visible destination.
  Widget? get title => _title;

  /// Called from the page's build with the current picker.
  ///
  /// Identity comparison keeps this cheap: the page rebuilds on every scroll
  /// position change, and only a genuinely new picker should repaint the bar.
  void setTitle(Widget? title) {
    if (identical(_title, title)) return;
    _title = title;
    notifyListeners();
  }

  /// Drops the published picker when the page goes away, so another destination
  /// does not inherit it.
  void clear() => setTitle(null);

  /// Tells the published page that the tile appearance changed.
  ///
  /// The grids read their layout from settings during build, so a value written
  /// from the title-bar panel only shows up once the page rebuilds. This keeps
  /// the change immediate instead of waiting for a tab switch.
  void notifyAppearanceChanged() => notifyListeners();
}
