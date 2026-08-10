import 'package:dio/dio.dart';

import '../models/trending_repo_model.dart';
import '../services/local_database.dart';

/// Service for fetching GitHub trending repositories from the public
/// githunt trending API.
///
/// Results are cached in a Hive box for 5 minutes and gracefully fall back to
/// the mock dataset when the remote API is unreachable, so the page always has
/// content to render.
class TrendingService {
  TrendingService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _cacheKey = 'trending_repos';
  static const _cacheTtl = Duration(minutes: 5);

  /// Returns cached trending repos if fresh, otherwise fetches from the web.
  Future<List<TrendingRepo>> fetchTrending() async {
    final cached = await _loadCached();
    if (cached != null) return cached;
    return _fetchAndCache();
  }

  /// Force-refresh from the web regardless of cache age.
  Future<List<TrendingRepo>> refreshTrending() async {
    return _fetchAndCache();
  }

  Future<List<TrendingRepo>> _fetchAndCache() async {
    try {
      final repos = await _fetchFromWeb();
      await _cacheRepos(repos);
      return repos;
    } catch (_) {
      // Network/parse failure — keep the UI alive with seed data.
      return mockTrendingRepos;
    }
  }

  Future<List<TrendingRepo>> _fetchFromWeb() async {
    final response = await _dio.get<List<dynamic>>(
      'https://api.githunt.com/repos/trending',
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/125.0.0.0 Safari/537.36',
        },
      ),
    );

    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(TrendingRepo.fromJson)
        .toList();
  }

  Future<List<TrendingRepo>?> _loadCached() async {
    final box = await LocalDatabase.box('trending_repos');
    final raw = box.get(_cacheKey);
    if (raw == null) return null;

    final data = Map<String, dynamic>.from(raw as Map);
    final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - cachedAt > _cacheTtl.inMilliseconds) return null;

    final list = data['repos'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(TrendingRepo.fromJson)
        .toList();
  }

  Future<void> _cacheRepos(List<TrendingRepo> repos) async {
    final box = await LocalDatabase.box('trending_repos');
    await box.put(_cacheKey, {
      'cached_at': DateTime.now().millisecondsSinceEpoch,
      'repos': repos.map((r) => r.toJson()).toList(),
    });
  }
}

/// Seed data used when the remote trending API is unreachable.
final List<TrendingRepo> mockTrendingRepos = [
  const TrendingRepo(
    author: '0xPlaygrounds',
    name: 'flow',
    description:
        'Browser based GSAP animation editor and experimentation sandbox.',
    language: 'TypeScript',
    languageColor: '#3178c6',
    stars: 1957,
    forks: 148,
    currentPeriodStars: 2634,
    url: 'https://github.com/0xPlaygrounds/flow',
  ),
  const TrendingRepo(
    author: 'unslothai',
    name: 'unsloth',
    description: 'Finetune Llama 3.3, DeepSeek R1 & Reasoning LLMs 2x faster '
        'with 70% less memory!',
    language: 'Python',
    languageColor: '#3572A5',
    stars: 44000,
    forks: 3000,
    currentPeriodStars: 3150,
    url: 'https://github.com/unslothai/unsloth',
  ),
  const TrendingRepo(
    author: 'langchain-ai',
    name: 'deep-research',
    description: 'AI agents that perform deep, multi-step research.',
    language: 'Jupyter Notebook',
    languageColor: '#DA5B0B',
    stars: 20800,
    forks: 2600,
    currentPeriodStars: 2160,
    url: 'https://github.com/langchain-ai/deep-research',
  ),
  const TrendingRepo(
    author: 'id-Software',
    name: 'DOOM',
    description: 'The id Software source code for DOOM (1993).',
    language: 'C',
    languageColor: '#555555',
    stars: 14500,
    forks: 2300,
    currentPeriodStars: 378,
    url: 'https://github.com/id-Software/DOOM',
  ),
  const TrendingRepo(
    author: 'microsoft',
    name: 'markitdown',
    description:
        'Python tool for converting files and office documents to Markdown.',
    language: 'Python',
    languageColor: '#3572A5',
    stars: 78800,
    forks: 4200,
    currentPeriodStars: 1234,
    url: 'https://github.com/microsoft/markitdown',
  ),
  const TrendingRepo(
    author: 'vesoft-inc',
    name: 'nebula',
    description: 'A distributed, fast open-source graph database featuring '
        'horizontal scalability and high availability.',
    language: 'C++',
    languageColor: '#f34b7d',
    stars: 11500,
    forks: 1150,
    currentPeriodStars: 95,
    url: 'https://github.com/vesoft-inc/nebula',
  ),
  const TrendingRepo(
    author: 'bytedance',
    name: 'monolith',
    description: 'A Lightweight Recommendation System.',
    language: 'Python',
    languageColor: '#3572A5',
    stars: 2100,
    forks: 210,
    currentPeriodStars: 189,
    url: 'https://github.com/bytedance/monolith',
  ),
  const TrendingRepo(
    author: 'openai',
    name: 'openai-realtime-console',
    description:
        'Realtime API Console App for speech-to-speech and function calling.',
    language: 'TypeScript',
    languageColor: '#3178c6',
    stars: 2600,
    forks: 890,
    currentPeriodStars: 92,
    url: 'https://github.com/openai/openai-realtime-console',
  ),
];