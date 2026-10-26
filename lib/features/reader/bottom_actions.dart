import 'package:flutter/material.dart';
import 'package:venera_next/foundation/translations.dart';
import 'platform_effects_controller.dart';

/// Presentation only. Optional callbacks express host/platform capabilities.
List<Widget> buildReaderBottomActions(
  BuildContext context, {
  VoidCallback? onFullscreen,
  required ReaderOrientation orientation,
  VoidCallback? onRotate,
  required bool brightnessEnabled,
  required VoidCallback onBrightness,
  required VoidCallback onSave,
}) {
  return [
    if (onFullscreen != null)
      Tooltip(
        message: "${"Full Screen".tl}(F12)",
        child: IconButton(
          icon: const Icon(Icons.fullscreen),
          onPressed: onFullscreen,
        ),
      ),
    if (onRotate != null)
      Tooltip(
        message: "Screen Rotation".tl,
        child: IconButton(
          icon: Icon(switch (orientation) {
            ReaderOrientation.system => Icons.screen_rotation,
            ReaderOrientation.portrait => Icons.screen_lock_portrait,
            ReaderOrientation.landscape => Icons.screen_lock_landscape,
          }),
          onPressed: onRotate,
        ),
      ),
    Tooltip(
      message: 'Reader brightness'.tl,
      child: IconButton(
        icon: Icon(brightnessEnabled ? Icons.brightness_4 : Icons.brightness_6),
        color: brightnessEnabled ? Theme.of(context).colorScheme.primary : null,
        onPressed: onBrightness,
      ),
    ),
    Tooltip(
      message: "Save Image".tl,
      child: IconButton(icon: const Icon(Icons.download), onPressed: onSave),
    ),
  ];
}
