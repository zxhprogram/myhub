/// Client for the mihomo (Clash.Meta) external controller REST API.
///
/// FlClash drives the Clash core through an in-process Go/Rust bridge; that
/// bridge cannot be embedded into this hub app, so the Clash virtual app
/// instead talks to a running core the same way the yacd / metacubexd
/// dashboards do: plain HTTP against the external controller.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/clash_models.dart';

/// Raised when the core answers with a non-2xx status or is unreachable.
class ClashApiException implements Exception {
  const ClashApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Snapshot + stream access to a running Clash core.
class ClashApiService {
  ClashApiService({
    required String host,
    required int port,
    String secret = '',
    Dio? dio,
  }) : _dio =
            dio ??
            Dio(
              BaseOptions(
                baseUrl: 'http://$host:$port',
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 8),
                // Cores commonly run with self-signed setups; never follow
                // redirects away from the loopback controller.
                followRedirects: false,
                validateStatus: (status) => status != null && status < 300,
              ),
            ) {
    if (secret.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $secret';
    }
  }

  final Dio _dio;

  /// Default URL used for latency tests (same as FlClash's default).
  static const defaultTestUrl = 'http://www.gstatic.com/generate_204';

  Options get _streamOptions =>
      Options(responseType: ResponseType.stream, receiveTimeout: null);

  Never _fail(DioException error) {
    final response = error.response;
    if (response != null) {
      final data = response.data;
      String message = 'HTTP ${response.statusCode}';
      if (data is Map<String, dynamic>) {
        final text = data['message'];
        if (text != null) message = text.toString();
      }
      throw ClashApiException(message);
    }
    throw ClashApiException(error.type.name);
  }

  Future<dynamic> _getJson(String path, {Object? query}) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: query is Map<String, dynamic> ? query : null,
      );
      return response.data;
    } on DioException catch (error) {
      _fail(error);
    }
  }

  // ---------------------------------------------------------------------
  // One-shot endpoints
  // ---------------------------------------------------------------------

  /// `GET /version`
  Future<ClashVersion> fetchVersion() async {
    final data = await _getJson('/version');
    if (data is Map<String, dynamic>) return ClashVersion.fromJson(data);
    throw const ClashApiException('无效的 /version 响应');
  }

  /// `GET /configs`
  Future<ClashRunningConfig> fetchConfigs() async {
    final data = await _getJson('/configs');
    if (data is Map<String, dynamic>) return ClashRunningConfig.fromJson(data);
    throw const ClashApiException('无效的 /configs 响应');
  }

  /// `PATCH /configs` — partial update, used for mode switching.
  Future<void> patchConfigs(Map<String, dynamic> payload) async {
    try {
      await _dio.patch<void>('/configs', data: payload);
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `PUT /configs?force=true` — replace the running config with [yaml].
  ///
  /// The controller parses and validates the payload with the same code path
  /// it uses for its own config file, so an invalid subscription answers with
  /// 400 and a descriptive message. This is this app's equivalent of
  /// FlClash's `coreController.setupConfig`, which cannot be used because the
  /// core runs in another process.
  Future<void> applyConfigPayload(String yaml) async {
    try {
      await _dio.put<void>(
        '/configs',
        queryParameters: {'force': 'true'},
        data: {'payload': yaml},
      );
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `GET /proxies` — every node and group, keyed by name.
  Future<Map<String, ClashProxy>> fetchProxies() async {
    final data = await _getJson('/proxies');
    if (data is! Map<String, dynamic>) {
      throw const ClashApiException('无效的 /proxies 响应');
    }
    final proxies = data['proxies'];
    if (proxies is! Map<String, dynamic>) {
      throw const ClashApiException('无效的 /proxies 响应');
    }
    return proxies.map(
      (name, value) => MapEntry(
        name,
        value is Map<String, dynamic>
            ? ClashProxy.fromJson(value)
            : ClashProxy(name: name, type: ''),
      ),
    );
  }

  /// `GET /rules`
  Future<List<ClashRule>> fetchRules() async {
    final data = await _getJson('/rules');
    if (data is! Map<String, dynamic>) return const [];
    final rules = data['rules'];
    if (rules is! List<dynamic>) return const [];
    return rules
        .map(
          (item) => item is Map<String, dynamic>
              ? ClashRule.fromJson(item)
              : null,
        )
        .whereType<ClashRule>()
        .toList();
  }

  /// `GET /connections`
  Future<ClashConnectionsSnapshot> fetchConnections() async {
    final data = await _getJson('/connections');
    if (data is Map<String, dynamic>) {
      return ClashConnectionsSnapshot.fromJson(data);
    }
    throw const ClashApiException('无效的 /connections 响应');
  }

  /// `GET /providers/proxies` — external proxy providers.
  Future<List<ClashProxyProvider>> fetchProxyProviders() async {
    final data = await _getJson('/providers/proxies');
    if (data is! Map<String, dynamic>) return const [];
    final providers = data['providers'];
    if (providers is! Map<String, dynamic>) return const [];
    return providers.values
        .map(
          (item) =>
              item is Map<String, dynamic>
                  ? ClashProxyProvider.fromJson(item)
                  : null,
        )
        .whereType<ClashProxyProvider>()
        .toList();
  }

  /// `PUT /providers/proxies/:name` — refresh one provider from its source.
  Future<void> updateProxyProvider(String name) async {
    try {
      await _dio.put<void>(
        '/providers/proxies/${Uri.encodeComponent(name)}',
      );
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `GET /providers/proxies/:name/healthcheck` — latency of every node in
  /// the provider (FlClash's provider health check action).
  Future<Map<String, int>> healthcheckProxyProvider(String name) async {
    try {
      final response = await _dio.get<dynamic>(
        '/providers/proxies/${Uri.encodeComponent(name)}/healthcheck',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data.map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        );
      }
      return const {};
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `GET /providers/rules` — external rule providers.
  Future<List<ClashRuleProvider>> fetchRuleProviders() async {
    final data = await _getJson('/providers/rules');
    if (data is! Map<String, dynamic>) return const [];
    final providers = data['providers'];
    if (providers is! Map<String, dynamic>) return const [];
    return providers.values
        .map(
          (item) =>
              item is Map<String, dynamic>
                  ? ClashRuleProvider.fromJson(item)
                  : null,
        )
        .whereType<ClashRuleProvider>()
        .toList();
  }

  /// `PUT /providers/rules/:name` — refresh one rule provider.
  Future<void> updateRuleProvider(String name) async {
    try {
      await _dio.put<void>(
        '/providers/rules/${Uri.encodeComponent(name)}',
      );
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `PUT /proxies/:group` — select the active node of a group.
  Future<void> selectProxy(String group, String name) async {
    try {
      await _dio.put<void>(
        '/proxies/${Uri.encodeComponent(group)}',
        data: {'name': name},
      );
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `GET /proxies/:name/delay` — returns the latency in ms, or -1 when the
  /// node timed out / errored (FlClash uses the same negative convention).
  Future<int> testDelay(
    String name, {
    String url = defaultTestUrl,
    int timeoutMillis = 5000,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/proxies/${Uri.encodeComponent(name)}/delay',
        queryParameters: {'timeout': timeoutMillis, 'url': url},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return (data['delay'] as num?)?.toInt() ?? -1;
      }
      return -1;
    } on DioException catch (error) {
      // A timeout is reported by the core as 408 with a message body; treat
      // every HTTP-level failure as "node unreachable" rather than crashing.
      if (error.response != null) return -1;
      if (error.type == DioExceptionType.cancel) rethrow;
      _fail(error);
    }
  }

  /// `DELETE /connections/:id`
  Future<void> closeConnection(String id) async {
    try {
      await _dio.delete<void>('/connections/${Uri.encodeComponent(id)}');
    } on DioException catch (error) {
      _fail(error);
    }
  }

  /// `DELETE /connections` — close every active connection.
  Future<void> closeAllConnections() async {
    try {
      await _dio.delete<void>('/connections');
    } on DioException catch (error) {
      _fail(error);
    }
  }

  // ---------------------------------------------------------------------
  // Chunked streaming endpoints
  // ---------------------------------------------------------------------

  /// `GET /traffic` — one `{"up": .., "down": ..}` JSON object per second.
  Stream<ClashTraffic> streamTraffic(CancelToken cancelToken) {
    return _streamJsonLines('/traffic', null, cancelToken).map(
      ClashTraffic.fromJson,
    );
  }

  /// `GET /memory` — one `{"inuse": ..}` JSON object per second (mihomo
  /// extension, FlClash's dashboard memory widget).
  Stream<int> streamMemory(CancelToken cancelToken) {
    return _streamJsonLines('/memory', null, cancelToken).map(
      (json) => (json['inuse'] as num?)?.toInt() ?? 0,
    );
  }

  /// `GET /logs?level=..` — one log line per JSON object.
  Stream<ClashLog> streamLogs(
    ClashLogLevel level,
    CancelToken cancelToken,
  ) {
    return _streamJsonLines(
      '/logs',
      {'level': level.value},
      cancelToken,
    ).map(ClashLog.fromJson);
  }

  /// Reads a chunked newline-delimited JSON endpoint into a stream of maps.
  ///
  /// The controller keeps the connection open and writes one JSON object per
  /// line; chunks may split lines arbitrarily, so lines are reassembled with
  /// a [LineSplitter] before decoding.
  Stream<Map<String, dynamic>> _streamJsonLines(
    String path,
    Map<String, dynamic>? query,
    CancelToken cancelToken,
  ) async* {
    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        path,
        queryParameters: query,
        options: _streamOptions,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) return;
      _fail(error);
    }
    final body = response.data;
    if (body == null) return;
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) yield decoded;
      } on FormatException {
        // Partial or malformed line — skip, the next line resyncs.
      }
    }
  }
}
