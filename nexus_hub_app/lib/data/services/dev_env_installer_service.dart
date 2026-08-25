import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;

/// A selectable release of one language environment.
class EnvVersion {
  const EnvVersion({
    required this.label,
    this.wingetId,
    this.wingetVersion,
    this.downloadUrl,
  });

  /// Display label, e.g. `JDK 21` or `3.12`.
  final String label;

  /// winget package id used by the install step (null when delivered as a
  /// direct [downloadUrl] archive instead).
  final String? wingetId;

  /// Exact version passed as winget's `--version`; null installs latest.
  final String? wingetVersion;

  /// Direct archive URL (Flutter), extracted locally after download.
  final String? downloadUrl;
}

/// A language environment the assistant can install (Java, Go, ...).
class LanguageEnv {
  const LanguageEnv({
    required this.id,
    required this.name,
    required this.description,
    required this.components,
    required this.versions,
    this.detectExe,
    this.detectArgs = const [],
    this.versionPattern,
  });

  final String id;
  final String name;
  final String description;

  /// Human-readable summary of what gets installed (e.g. "JDK + Maven").
  final String components;

  /// Executable probed to detect an existing installation.
  final String? detectExe;
  final List<String> detectArgs;

  /// First capture group is the reported version string.
  final RegExp? versionPattern;

  /// Selectable releases offered in the UI.
  final List<EnvVersion> versions;
}

/// Install status of one environment, refreshed on demand.
enum EnvDetectStatus { checking, notInstalled, installed, unknown }

/// Detection result for one environment.
class EnvDetection {
  const EnvDetection({required this.status, this.version});

  final EnvDetectStatus status;

  /// Detected version string, e.g. `21.0.5` (null unless installed).
  final String? version;
}

/// Development-environment setup assistant.
///
/// Installs language toolchains on Windows via `winget` (falling back to
/// latest when a pinned version is unavailable) or direct archive downloads
/// (Flutter), then configures the relevant user environment variables
/// (JAVA_HOME, MAVEN_HOME, GOPATH, PATH additions) through PowerShell's
/// `[Environment]::SetEnvironmentVariable` so no admin rights are needed.
class DevEnvInstallerService {
  DevEnvInstallerService._();

  static final DevEnvInstallerService instance = DevEnvInstallerService._();

  /// All environments offered by the assistant. Not const because each env
  /// carries a [RegExp] used to parse its version output.
  static final List<LanguageEnv> environments = [
    LanguageEnv(
      id: 'java',
      name: 'Java',
      description: 'Java 开发工具链，含 JDK 与构建工具 Maven',
      components: 'JDK + Maven',
      detectExe: 'java',
      detectArgs: ['-version'],
      // java -version writes to stderr: openjdk version "21.0.5" ...
      versionPattern: RegExp(r'version "([^"]+)"'),
      versions: [
        EnvVersion(label: 'JDK 21（LTS）+ Maven', wingetId: 'Microsoft.OpenJDK.21'),
        EnvVersion(label: 'JDK 17（LTS）+ Maven', wingetId: 'Microsoft.OpenJDK.17'),
        EnvVersion(label: 'JDK 25 + Maven', wingetId: 'Microsoft.OpenJDK.25'),
      ],
    ),
    LanguageEnv(
      id: 'go',
      name: 'Go',
      description: 'Go 语言编译器与官方工具链',
      components: 'Go SDK',
      detectExe: 'go',
      detectArgs: ['version'],
      // go version go1.22.0 windows/amd64
      versionPattern: RegExp(r'go(\d+\.\d+(?:\.\d+)?)'),
      versions: [
        EnvVersion(label: '最新稳定版', wingetId: 'GoLang.Go'),
        EnvVersion(label: '1.24.4', wingetId: 'GoLang.Go', wingetVersion: '1.24.4'),
        EnvVersion(label: '1.23.10', wingetId: 'GoLang.Go', wingetVersion: '1.23.10'),
      ],
    ),
    LanguageEnv(
      id: 'rust',
      name: 'Rust',
      description: 'Rust 编译器与 Cargo 包管理器（经 rustup 安装）',
      components: 'rustup + rustc + cargo',
      detectExe: 'rustc',
      detectArgs: ['--version'],
      versionPattern: RegExp(r'rustc (\d+\.\d+(?:\.\d+)?)'),
      versions: [
        EnvVersion(
          label: 'stable（MSVC 工具链）',
          wingetId: 'Rustlang.Rustup',
        ),
      ],
    ),
    LanguageEnv(
      id: 'flutter',
      name: 'Flutter',
      description: 'Flutter SDK（需自行安装 Android Studio / VS Code 插件）',
      components: 'Flutter SDK（zip 解压安装）',
      detectExe: 'flutter',
      detectArgs: ['--version'],
      versionPattern: RegExp(r'Flutter (\d+\.\d+\.\d+)'),
      versions: [
        EnvVersion(
          label: '最新稳定版',
          downloadUrl:
              'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_v-stable.zip',
        ),
        EnvVersion(
          label: '3.27.4',
          downloadUrl:
              'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.27.4-stable.zip',
        ),
        EnvVersion(
          label: '3.24.5',
          downloadUrl:
              'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip',
        ),
      ],
    ),
    LanguageEnv(
      id: 'nodejs',
      name: 'Node.js',
      description: 'Node.js JavaScript 运行时与 npm 包管理器',
      components: 'Node.js + npm',
      detectExe: 'node',
      detectArgs: ['-v'],
      versionPattern: RegExp(r'v(\d+\.\d+\.\d+)'),
      versions: [
        EnvVersion(label: 'LTS 长期支持版', wingetId: 'OpenJS.NodeJS.LTS'),
        EnvVersion(label: 'Current 最新版', wingetId: 'OpenJS.NodeJS'),
      ],
    ),
    LanguageEnv(
      id: 'python',
      name: 'Python',
      description: 'Python 解释器、pip 与 py 启动器',
      components: 'Python + pip',
      detectExe: 'python',
      detectArgs: ['--version'],
      versionPattern: RegExp(r'Python (\d+\.\d+(?:\.\d+)?)'),
      versions: [
        EnvVersion(label: '3.13', wingetId: 'Python.Python.3.13'),
        EnvVersion(label: '3.12', wingetId: 'Python.Python.3.12'),
        EnvVersion(label: '3.11', wingetId: 'Python.Python.3.11'),
        EnvVersion(label: '3.10', wingetId: 'Python.Python.3.10'),
      ],
    ),
  ];

  bool get isSupported => !kIsWeb && Platform.isWindows;

  /// The process currently running an install, kept so it can be killed.
  Process? _activeProcess;

  /// Detects whether [env] is already installed and at which version.
  Future<EnvDetection> detect(LanguageEnv env) async {
    final exe = env.detectExe;
    if (!isSupported || exe == null) {
      return const EnvDetection(status: EnvDetectStatus.unknown);
    }
    try {
      final result = await Process.run(exe, env.detectArgs, runInShell: true)
          .timeout(const Duration(seconds: 20));
      final output =
          '${result.stdout}\n${result.stderr}'.trim();
      if (result.exitCode != 0 || output.isEmpty) {
        return const EnvDetection(status: EnvDetectStatus.notInstalled);
      }
      final match = env.versionPattern?.firstMatch(output);
      return EnvDetection(
        status: EnvDetectStatus.installed,
        version: match?.group(1),
      );
    } catch (_) {
      return const EnvDetection(status: EnvDetectStatus.notInstalled);
    }
  }

  /// Installs [version] of [env], streaming progress lines to [onLog].
  ///
  /// Throws when any mandatory step fails; environment-variable setup is
  /// best-effort and only logged on failure.
  Future<void> install({
    required LanguageEnv env,
    required EnvVersion version,
    required void Function(String line) onLog,
  }) async {
    if (!isSupported) {
      throw Exception('当前平台不支持自动安装，仅支持 Windows。');
    }
    onLog('=== 开始安装 ${env.name}（${version.label}）===');

    switch (env.id) {
      case 'java':
        await _winget(version.wingetId!, version.wingetVersion, onLog);
        await _winget('Apache.Maven', null, onLog);
        await _configureJava(onLog);
      case 'go':
        await _winget(version.wingetId!, version.wingetVersion, onLog);
        await _configureGo(onLog);
      case 'rust':
        await _winget(version.wingetId!, null, onLog);
        await _runStep(
          'rustup',
          ['default', 'stable-x86_64-pc-windows-msvc'],
          onLog,
          optional: true,
        );
        await _configureRust(onLog);
      case 'flutter':
        await _installFlutterZip(version.downloadUrl!, onLog);
        await _configureFlutter(onLog);
      case 'nodejs':
        await _winget(version.wingetId!, null, onLog);
        onLog('Node.js 安装程序已自动配置系统 PATH。');
      case 'python':
        await _winget(version.wingetId!, null, onLog);
        onLog('Python 安装程序已自动配置 PATH 与 py 启动器。');
      default:
        throw Exception('未知环境：${env.id}');
    }
    onLog('=== ${env.name} 环境安装完成，新开的终端即可使用 ===');
  }

  /// Kills the running install process, if any.
  void cancel() {
    _activeProcess?.kill();
    _activeProcess = null;
  }

  // ── Install backends ─────────────────────────────────────────────────────

  Future<void> _winget(
    String packageId,
    String? version,
    void Function(String) onLog,
  ) async {
    if (version != null) {
      final ok = await _wingetRun(packageId, version, onLog);
      if (ok) return;
      onLog('未找到 $packageId $version，回退为安装最新版…');
      await _wingetRun(packageId, null, onLog, failHard: true);
      return;
    }
    await _wingetRun(packageId, null, onLog, failHard: true);
  }

  /// Returns true when winget exited successfully.
  Future<bool> _wingetRun(
    String packageId,
    String? version,
    void Function(String) onLog, {
    bool failHard = false,
  }) async {
    final args = [
      'install',
      '--id',
      packageId,
      '--exact',
      '--silent',
      '--accept-package-agreements',
      '--accept-source-agreements',
      if (version != null) ...['--version', version],
    ];
    onLog('> winget ${args.join(' ')}');
    try {
      final result = await _spawn('winget', args, onLog);
      if (result == 0) {
        onLog('$packageId 安装成功。');
        return true;
      }
      onLog('winget 退出码 $result（$packageId）。');
    } catch (e) {
      onLog('调用 winget 失败：$e');
    }
    if (failHard) {
      throw Exception('winget 安装 $packageId 失败，请检查网络连接或手动安装。');
    }
    return false;
  }

  /// Downloads the Flutter release archive and extracts it under
  /// `%LOCALAPPDATA%\NexusHub\flutter`.
  Future<void> _installFlutterZip(
    String url,
    void Function(String) onLog,
  ) async {
    final targetRoot = Directory(
      p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'NexusHub'),
    );
    await targetRoot.create(recursive: true);
    final target = p.join(targetRoot.path, 'flutter');

    // The pinned "latest" URL carries a v placeholder; resolve the real
    // filename from Flutter's releases manifest first.
    var resolvedUrl = url;
    if (url.contains('_v-stable')) {
      onLog('正在查询最新稳定版本号…');
      try {
        final response = await Dio().get<Map<String, dynamic>>(
          'https://storage.googleapis.com/flutter_infra_release/'
          'releases/releases_windows.json',
        );
        final data = response.data ?? const {};
        final baseUrl = (data['base_url'] as String?) ??
            'https://storage.googleapis.com/flutter_infra_release/releases';
        final currentRelease = data['current_release'] as Map<String, dynamic>?;
        final stableHash = currentRelease?['stable'] as String?;
        final releases =
            (data['releases'] as List<dynamic>? ?? const []).whereType<Map>();
        String? archive;
        for (final release in releases) {
          if (release['hash'] == stableHash &&
              release['channel'] == 'stable') {
            archive = release['archive'] as String?;
            break;
          }
        }
        if (archive != null) {
          resolvedUrl = '$baseUrl/$archive';
          onLog('最新稳定版：${archive.split('/').last}');
        }
      } catch (e) {
        onLog('解析最新版本失败（$e），尝试默认地址…');
      }
    }

    final zipPath = p.join(Directory.systemTemp.path, 'flutter_sdk.zip');
    onLog('正在下载 Flutter SDK：$resolvedUrl');
    final dio = Dio();
    var lastPercent = -1;
    await dio.download(
      resolvedUrl,
      zipPath,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final percent = (received * 100 ~/ total);
        // Only log every ~5% so the console is not flooded by progress ticks.
        if (percent >= lastPercent + 5 || percent == 100) {
          lastPercent = percent;
          onLog('下载进度：$percent%');
        }
      },
    );

    onLog('正在解压到 $target …');
    await _spawn('tar', ['-xf', zipPath, '-C', targetRoot.path], onLog);
    await File(zipPath).delete().catchError((_) => File(zipPath));
    if (!Directory(target).existsSync()) {
      throw Exception('解压后未找到 Flutter 目录，安装中止。');
    }
    onLog('Flutter SDK 已就绪：$target');
  }

  // ── Environment variable configuration ───────────────────────────────────

  Future<void> _configureJava(void Function(String) onLog) async {
    final jdkDir = await _latestMatchingDir(
      [r'C:\Program Files\Microsoft', r'C:\Program Files\Eclipse Adoptium'],
      RegExp(r'^jdk-\d+'),
    );
    final mavenDir = await _latestMatchingDir(
      [r'C:\Program Files\Apache', r'C:\Program Files'],
      RegExp(r'^(apache-)?maven'),
    );
    if (jdkDir != null) {
      await _setUserEnvVar('JAVA_HOME', jdkDir, onLog);
      await _addToUserPath(p.join(jdkDir, 'bin'), onLog);
    } else {
      onLog('警告：未能定位 JDK 安装目录，跳过 JAVA_HOME 配置。');
    }
    if (mavenDir != null) {
      await _setUserEnvVar('MAVEN_HOME', mavenDir, onLog);
      await _addToUserPath(p.join(mavenDir, 'bin'), onLog);
    } else {
      onLog('警告：未能定位 Maven 安装目录，跳过 MAVEN_HOME 配置。');
    }
  }

  Future<void> _configureGo(void Function(String) onLog) async {
    final goPath = p.join(_homeDir(), 'go');
    await _setUserEnvVar('GOPATH', goPath, onLog);
    await _setUserEnvVar('GOBIN', p.join(goPath, 'bin'), onLog);
    await _addToUserPath(p.join(goPath, 'bin'), onLog);
  }

  Future<void> _configureRust(void Function(String) onLog) async {
    await _addToUserPath(p.join(_homeDir(), '.cargo', 'bin'), onLog);
  }

  Future<void> _configureFlutter(void Function(String) onLog) async {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? _homeDir();
    await _setUserEnvVar(
      'FLUTTER_ROOT',
      p.join(localAppData, 'NexusHub', 'flutter'),
      onLog,
    );
    await _addToUserPath(
      p.join(localAppData, 'NexusHub', 'flutter', 'bin'),
      onLog,
    );
  }

  String _homeDir() =>
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

  /// Sets a user-scope environment variable (no admin rights needed).
  Future<void> _setUserEnvVar(
    String name,
    String value,
    void Function(String) onLog,
  ) async {
    onLog('设置环境变量 $name=$value');
    final script =
        "[Environment]::SetEnvironmentVariable('$name', '$value', 'User')";
    final result = await _runPowerShell(script);
    if (result != 0) {
      onLog('警告：写入环境变量 $name 失败（退出码 $result）。');
    }
  }

  /// Appends [dir] to the user PATH unless it is already present.
  Future<void> _addToUserPath(String dir, void Function(String) onLog) async {
    final query = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', "[Environment]::GetEnvironmentVariable('Path','User')"],
      stdoutEncoding: Encoding.getByName('utf-8'),
      stderrEncoding: Encoding.getByName('utf-8'),
    );
    final current = query.stdout.toString().trim();
    final entries = current
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final normalized = dir.replaceAll('/', r'\').toLowerCase();
    if (entries.any((e) => e.replaceAll('/', r'\').toLowerCase() == normalized)) {
      onLog('PATH 已包含 $dir，跳过。');
      return;
    }
    entries.add(dir);
    final joined = entries.join(';');
    final escaped = joined.replaceAll("'", "''");
    onLog('将 $dir 追加到用户 PATH');
    final result = await _runPowerShell(
      "[Environment]::SetEnvironmentVariable('Path', '$escaped', 'User')",
    );
    if (result != 0) {
      onLog('警告：更新用户 PATH 失败（退出码 $result）。');
    }
  }

  Future<int> _runPowerShell(String script) async {
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-Command', script],
      stdoutEncoding: Encoding.getByName('utf-8'),
      stderrEncoding: Encoding.getByName('utf-8'),
    );
    return result.exitCode;
  }

  /// Newest direct child directory of any base whose name matches [pattern].
  Future<String?> _latestMatchingDir(
    List<String> bases,
    RegExp pattern,
  ) async {
    for (final base in bases) {
      final dir = Directory(base);
      if (!dir.existsSync()) continue;
      final candidates = dir
          .listSync()
          .whereType<Directory>()
          .where((d) => pattern.hasMatch(p.basename(d.path)))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (candidates.isNotEmpty) return candidates.first.path;
    }
    return null;
  }

  // ── Process plumbing ─────────────────────────────────────────────────────

  /// Runs [exe] streaming each output line to [onLog]; returns the exit code.
  Future<int> _spawn(
    String exe,
    List<String> args,
    void Function(String) onLog,
  ) async {
    final process = await Process.start(
      exe,
      args,
      runInShell: true,
      mode: ProcessStartMode.normal,
    );
    _activeProcess = process;
    try {
      final outputs = <Future<void>>[
        _pumpStream(process.stdout, onLog),
        _pumpStream(process.stderr, onLog),
      ];
      int code;
      try {
        code = await process.exitCode.timeout(const Duration(minutes: 30));
      } on TimeoutException {
        process.kill();
        rethrow;
      }
      await Future.wait(outputs);
      return code;
    } finally {
      _activeProcess = null;
    }
  }

  Future<void> _pumpStream(
    Stream<List<int>> stream,
    void Function(String) onLog,
  ) async {
    await stream
        .transform(systemEncoding.decoder)
        .listen((line) => onLog(line.trim()))
        .asFuture<void>();
  }

  /// Runs an optional post-install step; failures are logged, not thrown.
  Future<void> _runStep(
    String exe,
    List<String> args,
    void Function(String) onLog, {
    bool optional = false,
  }) async {
    onLog('> $exe ${args.join(' ')}');
    try {
      final result = await Process.run(exe, args, runInShell: true)
          .timeout(const Duration(minutes: 10));
      final output = '${result.stdout}${result.stderr}'.trim();
      if (output.isNotEmpty) onLog(output);
      if (result.exitCode != 0) {
        final message = '$exe 退出码 ${result.exitCode}';
        if (optional) {
          onLog('警告：$message（已忽略）。');
        } else {
          throw Exception(message);
        }
      }
    } on TimeoutException {
      final message = '$exe 执行超时';
      if (optional) {
        onLog('警告：$message（已忽略）。');
      } else {
        rethrow;
      }
    }
  }
}
