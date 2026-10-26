import 'package:venera_next/foundation/preferences.dart';
import 'package:venera_next/foundation/reader_preferences.dart';
import 'package:venera_next/foundation/reader_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/features/reader/reader_mode_labels.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/components/settings_save_state.dart';

class ReaderModeSettings extends StatefulWidget {
  const ReaderModeSettings({
    super.key,
    this.comicId,
    this.sourceKey,
    this.currentMode,
    this.onChanged,
  });

  final String? comicId;
  final String? sourceKey;
  final String Function()? currentMode;
  final VoidCallback? onChanged;

  @override
  State<ReaderModeSettings> createState() => _ReaderModeSettingsState();
}

class _ReaderModeSettingsState extends SettingsSaveState<ReaderModeSettings> {
  @override
  void initState() {
    super.initState();
    appdata.settings.addListener(_refresh);
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ReaderPreferenceStore get _store =>
      ReaderPreferenceStore(settings: appdata.settings);

  Future<bool> _setPreference<T extends Object>(
    Preference<T> preference,
    T value,
  ) {
    final target = (widget.comicId, widget.sourceKey);
    return saveSetting(
      preference.key,
      () => appdata.updateSettings((draft) {
        ReaderPreferenceStore(settings: draft).write(preference, value);
      }),
      onSaved: () => widget.onChanged?.call(),
      isCurrent: () => target == (widget.comicId, widget.sourceKey),
    );
  }

  Future<void> _chooseMode({
    required String title,
    required String value,
    required Future<bool> Function(String) onSelected,
    bool allowDefault = false,
  }) async {
    if (!acceptsSettingsChanges) return;
    final target = (widget.comicId, widget.sourceKey);
    final options = {
      if (allowDefault) 'default': 'Follow default'.tl,
      ...readerModeLabels,
    };
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: options.entries.map((option) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, option.key),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Icon(
                  value == option.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: value == option.key
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(option.value)),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (mounted &&
        selected != null &&
        target == (widget.comicId, widget.sourceKey) &&
        acceptsSettingsChanges &&
        options.containsKey(selected)) {
      await onSelected(selected);
    }
  }

  Widget _preference(
    String title,
    Preference<String> preference, {
    String? description,
  }) {
    final value = _store.read(preference);
    return ListTile(
      title: Text(title.tl),
      subtitle: Text(
        [
          readerModeLabels[value] ?? value,
          if (description != null) description.tl,
        ].join('\n'),
      ),
      trailing: const Icon(Icons.expand_more),
      onTap: () => _chooseMode(
        title: title.tl,
        value: value,
        onSelected: (value) => _setPreference(preference, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = appdata.settings;
    final cid = widget.comicId;
    final source = widget.sourceKey;
    if (cid == null || source == null) {
      return Column(
        children: [
          settingsSaveStatus,
          _preference('Default reading mode', ReaderPreferences.readerMode),
        ],
      );
    }

    final override = settings.comicReaderModeOverride(cid, source);
    // A mode removed in a later version must not surface as a raw stored key.
    final displayOverride = override == null
        ? null
        : ReaderPreferences.readerMode.normalize(override);
    final effective = settings.resolveReaderMode(cid, source);
    final current = widget.currentMode?.call() ?? effective;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsSaveStatus,
        ListTile(
          title: Text('Reading mode for this comic'.tl),
          subtitle: Text(
            [
              displayOverride == null
                  ? 'Follow default'.tl
                  : readerModeLabels[displayOverride] ?? displayOverride,
              'Currently using: @mode'.tlParams({
                'mode': readerModeLabels[current] ?? current,
              }),
            ].join('\n'),
          ),
          trailing: const Icon(Icons.expand_more),
          onTap: () => _chooseMode(
            title: 'Reading mode for this comic'.tl,
            value: displayOverride ?? 'default',
            allowDefault: true,
            onSelected: (value) => saveSetting(
              (cid, source, 'readerMode'),
              () => appdata.updateSettings((draft) {
                draft.setComicReaderModeOverride(
                  cid,
                  source,
                  value == 'default' ? null : value,
                );
              }),
              onSaved: () => widget.onChanged?.call(),
              isCurrent: () =>
                  cid == widget.comicId && source == widget.sourceKey,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'This selection only affects this comic. Change default preferences in Settings → Reader.'
                .tl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
