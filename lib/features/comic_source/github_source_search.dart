import 'dart:convert';

import 'package:dio/dio.dart';

import 'source_repositories.dart'
    show SourceCatalog, SourceCatalogEntry, SourceRepositories;

/// One GitHub repository that might publish Venera comic sources.
class GitHubSourceCandidate {
  const GitHubSourceCandidate({
    required this.fullName,
    required this.htmlUrl,
    required this.defaultBranch,
    required this.stars,
    required this.lastPushedAt,
    this.description = '',
  });

  /// `owner/name`, which is also what the search result shows.
  final String fullName;

  final String htmlUrl;
  final String defaultBranch;
  final int stars;

  /// When the repository last received a code push.
  ///
  /// This is the honest "is the author still working on it" signal: GitHub's
  /// `updated_at` also moves for issues and stars, so a stale repository can
  /// look freshly updated.
  final DateTime? lastPushedAt;

  final String description;

  /// The raw `index.json` a repository would publish as its source catalog.
  ///
  /// Probing this is the only reliable way to tell a real source repository
  /// from a project that merely mentions Venera in its description.
  String get catalogUrl =>
      'https://raw.githubusercontent.com/$fullName/$defaultBranch/index.json';

  /// The same catalog through jsDelivr, which keeps working when GitHub's raw
  /// host is unreachable and is what the bundled defaults use.
  String get cdnCatalogUrl =>
      'https://cdn.jsdelivr.net/gh/$fullName@$defaultBranch/index.json';

  /// A repository found by search, before anyone checked it publishes a catalog.
  static GitHubSourceCandidate? fromSearchItem(Object? value) {
    if (value is! Map) return null;
    final fullName = value['full_name'];
    if (fullName is! String || fullName.isEmpty) return null;
    final branch = value['default_branch'];
    // `pushed_at` is the last code push. `updated_at` also moves for issues and
    // stars, so it would make a stale repository look maintained.
    final pushed = value['pushed_at'];
    return GitHubSourceCandidate(
      fullName: fullName,
      htmlUrl: value['html_url'] is String ? value['html_url'] as String : '',
      defaultBranch: branch is String && branch.isNotEmpty ? branch : 'main',
      stars: value['stargazers_count'] is int
          ? value['stargazers_count'] as int
          : 0,
      lastPushedAt: pushed is String ? DateTime.tryParse(pushed) : null,
      description: value['description'] is String
          ? value['description'] as String
          : '',
    );
  }
}

/// Which half of discovery a progress report belongs to.
enum GitHubDiscoveryStage {
  /// Running the repository search queries.
  searching,

  /// Probing candidates for a published source catalog.
  verifying,
}

/// One progress report from [GitHubSourceSearch].
///
/// The two stages count different things, so they are reported separately: a
/// single shared counter restarted at zero when discovery moved from searching to
/// probing, which read as a stuck or resetting progress bar.
class GitHubDiscoveryProgress {
  const GitHubDiscoveryProgress({
    required this.stage,
    required this.done,
    required this.total,
  });

  final GitHubDiscoveryStage stage;
  final int done;
  final int total;
}

/// A candidate that answered with a usable source catalog.
class VerifiedSourceRepository {
  const VerifiedSourceRepository({
    required this.candidate,
    required this.catalogUrl,
    required this.entries,
  });

  final GitHubSourceCandidate candidate;

  /// The URL that actually answered, so it can be saved as-is.
  final String catalogUrl;

  /// Every installable source the catalog lists.
  ///
  /// The entries, not just their count: the point of the key-first view is that
  /// the same source turns up in several repositories, which cannot be seen from
  /// a number.
  final List<SourceCatalogEntry> entries;

  int get sourceCount => entries.length;

  /// JSON-safe form for the on-disk discovery cache.
  Map<String, dynamic> toJson() => {
    'repo': candidate.fullName,
    'html': candidate.htmlUrl,
    'branch': candidate.defaultBranch,
    'stars': candidate.stars,
    'pushedAt': candidate.lastPushedAt?.toIso8601String(),
    'description': candidate.description,
    'catalogUrl': catalogUrl,
    'entries': [
      for (final entry in entries)
        {
          'key': entry.key,
          'name': entry.name,
          'version': entry.version,
          'url': entry.url,
          'description': entry.description,
        },
    ],
  };

  static VerifiedSourceRepository? fromJson(Object? value) {
    if (value is! Map) return null;
    final repo = value['repo'];
    final catalogUrl = value['catalogUrl'];
    final entries = value['entries'];
    if (repo is! String || catalogUrl is! String || entries is! List) {
      return null;
    }
    final parsed = <SourceCatalogEntry>[];
    for (final raw in entries) {
      if (raw is! Map) continue;
      final key = raw['key'];
      final name = raw['name'];
      final version = raw['version'];
      final url = raw['url'];
      if (key is! String || name is! String || version is! String) continue;
      if (url is! String || url.isEmpty) continue;
      parsed.add(
        SourceCatalogEntry(
          key: key,
          name: name,
          version: version,
          url: url,
          description: raw['description']?.toString() ?? '',
        ),
      );
    }
    if (parsed.isEmpty) return null;
    final pushed = value['pushedAt'];
    return VerifiedSourceRepository(
      candidate: GitHubSourceCandidate(
        fullName: repo,
        htmlUrl: value['html'] is String ? value['html'] as String : '',
        defaultBranch: value['branch'] is String
            ? value['branch'] as String
            : 'main',
        stars: value['stars'] is int ? value['stars'] as int : 0,
        lastPushedAt: pushed is String ? DateTime.tryParse(pushed) : null,
        description: value['description']?.toString() ?? '',
      ),
      catalogUrl: catalogUrl,
      entries: parsed,
    );
  }
}

/// Searches GitHub for repositories that publish Venera comic sources.
///
/// Repository search needs no credentials; GitHub's code search does, which is
/// why discovery works from repository metadata and then verifies the catalog
/// rather than searching file contents.
class GitHubSourceSearch {
  GitHubSourceSearch({Dio? client}) : _client = client ?? _defaultClient();

  /// A client with bounded waits.
  ///
  /// Without timeouts a single stalled connection to GitHub or the raw host held
  /// the whole sweep open, which is what made discovery look like it had hung.
  /// Dio's defaults are no timeout at all, so a probe could wait indefinitely.
  static Dio _defaultClient() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 8),
    ),
  );

  final Dio _client;

  /// Candidates probed concurrently.
  ///
  /// Measured on a live sweep of 264 repositories: eight workers finished in
  /// about 103 seconds, and a single catalog request costs 0.5-4 s. The probes do
  /// not spend GitHub's API quota (`raw.githubusercontent.com` is served outside
  /// it), and a catalog is a few kilobytes, so a wider window is the only lever
  /// on wall time: 16 halves it again.
  static const _probeBatchSize = 16;

  /// Upper bound on probes per search, kept only as a runaway guard.
  ///
  /// Raised from 120 once the search stopped guessing by name: a single `venera`
  /// query yields 667 candidates, 264 of them recent, and 63 really publish a
  /// catalog. Capping at 120 hid the rest of them, so the cap now only exists to
  /// stop a runaway query, not to shape the result.
  static const maxProbes = 400;

  Future<List<GitHubSourceCandidate>> search(
    String query, {
    // GitHub bills a search by request, not by result, so a full page costs the
    // same as a third of one. The old default of 30 capped every query at 30
    // repositories, which is why a full sweep surfaced only a couple of dozen.
    int perPage = 100,
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final response = await _client.get<dynamic>(
      'https://api.github.com/search/repositories',
      queryParameters: {
        'q': trimmed,
        'sort': 'stars',
        'order': 'desc',
        'per_page': perPage,
        'page': page,
      },
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'VeneraQ',
        },
        // The body is JSON even on error; keep the status so a rate limit can be
        // reported as such instead of as a parse failure.
        validateStatus: (status) => status != null && status < 500,
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const GitHubSearchRateLimited();
    }
    if (response.statusCode != 200) {
      throw GitHubSearchFailed('HTTP ${response.statusCode}');
    }
    final body = response.data;
    final decoded = body is String ? jsonDecode(body) : body;
    if (decoded is! Map) throw const GitHubSearchFailed('Unexpected response');
    final items = decoded['items'];
    if (items is! List) return const [];
    return [
      for (final item in items) ?GitHubSourceCandidate.fromSearchItem(item),
    ];
  }

  /// Checks whether [candidate] publishes a usable catalog.
  ///
  /// The CDN is tried **first**, and that order is deliberate: the URL that
  /// answers becomes the repository address the app saves and the base every
  /// script URL is resolved against. Trying GitHub's raw host first therefore
  /// handed `raw.githubusercontent.com` URLs to the installer and to the saved
  /// repository, which is exactly what the bundled defaults avoid by shipping
  /// jsDelivr addresses — the raw host is unreachable on some networks, so an
  /// install that "resolved" would still fail to download.
  ///
  /// The cost is CDN freshness: jsDelivr serves a branch with some delay, so a
  /// catalog added minutes ago may not be there yet. The raw host is the
  /// fallback for that case, which keeps a brand-new catalog discoverable while
  /// leaving every normal hit on the CDN.
  ///
  /// Returns null when neither URL answers with a catalog listing at least one
  /// source.
  Future<VerifiedSourceRepository?> verify(
    GitHubSourceCandidate candidate, {
    CancelToken? cancelToken,
  }) async {
    for (final url in [candidate.cdnCatalogUrl, candidate.catalogUrl]) {
      final catalog = await _readCatalog(url, cancelToken: cancelToken);
      if (catalog != null && catalog.entries.isNotEmpty) {
        return VerifiedSourceRepository(
          candidate: candidate,
          catalogUrl: url,
          entries: catalog.entries,
        );
      }
    }
    return null;
  }

  /// Reads one catalog, or null when it is not a catalog at all.
  ///
  /// Parsed with the installer's own [SourceRepositories.parseCatalog], so an
  /// entry that appears here is one the source list would accept; a separate
  /// counter drifted from the installer's rules exactly once (versions with a
  /// suffix) and would have offered entries that could never install.
  Future<SourceCatalog?> _readCatalog(
    String url, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.get<dynamic>(
        url,
        options: Options(
          headers: const {'User-Agent': 'VeneraQ'},
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
        cancelToken: cancelToken,
      );
      if (response.statusCode != 200) return null;
      final body = response.data;
      if (body is! String) return null;
      return SourceRepositories.parseCatalog(body, baseUrl: url);
    } on DioException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      // SourceFailure from the parser: this candidate is simply not a catalog.
      return null;
    }
  }

  /// Queries tried in order when the user has not typed anything.
  ///
  /// One word, paged to the end. Measured on live results: the single query
  /// `venera` reaches 667 repositories, of which 264 were pushed in the last six
  /// months and 63 really publish a catalog this app can install.
  ///
  /// The earlier list added words to that query (`source`, `configs`, `EZvenera`,
  /// `VeneraNext sources`) because a name-shaped guess felt more precise. It was
  /// not: it surfaced 53 repositories and missed `Venerax`, `veneracopy`,
  /// `venera-huaman` and `venera-memhua`, none of which contain a word the list
  /// looked for. Every added word also costs a search request against GitHub's
  /// ten-per-minute anonymous budget. Adding words narrows; paging does not.
  static const defaultQuery = 'venera';

  /// Pages fetched for [defaultQuery].
  ///
  /// 100 results per page, so this covers the ~667 the query reaches. Each page
  /// costs one search request.
  static const defaultQueryPages = 7;

  /// How many search requests [discoverDefaults] makes, for the progress label.
  ///
  /// A request count, not a repository count: the label says how many searches
  /// are done, and it must equal what actually runs.
  static const defaultQueryCount = defaultQueryPages;

  /// Name fragments that usually mean "this is a source catalog".
  ///
  /// Used **only to order** the probe queue, never to drop a candidate. Ordering
  /// means the likely ones are probed first, so a sweep stops early once it has
  /// found enough; dropping would make a miss invisible, and a probe costs no API
  /// quota — only time.
  static const _likelyCatalog = ['source', 'sources', '源', 'configs', 'config'];

  /// How long a repository may go without a code push and still be offered.
  ///
  /// An abandoned catalog is not worth adding: its sites have usually changed
  /// or gone, so the sources fail on first use. Measured on live results, 180
  /// days removes two repositories and keeps 41 of the 43 that publish one.
  static const maxIdle = Duration(days: 180);

  /// Whether [candidate] was pushed recently enough to be worth offering.
  ///
  /// A repository with no push date is kept: the field is absent rather than
  /// old, and dropping it would hide a real catalog.
  static bool isRecent(GitHubSourceCandidate candidate) {
    final pushed = candidate.lastPushedAt;
    if (pushed == null) return true;
    return DateTime.now().difference(pushed) <= maxIdle;
  }

  /// Whether [candidate] is worth a request at all.
  ///
  /// Only the age filter remains. A name can neither prove nor disprove that a
  /// repository publishes a catalog: `Venerax`, `veneracopy`, `venera-huaman`
  /// and `venera-memhua` all carry one and contain no catalog word, while the
  /// exclusion list's fragments also caught real catalogs. Guessing by name was
  /// therefore dropped; whether a repository publishes a catalog is answered by
  /// reading it, which spends no API quota.
  static bool looksLikeCatalog(GitHubSourceCandidate candidate) =>
      isRecent(candidate);

  /// Rank used before probing: likely catalogs first, then by stars.
  static int _rank(GitHubSourceCandidate candidate) {
    final name = candidate.fullName.toLowerCase();
    final likely = _likelyCatalog.any(name.contains);
    // A likely name outranks any star count, since a popular project is often
    // the app itself; stars break ties inside each group.
    return (likely ? 1000000 : 0) + candidate.stars;
  }

  /// Searches and verifies, keeping only repositories that really publish a
  /// catalog. At most [maxProbes] candidates are checked.
  Future<List<VerifiedSourceRepository>> discover(
    String query, {
    CancelToken? cancelToken,
    void Function(GitHubDiscoveryProgress progress)? onProgress,
  }) async {
    final candidates = await search(query, cancelToken: cancelToken);
    return _verifyBest(
      candidates,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  /// Filters, ranks, then verifies candidates in small concurrent batches.
  ///
  /// A catalog request costs 0.5-4 s and the batches run concurrently, so wall
  /// time is dominated by how many candidates are probed. [enough] caps that
  /// work; it defaults to "everything that survived the age filter" because a
  /// partial sweep is indistinguishable from a complete one on screen. The
  /// reader has no way to tell that the oldest row shown is simply where the
  /// probing stopped, so the list silently under-reported the population.
  Future<List<VerifiedSourceRepository>> _verifyBest(
    Iterable<GitHubSourceCandidate> candidates, {
    CancelToken? cancelToken,
    void Function(GitHubDiscoveryProgress progress)? onProgress,
    int enough = maxProbes,
  }) async {
    final ranked = candidates.where(looksLikeCatalog).toList()
      ..sort((a, b) => _rank(b).compareTo(_rank(a)));
    final targets = ranked.take(maxProbes).toList();
    const batchSize = _probeBatchSize;
    final verified = <VerifiedSourceRepository>[];
    var done = 0;
    // Nothing to probe: report no verification progress at all rather than a
    // "0 of 0" line, which reads as a stuck counter.
    if (targets.isNotEmpty) {
      // Announce the size before the first batch returns: without this the label
      // had nothing to show until a whole batch had settled.
      onProgress?.call(
        GitHubDiscoveryProgress(
          stage: GitHubDiscoveryStage.verifying,
          done: done,
          total: targets.length,
        ),
      );
    }
    for (var start = 0; start < targets.length; start += batchSize) {
      if (cancelToken?.isCancelled ?? false) break;
      if (verified.length >= enough) break;
      final batch = targets.skip(start).take(batchSize);
      final results = await Future.wait([
        for (final candidate in batch)
          verify(candidate, cancelToken: cancelToken),
      ]);
      for (final result in results) {
        if (result != null) verified.add(result);
      }
      done += results.length;
      onProgress?.call(
        GitHubDiscoveryProgress(
          stage: GitHubDiscoveryStage.verifying,
          done: done,
          total: targets.length,
        ),
      );
    }
    return verified;
  }

  /// Discovery with no query to type: pages through [defaultQuery] and verifies
  /// every candidate that survives the age filter.
  ///
  /// Each page costs one search request; a rate limit ends the paging but keeps
  /// whatever was already found, because a partial list is still useful. [enough]
  /// exists for tests and for callers that deliberately want a sample; the
  /// default probes every recent candidate, since a truncated list looks exactly
  /// like a complete one once it is on screen.
  Future<List<VerifiedSourceRepository>> discoverDefaults({
    CancelToken? cancelToken,
    void Function(GitHubDiscoveryProgress progress)? onProgress,
    int enough = maxProbes,
  }) async {
    final seen = <String>{};
    final candidates = <GitHubSourceCandidate>[];
    var limited = false;
    // Report before each request, then once more after the last one: with
    // `done: index` the label started at "0 of 7" and never reached the end.
    for (var page = 1; page <= defaultQueryPages; page++) {
      if (cancelToken?.isCancelled ?? false) break;
      onProgress?.call(
        GitHubDiscoveryProgress(
          stage: GitHubDiscoveryStage.searching,
          done: page - 1,
          total: defaultQueryPages,
        ),
      );
      try {
        final found = await search(
          defaultQuery,
          page: page,
          cancelToken: cancelToken,
        );
        for (final candidate in found) {
          if (seen.add(candidate.fullName)) candidates.add(candidate);
        }
        // A short page is the last page; paging further only repeats the error.
        if (found.length < 100) break;
      } on GitHubSearchRateLimited {
        limited = true;
        break;
      }
    }
    onProgress?.call(
      GitHubDiscoveryProgress(
        stage: GitHubDiscoveryStage.searching,
        done: defaultQueryPages,
        total: defaultQueryPages,
      ),
    );
    if (candidates.isEmpty && limited) throw const GitHubSearchRateLimited();
    // Filtering and ranking happen before any request is spent, so the app and
    // its client builds never take a probe slot.
    final verified = await _verifyBest(
      candidates,
      cancelToken: cancelToken,
      onProgress: onProgress,
      enough: enough,
    );
    verified.sort((a, b) => b.candidate.stars.compareTo(a.candidate.stars));
    return verified;
  }

  void close() => _client.close();
}

class GitHubSearchRateLimited implements Exception {
  const GitHubSearchRateLimited();

  @override
  String toString() => 'GitHub search rate limit reached';
}

class GitHubSearchFailed implements Exception {
  const GitHubSearchFailed(this.message);

  final String message;

  @override
  String toString() => 'GitHub search failed: $message';
}
