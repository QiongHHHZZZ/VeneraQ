import 'package:flutter/material.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/layout.dart';
import 'package:venera_next/components/select.dart';
import 'package:venera_next/features/discovery/discovery_toolbar.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/preferences.dart';
import 'package:venera_next/foundation/translations.dart';

/// The discovery page's own display controls, opened from its title bar.
///
/// These two settings decide how every result grid looks, so they belong next to
/// the grid instead of only inside Settings. The panel writes through the same
/// preference keys the settings page uses, so both doors show the same values.
///
/// It is a plain dialog like the shelf's "Display & sorting", so both screens
/// open and dismiss the same way.
class DiscoveryDisplaySheet extends StatefulWidget {
  const DiscoveryDisplaySheet({super.key});

  @override
  State<DiscoveryDisplaySheet> createState() => _DiscoveryDisplaySheetState();
}

class _DiscoveryDisplaySheetState extends State<DiscoveryDisplaySheet> {
  late String mode = GlobalPreferenceStore(
    appdata.settings,
  ).read(DiscoveryPreferences.comicDisplayMode);

  /// The size shown for the arrangement currently selected.
  ///
  /// The list and the grid store their own value, so switching arrangements
  /// shows that arrangement's size instead of overwriting the other one.
  late String size = _readSize();

  NumericPreference get _sizePreference => mode == 'brief'
      ? DiscoveryPreferences.comicTileScale
      : DiscoveryPreferences.comicListTileScale;

  String _readSize() => coverSizeLabel(
    GlobalPreferenceStore(appdata.settings).read(_sizePreference).toDouble(),
  );

  /// Saves the mode always, but only the size that belongs to the new mode.
  void _save({bool sizeChanged = false}) {
    final useMode = mode;
    final useScale = coverSizeScale(size);
    final target = _sizePreference;
    setState(() {});
    appdata.updateSettings((draft) {
      final writer = GlobalPreferenceStore(draft);
      writer.write(DiscoveryPreferences.comicDisplayMode, useMode);
      if (sizeChanged) writer.write(target, useScale);
    });
    // The page renders its grids from these values during build, so it has to be
    // told; otherwise the panel would appear to do nothing until a tab switch.
    DiscoveryToolbar.instance.notifyAppearanceChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "Display".tl,
      // No close icon: every choice saves on pick, so the dialog is dismissed by
      // tapping outside, the same as the shelf's display dialog.
      showClose: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text("Display".tl),
            trailing: Select(
              // The stored values stay "detailed"/"brief"; the labels name the
              // arrangement the reader actually gets.
              current: (mode == 'brief' ? "Grid" : "List").tl,
              values: ["List".tl, "Grid".tl],
              minWidth: 64,
              onTap: (index) {
                if (index < 0 || index > 1) return;
                mode = index == 1 ? 'brief' : 'detailed';
                // Show the size that belongs to the arrangement just chosen.
                size = _readSize();
                _save();
              },
            ),
          ),
          ListTile(
            // Named steps rather than a slider: three choices are quicker to hit
            // and the same three names appear on the shelf.
            title: Text("Cover size".tl),
            trailing: Select(
              current: switch (size) {
                'small' => "Small".tl,
                'large' => "Large".tl,
                _ => "Medium".tl,
              },
              values: ["Small".tl, "Medium".tl, "Large".tl],
              minWidth: 64,
              onTap: (index) {
                if (index < 0 || index > 2) return;
                size = const ['small', 'medium', 'large'][index];
                _save(sizeChanged: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the discovery display panel the same way the shelf opens its own.
Future<void> showDiscoveryDisplaySheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const DiscoveryDisplaySheet(),
  );
}
