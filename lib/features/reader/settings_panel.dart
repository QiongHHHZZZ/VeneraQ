import 'package:flutter/widgets.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/routing/settings.dart';

import 'brightness.dart';
import 'settings_effects.dart';

/// Presentation adapter; the request owns target checks and effect ordering.
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.request,
    required this.work,
    required this.brightnessPreview,
    required this.onChanged,
  });

  final ReaderSettingsRequest request;
  final ImageWork work;
  final ReaderBrightnessPreview brightnessPreview;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) => SettingsSaveScope(
    work: work,
    child: ReaderSettings(
      comicId: request.comicId,
      comicSource: request.sourceKey,
      currentReaderMode: () => request.currentMode,
      onChanged: onChanged,
      brightnessPreview: brightnessPreview,
    ),
  );
}
