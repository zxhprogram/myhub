import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/pub_package_model.dart';
import '../services/local_database.dart';

/// Service for fetching the newest published packages from the official
/// pub.dev packages API (`GET https://pub.dev/api/packages?page=N`,
/// sorted by publish time descending, 10 per page).
///
/// Page 1 is cached in a Hive box for 5 minutes and falls back to the mock
/// dataset when the remote API is unreachable, so the page always has content
/// to render. Deeper pages are always fetched live.
class PubDevService {
  PubDevService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _cacheKey = 'latest_packages';
  static const _cacheTtl = Duration(minutes: 5);
  static const _packagesPerPage = 10;
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Safari/537.36';

  /// Returns cached page-1 packages if fresh, otherwise fetches from the web.
  Future<List<PubPackage>> fetchLatest({int page = 1}) async {
    if (page == 1) {
      final cached = await _loadCached();
      if (cached != null) return cached;
      return _fetchAndCache(1);
    }
    return _fetchFromWeb(page);
  }

  /// Force-refresh page 1 from the web regardless of cache age.
  Future<List<PubPackage>> refreshLatest() async {
    return _fetchAndCache(1);
  }

  Future<List<PubPackage>> _fetchAndCache(int page) async {
    try {
      final packages = await _fetchFromWeb(page);
      await _cachePackages(packages);
      return packages;
    } catch (_) {
      // Network/parse failure — keep the UI alive with seed data.
      return mockPubPackages;
    }
  }

  Future<List<PubPackage>> _fetchFromWeb(int page) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://pub.dev/api/packages',
      queryParameters: {'page': page},
      options: Options(
        headers: {'User-Agent': _userAgent},
      ),
    );

    final list = response.data?['packages'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(PubPackage.fromJson)
        .where((p) => p.name.isNotEmpty)
        .toList();
  }

  /// True when the last full page was returned, hinting more pages exist.
  bool hasMorePages(List<PubPackage> pageItems) {
    return pageItems.length >= _packagesPerPage;
  }

  /// Fetches the full native-rendered detail for one package: metadata +
  /// all versions from the detail API, score metrics from the score API and
  /// the rendered README HTML from the pub.dev package page.
  Future<PubPackageDetail> fetchPackageDetail(String name) async {
    final detailFuture = _dio.get<Map<String, dynamic>>(
      'https://pub.dev/api/packages/$name',
      options: Options(
        headers: {'User-Agent': _userAgent},
      ),
    );
    final scoreFuture = _dio.get<Map<String, dynamic>>(
      'https://pub.dev/api/packages/$name/score',
      options: Options(
        headers: {'User-Agent': _userAgent},
      ),
    );
    // README never fails the whole detail — it degrades to empty content.
    final readmeFuture = fetchPackageReadme(name);

    final detailResponse = await detailFuture;
    final detailJson = detailResponse.data;
    if (detailJson == null) {
      throw DioException.connectionError(
        reason: 'Empty package detail response',
        requestOptions: detailResponse.requestOptions,
      );
    }
    final scoreResponse = await scoreFuture;
    final scoreJson = scoreResponse.data;
    final readmeHtml = await readmeFuture;
    return PubPackageDetail.fromApi(
      json: detailJson,
      score: scoreJson == null ? null : PubPackageScore.fromJson(scoreJson),
      readmeHtml: readmeHtml,
    );
  }

  /// Scrapes the pre-rendered README HTML from the pub.dev package page
  /// (pub.dev's public API does not expose the README). Returns an empty
  /// string when the page cannot be fetched or has no README section.
  Future<String> fetchPackageReadme(String name) async {
    try {
      final response = await _dio.get<String>(
        'https://pub.dev/packages/$name',
        options: Options(
          headers: {'User-Agent': _userAgent},
          // The whole HTML page is big; only the README section is kept.
          responseType: ResponseType.plain,
        ),
      );
      final page = response.data;
      if (page == null || page.isEmpty) return '';
      final document = html_parser.parse(page);
      final section = document.querySelector(
        'section.detail-tab-readme-content',
      );
      return section?.innerHtml.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<PubPackage>?> _loadCached() async {
    final box = await LocalDatabase.box('pub_dev');
    final raw = box.get(_cacheKey);
    if (raw == null) return null;

    final data = Map<String, dynamic>.from(raw as Map);
    final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - cachedAt > _cacheTtl.inMilliseconds) return null;

    final list = data['packages'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(PubPackage.fromCacheJson)
        .toList();
  }

  Future<void> _cachePackages(List<PubPackage> packages) async {
    final box = await LocalDatabase.box('pub_dev');
    await box.put(_cacheKey, {
      'cached_at': DateTime.now().millisecondsSinceEpoch,
      'packages': packages.map((p) => p.toCacheJson()).toList(),
    });
  }
}

/// Seed data used when the pub.dev API is unreachable.
final List<PubPackage> mockPubPackages = [
  const PubPackage(
    name: 'bloc_signals_jaspr',
    version: '1.0.1',
    description:
        'Jaspr web component integration and state binding for BlocSignal '
        'state containers.',
    topics: ['jaspr', 'signals', 'state-management'],
  ),
  const PubPackage(
    name: 'bloc_signals_flutter',
    version: '1.2.1',
    description:
        'Flutter extensions and bindings for the BlocSignal state management '
        'library.',
    topics: ['flutter', 'signals', 'state-management'],
  ),
  const PubPackage(
    name: 'solid_generator',
    version: '2.0.0+1',
    description: 'Solid source-to-lib code generator for Flutter reactive '
        'state.',
    topics: ['codegen', 'build-runner'],
  ),
  const PubPackage(
    name: 'device_safety_info',
    version: '1.5.1',
    description:
        'Device security toolkit: root/jailbreak, hook, and debugger '
        'detection plus related protections.',
    topics: ['security', 'root-detection'],
  ),
  const PubPackage(
    name: 'fhir_r6_validation',
    version: '0.9.0',
    description:
        'StructureDefinition-driven validation for FHIR R6 resources.',
    topics: ['fhir', 'healthcare'],
  ),
  const PubPackage(
    name: 'fhir_r6_mapping',
    version: '0.9.0',
    description: 'FHIR Mapping Language (FML) engine for FHIR R6.',
    topics: ['fhir', 'healthcare'],
  ),
  const PubPackage(
    name: 'fhir_r6_cql',
    version: '0.9.0',
    description:
        'FHIR R6 binding for the CQL engine (ModelResolver and '
        'TerminologyProvider).',
    topics: ['fhir', 'cql'],
  ),
  const PubPackage(
    name: 'fhir_r6_db',
    version: '0.9.0',
    description:
        'FHIR R6 database with SQLite/Drift backend and optional encryption.',
    topics: ['fhir', 'database'],
  ),
];
