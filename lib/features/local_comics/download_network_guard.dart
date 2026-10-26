import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/log.dart';

import 'local.dart';

/// Pauses downloads on a metered connection while "Download on WiFi only" is on,
/// and lets them continue once an unmetered link returns.
///
/// The queue itself stays unaware of how the decision is made: this only flips
/// one block flag, mirroring how the reader keeps platform concerns outside its
/// session logic.
class DownloadNetworkGuard {
  DownloadNetworkGuard._();

  static final DownloadNetworkGuard instance = DownloadNetworkGuard._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Whether the last evaluation proved a metered-only connection.
  bool get isBlocked => _blocked;
  bool _blocked = false;

  final _settings = GlobalPreferenceStore(appdata.settings);

  /// Begin watching connectivity. Idempotent, and safe before any download
  /// exists: it evaluates the current link once and then on every change.
  void start() {
    _subscription ??= Connectivity().onConnectivityChanged.listen(
      (_) => unawaited(_evaluate()),
      onError: (_) {},
    );
    unawaited(_evaluate());
  }

  /// Re-evaluate at once after the switch is toggled, so the effect is
  /// immediate instead of waiting for the next connectivity event.
  void onSettingChanged() => unawaited(_evaluate());

  Future<void> _evaluate() async {
    final manager = LocalManager.current;
    if (manager == null) return;
    // Setting off: never block on our account, clearing any earlier block.
    if (!_settings.read(NetworkPreferences.downloadWifiOnly)) {
      _apply(manager, false);
      return;
    }
    List<ConnectivityResult> result;
    try {
      result = await Connectivity().checkConnectivity();
    } catch (error) {
      // Cannot tell the link type. Leave the queue as it is rather than
      // guessing and stranding downloads.
      Log.error('Download', 'connectivity check failed: $error');
      return;
    }
    final unmetered =
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
    final metered = result.contains(ConnectivityResult.mobile);
    // Block only a clearly metered link with no unmetered one. "No network" is
    // not treated as a block: downloads fail and retry on their own, and the
    // next real event re-evaluates this.
    _apply(manager, metered && !unmetered);
  }

  void _apply(LocalManager manager, bool blocked) {
    _blocked = blocked;
    manager.setDownloadsNetworkBlocked(blocked);
  }

  /// Stop watching. Used when the owning application shuts down.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _blocked = false;
  }
}
