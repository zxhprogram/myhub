import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/services/image_cache_service.dart';
import 'package:nexus_hub_app/data/services/video_site_service.dart'
    show StateException;

void main() {
  late Directory baseDir;
  late HttpServer server;
  var hits = 0;

  setUpAll(() async {
    baseDir = Directory.systemTemp.createTempSync('nexus_image_cache_test');
    ImageCacheService.baseDirOverride = baseDir.path;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits++;
      request.response.write('not really an image but bytes are bytes');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close();
    baseDir.deleteSync(recursive: true);
  });

  test('downloads into <base>/cache and serves repeats without refetching',
      () async {
    final service = ImageCacheService.instance;
    final url = 'http://127.0.0.1:${server.port}/cover.jpg';
    final beforeHits = hits;

    final first = await service.getImage(url);
    final cacheDir = Directory('${baseDir.path}${Platform.pathSeparator}cache');
    expect(first.path.startsWith(cacheDir.path), isTrue);
    expect(first.existsSync(), isTrue);
    expect(first.readAsStringSync(), contains('bytes are bytes'));
    expect(hits, beforeHits + 1);

    // Second load of the same URL must come from disk, not the server.
    final second = await service.getImage(url);
    expect(second.path, first.path);
    expect(hits, beforeHits + 1);
  });

  test('concurrent requests for one URL download it only once', () async {
    final service = ImageCacheService.instance;
    final url = 'http://127.0.0.1:${server.port}/cover2.jpg';
    final beforeHits = hits;

    final results = await Future.wait([
      service.getImage(url),
      service.getImage(url),
      service.getImage(url),
    ]);
    expect(hits, beforeHits + 1);
    expect(results.map((f) => f.path).toSet().length, 1);
  });

  test('failed downloads are not cached and can be retried later', () async {
    final service = ImageCacheService.instance;
    final url = 'http://127.0.0.1:${server.port}/missing.jpg';
    // Take the server down so the first attempt fails...
    await server.close();
    try {
      await service.getImage(url);
      fail('download should have failed');
    } on StateException {
      // expected
    }
    expect(
      Directory('${baseDir.path}${Platform.pathSeparator}cache')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
      reason: 'a failed download must not leave partial files behind',
    );

    // ...bring the server back on the same port and verify a retry works.
    final revived = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    revived.listen((request) async {
      request.response.write('back online');
      await request.response.close();
    });
    addTearDown(() => revived.close());
    final file = await service.getImage('http://127.0.0.1:${server.port}/x.jpg');
    expect(file.existsSync(), isTrue);
  });

  test('empty responses are rejected, not cached', () async {
    final empty = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    empty.listen((request) async {
      await request.response.close();
    });
    addTearDown(() => empty.close());
    final service = ImageCacheService.instance;
    final url = 'http://127.0.0.1:${empty.port}/empty.jpg';
    try {
      await service.getImage(url);
      fail('empty download should have failed');
    } on StateException {
      // expected
    }
  });
}
