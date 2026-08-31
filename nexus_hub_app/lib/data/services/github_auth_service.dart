import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'proxy_dio_factory.dart';

/// GitHub OAuth authentication via the Device Authorization Grant
/// (a.k.a. Device Flow) — the OAuth variant designed for desktop apps
/// without a redirect endpoint: the app asks GitHub for a short user code,
/// the user opens github.com/login/device in a browser, types the code, and
/// the app polls GitHub until the authorization is granted or expires.
///
/// Unlike the browser-callback (authorization code) flow, device flow needs
/// only the Client ID — no client secret and no local HTTP server — which is
/// why it is the flow GitHub recommends for desktop applications.
class GitHubAuthService {
  GitHubAuthService._();

  /// Lazily-created shared client; built through [ProxyDioFactory] so the
  /// device-flow requests honor the system proxy (e.g. Clash) when enabled.
  Dio? _dioInstance;
  Future<Dio> get _dio async => _dioInstance ??= await ProxyDioFactory.instance();

  static const _tokenKey = 'nexus_github_access_token_v1';
  static const _deviceCodeEndpoint =
      'https://github.com/login/device/code';
  static const _tokenEndpoint = 'https://github.com/login/oauth/access_token';

  /// Scopes needed to read the signed-in user's profile, repositories and
  /// activity feed.
  static const _scopes = 'read:user user:email repo workflow read:org';

  /// Client ID of the Nexus Hub GitHub App. Device flow requires no secret;
  /// if you swap in another app, override via
  /// `--dart-define=GITHUB_OAUTH_CLIENT_ID=...`.
  static const kGitHubOAuthClientId =
      String.fromEnvironment(
        'GITHUB_OAUTH_CLIENT_ID',
        defaultValue: 'Ov23li6ytqmgHWrAgh21',
      );

  static final GitHubAuthService instance = GitHubAuthService._();

  Options get _jsonOptions => Options(headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });

  // ---------------------------------------------------------------------------
  // Persisted credentials
  // ---------------------------------------------------------------------------

  /// Returns the stored access token, or null when signed out.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _storeToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Signs the user out by removing the stored access token.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ---------------------------------------------------------------------------
  // Device flow
  // ---------------------------------------------------------------------------

  /// Step 1 of the device flow: request the device + user codes.
  ///
  /// Throws [DioException] on network errors and [GitHubAuthException] when
  /// GitHub rejects the request (e.g. bad client_id).
  Future<DeviceFlowStart> startDeviceFlow() async {
    final response = await (await _dio).post<Map<String, dynamic>>(
      _deviceCodeEndpoint,
      data: {'client_id': kGitHubOAuthClientId, 'scope': _scopes},
      options: _jsonOptions,
    );
    final data = response.data;
    if (data == null || data['device_code'] == null) {
      throw GitHubAuthException('GitHub did not return a device code.');
    }
    final error = data['error'] as String?;
    if (error != null) {
      throw GitHubAuthException(
        data['error_description'] as String? ?? error,
      );
    }
    return DeviceFlowStart(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUri:
          data['verification_uri'] as String? ?? 'https://github.com/login/device',
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
      expiresIn: Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 900),
    );
  }

  /// Step 2: single polling request. Repeat (spaced by [DeviceFlowStart
  /// .intervalSeconds], +5s after a slow_down) until the result is granted,
  /// expired, or the user gives up.
  Future<DeviceFlowPoll> pollForToken(String deviceCode) async {
    final response = await (await _dio).post<Map<String, dynamic>>(
      _tokenEndpoint,
      data: {
        'client_id': kGitHubOAuthClientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
      options: _jsonOptions,
    );
    final data = response.data ?? const {};
    final token = data['access_token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _storeToken(token);
      return const DeviceFlowPoll.granted();
    }
    final error = data['error'] as String?;
    switch (error) {
      case 'authorization_pending':
        return const DeviceFlowPoll.pending();
      case 'slow_down':
        return const DeviceFlowPoll.slowDown();
      case 'expired_token':
        throw GitHubAuthException('The device code expired. Please try again.');
      default:
        throw GitHubAuthException(
          data['error_description'] as String? ?? error ?? 'Unknown error.',
        );
    }
  }

  /// Manual token entry (e.g. a Personal Access Token) for users who prefer
  /// to skip the browser round-trip. The token is validated by the caller
  /// via the API service before being stored.
  Future<void> storeTokenManually(String token) => _storeToken(token.trim());
}

/// Result of the initial device-flow code request.
class DeviceFlowStart {
  const DeviceFlowStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.intervalSeconds,
    required this.expiresIn,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int intervalSeconds;
  final Duration expiresIn;
}

/// Result of one device-flow polling request.
class DeviceFlowPoll {
  const DeviceFlowPoll.pending()
      : granted = false,
        slowDown = false;
  const DeviceFlowPoll.slowDown()
      : granted = false,
        slowDown = true;
  const DeviceFlowPoll.granted()
      : granted = true,
        slowDown = false;

  final bool granted;
  final bool slowDown;
}

class GitHubAuthException implements Exception {
  const GitHubAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
