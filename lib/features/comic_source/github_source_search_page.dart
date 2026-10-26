import 'dart:async';

import 'package:dio/dio.dart' show CancelToken, DioException;
import 'package:flutter/material.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/foundation/translations.dart';

import 'github_discovery_cache.dart';
import 'github_source_search.dart';
import 'source_installation_widgets.dart';
import 'source_repositories.dart';
import 'source_repository_sources_page.dart';

/// GitHub discovery, organised the way sources are published: by repository.
///
/// The previous layout merged every copy of a source key across repositories,
/// which hid which repository a copy came from and made "add this repository"
/// a side action. Repositories are the unit a reader can save, update and
/// attribute a source to, so they are the unit listed here; the sources appear
/// one repository at a time, on [SourceRepositorySourcesPage].
class GitHubSourceSearchPage extends StatefulWidget {
  const GitHubSourceSearchPage({super.key, this.search, this.repositories});

  /// Injectable for tests; null means a real GitHub client.
  final GitHubSourceSearch? search;
  final SourceRepositories? repositories;

  @override
  State<GitHubSourceSearchPage> createState() => _GitHubSourceSearchPageState();
}

/// How the discovered repositories are ordered.
///
/// Both orders matter to readers: an actively maintained repository is a better
/// bet than a popular abandoned one, and stars are the only signal of how many
/// readers already trust it. Sorting by one uses the other to break ties.
enum _RepoSOrder { updated, stars }

class _GitHubSourceSearchPageState extends State<GitHubSourceSearchPage> {
  late final GitHubSourceSearch _search = widget.search ?? GitHubSourceSearch();
  SourceRepositories get _store =>
      widget.repositories ?? SourceRepositories.instance;

  /// Re-probing every catalog is slow, so a recent cache answers instantly and
  /// a background refresh is only started once the cache is a few hours old.
  static const _refreshAfter = Duration(hours: 6);

  List<VerifiedSourceRepository> _repositories = const [];
  bool _searching = false;
  bool _searched = false;
  bool _fromCache = false;
  String? _error;
  String _query = '';
  _RepoSOrder _order = _RepoSOrder.updated;
  GitHubDiscoveryProgress? _progress;
  DateTime? _cachedAt;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    // Only close a client this page created; an injected one belongs to its
    // owner, which may be reusing it after this page is gone.
    if (widget.search == null) _search.close();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await GitHubDiscoveryCache.read();
    if (!mounted) return;
    var fresh = false;
    if (cached != null && cached.isNotEmpty) {
      final savedAt = await GitHubDiscoveryCache.savedAt();
      if (!mounted) return;
      setState(() {
        _repositories = cached;
        _searched = true;
        _fromCache = true;
        _cachedAt = savedAt;
      });
      fresh =
          savedAt != null && DateTime.now().difference(savedAt) < _refreshAfter;
    }
    if (!fresh) unawaited(_discover());
  }

  Future<void> _discover() async {
    if (_searching) return;
    final cancel = _cancel = CancelToken();
    setState(() {
      _searching = true;
      _error = null;
      _progress = null;
    });
    try {
      final found = await _search.discoverDefaults(
        cancelToken: cancel,
        onProgress: (progress) {
          if (mounted && !cancel.isCancelled) {
            setState(() => _progress = progress);
          }
        },
      );
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _repositories = found;
        _searched = true;
        _fromCache = false;
        _cachedAt = DateTime.now();
      });
      // A failed write only costs the next launch a re-probe, so it must not
      // turn a successful discovery into an error screen.
      unawaited(GitHubDiscoveryCache.write(found));
    } on GitHubSearchRateLimited {
      _fail('GitHub is limiting requests. Wait a few minutes and try again.');
    } on GitHubSearchFailed catch (error) {
      _fail(error.message);
    } on DioException {
      _fail('Network error. Check the connection and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _progress = null;
        });
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  /// Repositories already saved under "Source repositories" are omitted: they
  /// have their own entry in source management, so listing them again here
  /// would offer a second, confusing way to open the same repository.
  List<VerifiedSourceRepository> get _visible {
    final savedUrls = {for (final repository in _store.all) repository.url};
    final query = _query.trim().toLowerCase();
    final visible = [
      for (final repository in _repositories)
        if (!_isSaved(repository, savedUrls) &&
            (query.isEmpty ||
                repository.candidate.fullName.toLowerCase().contains(query) ||
                repository.candidate.description.toLowerCase().contains(query)))
          repository,
    ];
    visible.sort(_compare);
    return visible;
  }

  static bool _isSaved(
    VerifiedSourceRepository repository,
    Set<String> savedUrls,
  ) =>
      savedUrls.contains(repository.catalogUrl) ||
      savedUrls.contains(repository.candidate.cdnCatalogUrl);

  /// How many discovered repositories survive the "already saved" filter.
  ///
  /// Counted without the search box: that box is transient, so folding it in
  /// would make the hidden count move as the reader types.
  int get _visibleCount {
    final savedUrls = {for (final repository in _store.all) repository.url};
    return _repositories
        .where((repository) => !_isSaved(repository, savedUrls))
        .length;
  }

  int _compare(VerifiedSourceRepository a, VerifiedSourceRepository b) {
    if (_order == _RepoSOrder.stars) {
      final byStars = b.candidate.stars.compareTo(a.candidate.stars);
      if (byStars != 0) return byStars;
      return _byRecency(a, b);
    }
    final byRecency = _byRecency(a, b);
    if (byRecency != 0) return byRecency;
    return b.candidate.stars.compareTo(a.candidate.stars);
  }

  /// Most recent push first; a repository with no push date sorts last because
  /// its activity cannot be verified.
  static int _byRecency(
    VerifiedSourceRepository a,
    VerifiedSourceRepository b,
  ) {
    final aTime = a.candidate.lastPushedAt;
    final bTime = b.candidate.lastPushedAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }

  Future<void> _open(VerifiedSourceRepository repository) async {
    await showPopUpWidget(
      context,
      SourceRepositorySourcesPage.discovered(repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: 'Find sources on GitHub'.tl,
      tailing: [SourceInstallationSummary(compact: true)],
      body: Column(
        children: [
          if (_searching)
            LinearProgressIndicator(
              minHeight: 2,
              value: _progress == null || _progress!.total <= 0
                  ? null
                  : _progress!.done / _progress!.total,
            ),
          Expanded(
            // Saving or removing a repository changes what may be listed here.
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) => _content(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
          'Sources come from repositories. Open a repository to browse its sources; add it only if you want to keep it.'
              .tl,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _summary(context),
        const SizedBox(height: 8),
        _controls(context),
        if (_error != null) ...[const SizedBox(height: 8), _failure(context)],
        const SizedBox(height: 8),
        if (_searching && !_searched && _error == null)
          const SizedBox.shrink()
        else if (_repositories.isEmpty)
          _hint(context, 'No repository with a source list found.'.tl)
        else if (visible.isEmpty)
          _hint(
            context,
            _query.trim().isEmpty
                ? 'All found repositories are already saved.'.tl
                : 'No repository matches the filter'.tl,
          )
        else
          for (final repository in visible)
            _repositoryCard(context, repository),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Only the repositories saved *and* found count as hidden here; comparing
    // the saved total against the found total would claim hidden rows that this
    // sweep never saw.
    final hidden = _repositories.length - _visibleCount;
    final found = _repositories.length;
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
          Text(
            '@count repositories found'.tlParams({'count': found}),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Tap a repository to browse its sources.'.tl,
            style: theme.textTheme.bodySmall,
          ),
          if (_searching && _progress != null) ...[
            const SizedBox(height: 4),
            Text(
              _progress!.stage == GitHubDiscoveryStage.searching
                  ? 'Searching repositories @done/@total'.tlParams({
                      'done': _progress!.done,
                      'total': _progress!.total,
                    })
                  : 'Checking catalogs @done/@total'.tlParams({
                      'done': _progress!.done,
                      'total': _progress!.total,
                    }),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
          ],
          if (_fromCache && _cachedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'From cache, saved @time'.tlParams({
                'time': _agoLabel(_cachedAt!),
              }),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
          ],
          if (hidden > 0) ...[
            const SizedBox(height: 4),
            Text(
              '@count already saved are hidden'.tlParams({'count': hidden}),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text('Recently updated'.tl),
              selected: _order == _RepoSOrder.updated,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _order = _RepoSOrder.updated),
            ),
            ChoiceChip(
              label: Text('Most stars'.tl),
              selected: _order == _RepoSOrder.stars,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _order = _RepoSOrder.stars),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (text) => setState(() => _query = text),
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search repositories'.tl,
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
            const SizedBox(width: 8),
            IconButton(
              onPressed: _searching ? null : _discover,
              tooltip: 'Refresh list'.tl,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
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
            onPressed: _searching ? null : _discover,
            child: Text('Retry'.tl),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Widget _repositoryCard(
    BuildContext context,
    VerifiedSourceRepository repository,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final candidate = repository.candidate;
    final updated = candidate.lastPushedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(repository),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.fullName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (candidate.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          candidate.description,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          _meta(
                            context,
                            '@count stars'.tlParams({'count': candidate.stars}),
                            icon: Icons.star_border,
                          ),
                          if (updated != null)
                            _meta(
                              context,
                              'Updated @ago'.tlParams({
                                'ago': _agoLabel(updated),
                              }),
                              icon: Icons.schedule,
                            ),
                          _meta(
                            context,
                            '@count sources'.tlParams({
                              'count': repository.entries.length,
                            }),
                            icon: Icons.auto_awesome_motion,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: colors.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, String text, {required IconData icon}) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.outline),
        const SizedBox(width: 3),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.outline),
        ),
      ],
    );
  }

  /// "3 hours ago" style label, shared with the repository page.
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
}
