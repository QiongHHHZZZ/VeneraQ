import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart' show Dio;
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';

import 'comic_source_manager.dart';
import 'github_source_search_page.dart';
import 'source.dart';
import 'source_failure.dart';
import 'source_failure_presentation.dart';
import 'source_installations_scope.dart';
import 'source_repositories.dart';
import 'source_repository_sources_page.dart';

class SourceRepositoriesPanel extends StatelessWidget {
  const SourceRepositoriesPanel({super.key, this.createClient});

  final Dio Function()? createClient;

  @override
  Widget build(BuildContext context) {
    final store = SourceRepositories.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, ComicSourceManager()]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text(
            'Save repositories to browse and install comic sources.'.tl,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _editRepository(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add repository'.tl),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Discovery is a separate door: it searches GitHub instead of
                // asking for a URL the user would have to find elsewhere.
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await showPopUpWidget(
                      context,
                      const GitHubSourceSearchPage(),
                    );
                  },
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: Text('Find on GitHub'.tl),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (store.all.isEmpty)
            SourceManagementEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No repositories yet'.tl,
              description:
                  'Add a repository using its source list URL. Installed sources are managed in the Installed tab.'
                      .tl,
            ),
          for (final repository in store.all)
            _RepositoryCard(
              repository: repository,
              sourceCount: _linkedCount(repository),
              onOpen: () => _openRepository(context, repository),
              onEdit: () => _editRepository(context, repository),
              onRemove: () => _removeRepository(context, repository),
              onCopy: () => _copyRepository(context, repository),
              onToggle: (value) =>
                  SourceRepositories.instance.setEnabled(repository.id, value),
            ),
        ],
      ),
    );
  }

  int _linkedCount(SourceRepository repository) => ComicSource.all()
      .where(
        (s) =>
            SourceRepositories.instance.originFor(s.key)?.repositoryId ==
            repository.id,
      )
      .length;

  /// Opens one repository's own source list.
  ///
  /// The store is looked up again because the card may have been built before
  /// an edit replaced the repository object.
  Future<void> _openRepository(
    BuildContext context,
    SourceRepository repository,
  ) async {
    final current = SourceRepositories.instance.find(repository.id);
    if (current == null) return;
    await showPopUpWidget(
      context,
      SourceRepositorySourcesPage.saved(current, createClient: createClient),
    );
  }

  Future<void> _editRepository(
    BuildContext context, [
    SourceRepository? repository,
  ]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _RepositoryEditor(repository: repository, createClient: createClient),
  );

  Future<void> _removeRepository(
    BuildContext context,
    SourceRepository repository,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RepositoryActionDialog(
        title: 'Remove repository'.tl,
        content:
            'Remove "@name"? Its @count linked sources, their settings and your reading data will be kept. These sources will no longer be included in repository update checks.'
                .tlParams({
                  'name': repository.name,
                  'count': _linkedCount(repository).toString(),
                }),
        perform: () => SourceRepositories.instance.remove(repository),
      ),
    );
  }

  /// Puts the repository's source-list address on the clipboard.
  ///
  /// The address is not drawn anywhere in source management any more, so this
  /// is the only way to get hold of it — for sharing, or for adding the same
  /// list on another device. Duplicating the repository itself is not an
  /// option: the store refuses two entries with the same address.
  Future<void> _copyRepository(
    BuildContext context,
    SourceRepository repository,
  ) async {
    await Clipboard.setData(ClipboardData(text: repository.url));
    if (context.mounted) {
      context.showMessage(message: 'Repository address copied'.tl);
    }
  }
}

class _RepositoryEditor extends StatefulWidget {
  const _RepositoryEditor({this.repository, this.createClient});
  final SourceRepository? repository;
  final Dio Function()? createClient;
  @override
  State<_RepositoryEditor> createState() => _RepositoryEditorState();
}

class _RepositoryEditorState extends SettingsSaveState<_RepositoryEditor> {
  late final name = TextEditingController(text: widget.repository?.name);
  late final url = TextEditingController(text: widget.repository?.url);
  bool get saving => savingSettings;
  bool get busy => savingSettings || hasSettingsSaveError;
  String? error;

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!acceptsSettingsChanges || busy) return;
    final id = widget.repository?.id;
    final capturedName = name.text;
    final capturedUrl = url.text;
    final createClient = widget.createClient;
    SourceRepositorySave? request;
    error = null;
    await saveSetting(
      'repository',
      () async {
        error = null;
        try {
          request ??= SourceRepositories.instance.prepareSave(
            id: id,
            name: capturedName,
            url: capturedUrl,
            createClient: createClient,
          );
          await request!.validate();
        } catch (failure) {
          // Validation has not published anything; keep the input editable.
          error = sourceFailureMessage(failure);
          return;
        }
        try {
          await request!.save();
        } on SourceFailure catch (failure) {
          error = sourceFailureMessage(failure);
        } catch (failure) {
          error = sourceFailureMessage(failure);
          rethrow;
        }
      },
      onSaved: () {
        if (error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(leaveSettings());
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => protectSettings(
    AlertDialog(
      scrollable: true,
      title: Text(
        (widget.repository == null ? 'Add repository' : 'Edit repository').tl,
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text('Repository name'.tl)),
            const SizedBox(height: 8),
            Semantics(
              label: 'Repository name'.tl,
              child: TextField(
                controller: name,
                autofocus: true,
                enabled: !busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'A name you recognize'.tl,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ExcludeSemantics(child: Text('Source list URL'.tl)),
            const SizedBox(height: 8),
            Semantics(
              label: 'Source list URL'.tl,
              child: TextField(
                controller: url,
                enabled: !busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/index.json',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the JSON source list address, not a single script link.'.tl,
            ),
            if (widget.repository != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Changing this address also changes where linked sources check for updates.'
                      .tl,
                ),
              ),
            settingsSaveStatus,
            if (saving)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Validating repository'.tl,
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: acceptsSettingsChanges ? leaveSettings : null,
          child: Text('Cancel'.tl),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text((saving ? 'Validating repository' : 'Save').tl),
        ),
      ],
    ),
  );
}

class _RepositoryActionDialog extends StatefulWidget {
  const _RepositoryActionDialog({
    required this.title,
    required this.content,
    required this.perform,
  });
  final String title;
  final String content;
  final Future<void> Function() perform;
  @override
  State<_RepositoryActionDialog> createState() =>
      _RepositoryActionDialogState();
}

class _RepositoryActionDialogState
    extends SettingsSaveState<_RepositoryActionDialog> {
  String? error;
  Future<void> submit() async {
    if (!acceptsSettingsChanges || savingSettings || hasSettingsSaveError) {
      return;
    }
    final perform = widget.perform;
    await saveSetting(
      'repository-action',
      () async {
        error = null;
        try {
          await perform();
        } on SourceFailure catch (failure) {
          error = sourceFailureMessage(failure);
        } catch (failure) {
          error = sourceFailureMessage(failure);
          rethrow;
        }
      },
      onSaved: () {
        if (error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(leaveSettings());
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => protectSettings(
    AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.content),
          settingsSaveStatus,
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: acceptsSettingsChanges ? leaveSettings : null,
          child: Text('Cancel'.tl),
        ),
        FilledButton(
          onPressed: savingSettings || hasSettingsSaveError ? null : submit,
          child: Text(widget.title),
        ),
      ],
    ),
  );
}

/// Switches an installed source to the copy another repository publishes.
///
/// Picking a repository used to only relink the source for update checks: the
/// script, the version and the code all stayed the old repository's, so a
/// source installed from one repository could never be moved to a newer or
/// older copy elsewhere — the page said "updates now follow X" while running
/// the old script. Replacement is what the reader asked for by choosing a
/// different repository, so it is what happens here; when the two copies are
/// the same address there is nothing to replace and only the link is written.
Future<void> showSourceOriginPicker(
  BuildContext context,
  ComicSource source,
) async {
  final repository = await showDialog<SourceRepository>(
    context: context,
    builder: (_) => _SourceOriginPicker(source: source),
  );
  if (repository == null || !context.mounted) return;
  // The entry must come from the chosen repository's catalog: it is the only
  // authority on the address and the version being switched to.
  final store = SourceRepositories.instance;
  final entry = await _confirmLink(context, store, repository, source);
  if (entry == null || !context.mounted) return;
  if (entry.url == source.url) {
    // Same address: the script is already this copy, so only the update link
    // needs to move.
    try {
      await store.link(source.key, repository, entry);
      if (context.mounted) {
        context.showMessage(
          message: 'Updates now follow @repo'.tlParams({
            'repo': repository.name,
          }),
        );
      }
    } catch (error) {
      if (context.mounted) {
        context.showMessage(message: sourceFailureMessage(error));
      }
    }
    return;
  }
  final confirmed = await _confirmSwitch(context, source, repository, entry);
  if (confirmed != true || !context.mounted) return;
  try {
    SourceInstallationsScope.of(
      context,
    ).replaceFromRepository(repository, entry);
    if (context.mounted) {
      context.showMessage(
        message: 'Switching to @version from @repo'.tlParams({
          'version': entry.version,
          'repo': repository.name,
        }),
      );
    }
  } catch (error) {
    if (context.mounted) {
      context.showMessage(message: sourceFailureMessage(error));
    }
  }
}

/// Confirms replacing a working script with another repository's copy.
///
/// Settings belong to the script that defined them, so the reader has to know
/// before the swap that the source's own settings and account will need setting
/// up again.
Future<bool?> _confirmSwitch(
  BuildContext context,
  ComicSource source,
  SourceRepository repository,
  SourceCatalogEntry entry,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Switch to this copy?'.tl),
    content: Text(
      'The source "@name" is already installed at version @from from another repository. Switching replaces its script with version @to from @repo. Reading progress and finished chapters are kept; the source’s own settings and account will need setting up again, and favorites saved under the old implementation may no longer open.'
          .tlParams({
            'name': source.name,
            'from': source.version,
            'to': entry.version,
            'repo': repository.name,
          }),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text('Cancel'.tl),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text('Switch'.tl),
      ),
    ],
  ),
);

/// Finds [source] in [repository]'s catalog and confirms the relink.
Future<SourceCatalogEntry?> _confirmLink(
  BuildContext context,
  SourceRepositories store,
  SourceRepository repository,
  ComicSource source,
) async {
  try {
    final catalog = await store.load(repository);
    final entry = store.entryFor(source, catalog.entries);
    return entry;
  } on SourceFailure catch (failure) {
    if (context.mounted) {
      context.showMessage(message: sourceFailureMessage(failure));
    }
  } catch (error) {
    if (context.mounted) {
      context.showMessage(message: error.toString());
    }
  }
  return null;
}

class _SourceOriginPicker extends StatefulWidget {
  const _SourceOriginPicker({required this.source});
  final ComicSource source;
  @override
  State<_SourceOriginPicker> createState() => _SourceOriginPickerState();
}

class _SourceOriginPickerState extends SettingsSaveState<_SourceOriginPicker> {
  final store = SourceRepositories.instance;
  late final origin = store.originFor(widget.source.key);
  String? error;
  bool get busy => savingSettings || hasSettingsSaveError;
  Future<void> unlink() async {
    if (!acceptsSettingsChanges || busy || origin == null) return;
    final key = widget.source.key;
    final original = origin!;
    await saveSetting(
      'origin',
      () async {
        error = null;
        try {
          await store.unlink(key, original);
        } on SourceFailure catch (failure) {
          // A different link superseded this dialog; do not remove it.
          error = sourceFailureMessage(failure);
        } catch (failure) {
          error = sourceFailureMessage(failure);
          rethrow;
        }
      },
      onSaved: () {
        if (error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(leaveSettings());
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => protectSettings(
    SimpleDialog(
      title: Text('Manage source origin'.tl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            'Current origin: @origin'.tlParams({
              'origin': store.originLabel(widget.source.key),
            }),
          ),
        ),
        settingsSaveStatus,
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (origin?.kind == 'repository')
          SimpleDialogOption(
            onPressed: busy ? null : unlink,
            child: Text('Remove repository link'.tl),
          ),
        if (store.all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Add a repository in the Repositories tab first.'.tl),
          ),
        for (final repository in store.all)
          SimpleDialogOption(
            onPressed: busy ? null : () => Navigator.pop(context, repository),
            child: ListTile(
              dense: true,
              title: Text(repository.name),
              // One line only: the dialog is a picker, and a wrapped URL made
              // each choice tall enough to hide the rest of the list.
              subtitle: Text(
                repository.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        TextButton(
          onPressed: acceptsSettingsChanges ? leaveSettings : null,
          child: Text('Cancel'.tl),
        ),
      ],
    ),
  );
}

class SourceManagementEmptyState extends StatelessWidget {
  const SourceManagementEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      children: [
        Icon(
          icon,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(description, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// One repository, drawn as a card with its own update-check switch.
class _RepositoryCard extends StatelessWidget {
  const _RepositoryCard({
    required this.repository,
    required this.sourceCount,
    required this.onOpen,
    required this.onEdit,
    required this.onRemove,
    required this.onCopy,
    required this.onToggle,
  });

  final SourceRepository repository;
  final int sourceCount;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onCopy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = !repository.enabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Browsing a repository is the primary action, so the whole card is
          // the target; the switch and the menu keep their own hit areas.
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repository.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: disabled ? colors.outline : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@count sources'.tlParams({'count': '$sourceCount'}),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The linked count used to sit in its own circle beside the
                // switch, which is why it now lives under the name: three
                // trailing controls pushed the name into a very narrow column.
                Tooltip(
                  message: repository.enabled
                      ? 'Enabled'.tl
                      : 'This repository is disabled'.tl,
                  child: Switch(value: repository.enabled, onChanged: onToggle),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Repository actions'.tl,
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    if (action == 'edit') onEdit();
                    if (action == 'remove') onRemove();
                    if (action == 'copy') onCopy();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit repository'.tl),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy repository'.tl),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove repository'.tl),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
