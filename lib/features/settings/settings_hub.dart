import 'package:flutter/material.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

/// One selectable destination inside the settings screen.
///
/// [title] and [description] are translation keys, not displayed text:
/// rendering applies `.tl` so a new entry cannot silently ship untranslated.
class SettingsEntry {
  const SettingsEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.builder,
  });

  final String title;

  /// One line explaining what the destination holds. The list is a table of
  /// contents rather than a set of bare names.
  final String description;

  final IconData icon;

  final Widget Function() builder;
}

/// A single settings destination row rendered in the settings list.
class SettingsEntryTile extends StatelessWidget {
  const SettingsEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.selected = false,
    this.padding = EdgeInsets.zero,
  });

  final SettingsEntry entry;

  final VoidCallback onTap;

  final bool selected;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: ClickInkWell(
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey(entry.title),
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer.toOpacity(0.36) : null,
            border: Border(
              left: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(entry.icon),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.title.tl,
                      style: ts.s16,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.description.tl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts.s12.withColor(colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.arrow_right),
            ],
          ),
        ),
      ).paddingVertical(4),
    );
  }
}
