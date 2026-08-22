/// Subscription (profile URL) downloader for the Clash virtual app.
///
/// Ported from FlClash's `common/request.dart` + `Profile.update()`: fetch the
/// config behind a subscription URL with a Clash-family User-Agent so the
/// server returns Clash YAML rather than a base64 node list, then decode the
/// `subscription-userinfo` traffic header and the `content-disposition`
/// filename for display.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import '../models/clash_models.dart';

/// Raised when the download failed or the body is not a Clash config.
class ClashSubscriptionException implements Exception {
  const ClashSubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The result of one subscription download.
class ClashSubscriptionDownload {
  const ClashSubscriptionDownload({
    required this.config,
    this.subscriptionInfo,
    this.suggestedLabel,
  });

  /// Raw YAML config text.
  final String config;

  /// Decoded `subscription-userinfo` header, when present.
  final ClashSubscriptionInfo? subscriptionInfo;

  /// Filename extracted from `content-disposition`, when present.
  final String? suggestedLabel;
}

class ClashSubscriptionService {
  ClashSubscriptionService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // FlClash sends `FlClash/v.. clash-verge Platform/..` — the
              // `clash-verge` token is what subscription backends sniff to
              // pick the Clash YAML variant of the config.
              headers: {
                'User-Agent':
                    'NexusHub/v0.1.0 clash-verge Platform/${Platform.operatingSystem}',
              },
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.bytes,
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 300,
            ),
          );

  final Dio _dio;

  /// Downloads and sanity-checks the config behind [url].
  Future<ClashSubscriptionDownload> download(String url) async {
    Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(url);
    } on DioException catch (error) {
      throw ClashSubscriptionException(_describe(error));
    }

    final body = response.data ?? const <int>[];
    // Subscriptions are YAML (ASCII + the occasional UTF-8 name); malformed
    // bytes degrade to U+FFFD instead of throwing.
    final config = utf8.decode(body, allowMalformed: true);
    if (!_looksLikeClashConfig(config)) {
      throw const ClashSubscriptionException(
        '订阅返回的内容不是 Clash 配置，请确认链接支持 Clash 订阅',
      );
    }

    return ClashSubscriptionDownload(
      config: config,
      subscriptionInfo: ClashSubscriptionInfo.fromHeader(
        response.headers.value('subscription-userinfo'),
      ),
      suggestedLabel: clashLabelFromDisposition(
        response.headers.value('content-disposition'),
      ),
    );
  }

  /// FlClash validates the YAML inside the mihomo core; this app validates by
  /// applying the config to the core (`PUT /configs`), so the local check only
  /// rejects obvious non-config bodies (HTML error pages, base64 node lists).
  bool _looksLikeClashConfig(String config) {
    final text = config.trimLeft();
    if (text.isEmpty || text.startsWith('<')) return false;
    return config.contains('proxies:') || config.contains('proxy-providers:');
  }

  String _describe(DioException error) {
    final response = error.response;
    if (response != null) {
      return switch (response.statusCode) {
        401 || 403 => '订阅服务器拒绝访问（${response.statusCode}），链接可能已失效',
        404 => '订阅链接不存在（404）',
        _ => '订阅服务器返回 HTTP ${response.statusCode}',
      };
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => '下载订阅超时',
      DioExceptionType.connectionError => '无法连接订阅服务器',
      _ => '下载订阅失败：${error.message ?? error.type.name}',
    };
  }
}
