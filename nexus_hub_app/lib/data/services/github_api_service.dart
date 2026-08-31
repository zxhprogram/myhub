import 'package:dio/dio.dart';

import '../models/github_models.dart';
import '../services/github_auth_service.dart';
import '../services/proxy_dio_factory.dart';

/// Thin wrapper over the GitHub REST API v3 endpoints used by the GitHub
/// sub-app. Requests carry the OAuth access token from [GitHubAuthService];
/// a 401 response is surfaced as [GitHubAuthException] so callers can send
/// the user back through sign-in.
class GitHubApiService {
  /// Lazily-created shared client; built through [ProxyDioFactory] so API
  /// requests honor the system proxy (e.g. Clash) when enabled.
  Dio? _dioInstance;
  Future<Dio> get _dio async =>
      _dioInstance ??= await ProxyDioFactory.instance();

  static const _base = 'https://api.github.com';

  Future<Options> _options(String? token) async {
    return Options(
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
  }

  /// Validates a token by fetching the signed-in user. Used after device
  /// flow and for manual token entry. Throws on invalid/expired tokens.
  Future<GitHubUser> fetchAuthenticatedUser(String? token) async {
    final user = await _getJson<Map<String, dynamic>>(
      '/user',
      token,
      'fetch your profile',
    );
    return GitHubUser.fromJson(user);
  }

  /// Repositories the authenticated user owns, collaborates on, or has
  /// access to via org membership, sorted by last activity.
  Future<List<GitHubRepo>> fetchUserRepos(
    String? token, {
    String sort = 'updated',
    int perPage = 100,
  }) async {
    final list = await _getJson<List<dynamic>>(
      '/user/repos',
      token,
      'fetch your repositories',
      query: {
        'sort': sort,
        'direction': 'desc',
        'per_page': '$perPage',
        'affiliation': 'owner,collaborator,organization_member',
      },
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(GitHubRepo.fromJson)
        .toList();
  }

  /// Activity feed for the given user (private events included when the
  /// token belongs to that user).
  Future<List<GitHubEvent>> fetchUserEvents(
    String? token,
    String login, {
    int perPage = 60,
  }) async {
    final list = await _getJson<List<dynamic>>(
      '/users/$login/events',
      token,
      'fetch your activity',
      query: {'per_page': '$perPage'},
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(GitHubEvent.fromJson)
        .toList();
  }

  Future<T> _getJson<T>(
    String path,
    String? token,
    String actionLabel, {
    Map<String, String>? query,
  }) async {
    try {
      final response = await (await _dio).get<T>(
        '$_base$path',
        queryParameters: query,
        options: await _options(token),
      );
      return response.data as T;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const GitHubAuthException(
          'Your GitHub session has expired. Please sign in again.',
        );
      }
      if (e.response?.statusCode == 403 &&
          (e.response?.headers.value('x-ratelimit-remaining') == '0')) {
        throw GitHubAuthException(
          'GitHub API rate limit reached. Try again in a few minutes.',
        );
      }
      throw GitHubAuthException(
        'Failed to $actionLabel (${e.response?.statusCode ?? e.error}).',
      );
    }
  }
}
