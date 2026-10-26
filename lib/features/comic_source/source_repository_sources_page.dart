import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';

import 'comic_source_manager.dart';
import 'github_source_search.dart';
import 'source_failure.dart';
import 'source_failure_presentation.dart';
import 'source_installation.dart';
import 'source_installation_widgets.dart';
import 'source_installations_scope.dart';
import 'source_repositories.dart';

/// The sources one repository publishes.
///
/// Repositories are the unit a reader browses: one list is one author's
/// catalog, so this page shows a single catalog instead of merging every copy
/// of a key from every repository. Choosing between copies is a choice the
/// reader makes by opening the repository that publishes the copy they want.
class SourceRepositorySourcesPage extends StatefulWidget {
  /// A repository the reader already saved.
  const SourceRepositorySourcesPage.saved(
    this.repository, {
    super.key,
    this.store,
    this.createClient,
  }) : discovered = null;

  /// A repository found on GitHub and not saved yet.
  const SourceRepositorySourcesPage.discovered(
    this.discovered, {
    super.key,
    this.store,
    this.createClient,
  }) : repository = null;

  final SourceRepository? repository;
  final VerifiedSourceRepository? discovered;
  final SourceRepositories? store;
  final Dio Function()? createClient;

  @override
  State<SourceRepositorySourcesPage> createState() =>
      _SourceRepositorySourcesPageState();
}

class _SourceRepositorySourcesPageState
    extends State<SourceRepositorySourcesPage> {
  SourceRepositories get _store => widget.store ?? SourceRepositories.instance;
  String get _title =>
      widget.repository?.name ?? widget.discovered!.candidate.fullName;

  SourceCatalog? _catalog;
  String? _error;
  bool _loading = false;
  SourceRepository? _saved;
  Future<SourceRepository>? _saving;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final discovered = widget.discovered;
    if (discovered == null) {
      unawaited(load());
    } else {
      // A verified GitHub repository already carries its catalog, so opening it
      // never waits on the network twice.
      _catalog = SourceCatalog(discovered.entries, const []);
      _saved = _matchingSaved(discovered);
    }
  }

  Future<void> load() async {
    final repository = widget.repository;
    if (repository == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _store.load(
        repository,
        createClient: widget.createClient,
      );
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = sourceFailureMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The saved repository that holds the same address, if the reader already
  /// added the GitHub hit before opening it.
  SourceRepository? _matchingSaved(VerifiedSourceRepository discovered) {
    final urls = _catalogUrls(discovered);
    for (final repository in _store.all) {
      if (urls.contains(repository.url)) return repository;
    }
    return null;
  }

  static Set<String> _catalogUrls(VerifiedSourceRepository repository) => {
    repository.catalogUrl,
    repository.candidate.cdnCatalogUrl,
  };

  /// The repository an install is attributed to.
  ///
  /// A GitHub hit has no repository id yet, so it is saved first: the install
  /// records its origin, and update checks need a saved repository to follow.
  Future<SourceRepository> _ensureRepository() async {
    final saved = widget.repository;
    if (saved != null) {
      final current = _store.find(saved.id);
      if (current == null) {
        throw const SourceFailure(SourceFailureCode.missingRepository);
      }
      return current;
    }
    final known = _saved;
    if (known != null && _store.find(known.id) != null) return known;
    final discovered = widget.discovered!;
    final existing = _matchingSaved(discovered);
    if (existing != null) {
      _saved = existing;
      return existing;
    }
    final started = _saving ??= _saveDiscovered(discovered);
    try {
      return await started;
    } catch (_) {
      if (identical(_saving, started)) _saving = null;
      rethrow;
    }
  }

  Future<SourceRepository> _saveDiscovered(
    VerifiedSourceRepository discovered,
  ) async {
    final repository = await _store.save(
      name: discovered.candidate.fullName,
      url: discovered.catalogUrl,
      // The verified catalog is already in hand; re-downloading it here would
      // fail on a repository that just answered, and would cost a round trip
      // before the install can start.
      catalogContents: jsonEncode([
        for (final entry in discovered.entries)
          {
            'key': entry.key,
            'name': entry.name,
            'version': entry.version,
            'url': entry.url,
            'description': entry.description,
          },
      ]),
    );
    if (mounted) setState(() => _saved = repository);
    return repository;
  }

  Future<void> _install(
    SourceCatalogEntry entry, {
    required bool hasInstalled,
  }) async {
    try {
      final repository = await _ensureRepository();
      if (!mounted) return;
      if (hasInstalled) {
        // Switching replaces a working source with another implementation of
        // the same key. Settings belong to the script that defined them, so the
        // reader has to know before, not after.
        await _showSwitchDialog(repository, entry);
        return;
      }
      _queue?.enqueueRepository(repository, entry);
    } catch (error) {
      if (mounted) context.showMessage(message: sourceFailureMessage(error));
    }
  }

  Future<void> _showSwitchDialog(
    SourceRepository repository,
    SourceCatalogEntry entry,
  ) async {
    final installed = ComicSourceManager().find(entry.key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Switch to this copy?'.tl),
        content: Text(
          'The source "@name" is already installed at version @from from another repository. Switching replaces its script with version @to from @repo. Reading progress and finished chapters are kept; the source’s own settings and account will need setting up again, and favorites saved under the old implementation may no longer open.'
              .tlParams({
                'name': installed?.name ?? entry.name,
                'from': installed?.version ?? '',
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
    if (confirmed != true || !mounted) return;
    try {
      // `replaceFromRepository` swaps the script and records the new origin, so
      // the update check follows the repository the copy came from.
      _queue?.replaceFromRepository(repository, entry);
    } catch (error) {
      if (mounted) context.showMessage(message: sourceFailureMessage(error));
    }
  }

  /// Installs are only offered where there is a queue to install into.
  SourceInstallations? get _queue => context
      .dependOnInheritedWidgetOfExactType<SourceInstallationsScope>()
      ?.queue;

  /// The copy this source is currently running, or null.
  bool _isCurrent(SourceCatalogEntry entry) =>
      ComicSourceManager().find(entry.key) != null &&
      _store.originFor(entry.key)?.url == entry.url;

  List<SourceCatalogEntry> _visible(List<SourceCatalogEntry> entries) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.key.toLowerCase().contains(query) ||
              entry.description.toLowerCase().contains(query),
        )
        .toList();
  }

  int get _uninstallableCount {
    final catalog = _catalog;
    if (catalog == null) return 0;
    return catalog.skipped.length + catalog.unsupported.length;
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return PopUpWidgetScaffold(
      title: _title,
      tailing: [SourceInstallationSummary(compact: true)],
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListenableBuilder(
              // The queue must be one of these: a row's "installing" spinner is
              // driven by task phases on the queue, so without it the page only
              // rebuilt when the registry changed — which happens at the very
              // end. The spinner therefore kept turning after the install had
              // already finished.
              listenable: Listenable.merge([
                _store,
                ComicSourceManager(),
                ?queue,
              ]),
              builder: (context, _) => _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final catalog = _catalog;
    final header = _header(context);
    final entries = catalog == null
        ? const <SourceCatalogEntry>[]
        : _visible(catalog.entries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (header != null) ...[header, const SizedBox(height: 10)],
        _controls(context),
        const SizedBox(height: 10),
        if (_error != null)
          _failure(context)
        else if (catalog == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Reading repository'.tl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else if (catalog.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No sources published.'.tl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No source matches the filter'.tl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else ...[
          for (final entry in entries) _entryCard(context, entry),
          if (_uninstallableCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '@count entries in this repository cannot be installed here.'
                    .tlParams({'count': _uninstallableCount}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// The GitHub facts a discovered repository adds, or null when there are
  /// none to show.
  ///
  /// A saved repository draws no header at all: its name is the page title, its
  /// address is an implementation detail nobody can act on here, and its source
  /// count moved beside the search field.
  Widget? _header(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final discovered = widget.discovered;
    if (discovered == null) return null;
    final saved = _saved ?? widget.repository;
    final updated = discovered.candidate.lastPushedAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.5),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(
                context,
                '@count stars'.tlParams({'count': discovered.candidate.stars}),
                icon: Icons.star_border,
              ),
              if (updated != null)
                _chip(
                  context,
                  'Updated @ago'.tlParams({'ago': _agoLabel(updated)}),
                  icon: Icons.schedule,
                ),
            ],
          ),
          if (discovered.candidate.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              discovered.candidate.description,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          if (saved != null)
            Text(
              'Saved as @name'.tlParams({'name': saved.name}),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _saving == null ? _saveOnly : null,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: Text('Add this repository'.tl),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  /// Saves the repository without installing anything, for a reader who wants
  /// to keep browsing it later.
  Future<void> _saveOnly() async {
    try {
      await _ensureRepository();
      if (mounted) context.showMessage(message: 'Repository saved.'.tl);
    } catch (error) {
      if (mounted) context.showMessage(message: sourceFailureMessage(error));
    }
  }

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final catalog = _catalog;
    // How many sources this repository publishes belongs beside the field that
    // narrows them, not in a header card of its own: it answers "how much is
    // in here", which is the question the search field is asked next.
    final count = catalog == null
        ? null
        : '@count sources'.tlParams({'count': catalog.entries.length});
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (text) => setState(() => _query = text),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search sources'.tl,
              isDense: true,
              filled: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minHeight: 36),
            ),
          ),
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              count,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
              maxLines: 1,
            ),
          ),
        if (widget.repository != null)
          IconButton(
            onPressed: _loading ? null : load,
            tooltip: 'Refresh list'.tl,
            icon: const Icon(Icons.refresh, size: 20),
          ),
      ],
    );
  }

  Widget _failure(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _loading ? null : load,
            child: Text('Retry'.tl),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(BuildContext context, SourceCatalogEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final queue = _queue;
    final installed = ComicSourceManager().find(entry.key);
    final task = queue?.taskFor(sourceKey: entry.key, url: entry.url);
    final current = _isCurrent(entry);
    final inFlight = task != null && (task.active || task.canRetry);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.5),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      entry.version,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // The key is what distinguishes two sources with the same
                    // name, so it is shown here rather than in a tooltip.
                    Flexible(
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.description,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (inFlight)
            Flexible(child: SourceInstallationStatus(task: task))
          else if (current)
            _chip(
              context,
              'In use'.tl,
              background: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
              icon: Icons.check,
            )
          else if (queue == null)
            // No installation owner in this build, so there is nothing to
            // install into; showing a dead button would be worse than showing
            // the entry without an action.
            const SizedBox.shrink()
          else
            FilledButton.tonal(
              onPressed: () => _install(entry, hasInstalled: installed != null),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                installed == null ? 'Install'.tl : 'Switch to this'.tl,
              ),
            ),
        ],
      ),
    );
  }

  /// "3 hours ago" style label, matching the discovery list.
  String _agoLabel(DateTime time) {
    final elapsed = DateTime.now().difference(time);
    if (elapsed.inMinutes < 1) return 'just now'.tl;
    if (elapsed.inHours < 1) {
      return '@count minutes ago'.tlParams({'count': elapsed.inMinutes});
    }
    if (elapsed.inDays < 1) {
      return '@count hours ago'.tlParams({'count': elapsed.inHours});
    }
    return '@count days ago'.tlParams({'count': elapsed.inDays});
  }

  Widget _chip(
    BuildContext context,
    String text, {
    Color? background,
    Color? foreground,
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final bg = background ?? colors.surfaceContainerHighest;
    final fg = foreground ?? colors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(fontSize: 11, color: fg)),
        ],
      ),
    );
  }
}
