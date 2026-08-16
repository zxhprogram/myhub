// Smoke check for VideoStreamRelay outside the Flutter UI: resolves a real
// episode, serves it through the relay and pulls the playlist plus one
// segment over the local HTTP endpoint.
//
// Run with: dart run tool/relay_smoke.dart

import 'dart:convert';
import 'dart:io';

import 'package:nexus_hub_app/data/services/video_site_service.dart';
import 'package:nexus_hub_app/data/services/video_stream_relay.dart';

Future<String> fetchText(String url) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close();
  final builder = StringBuffer();
  await for (final chunk in res.transform(utf8.decoder)) {
    builder.write(chunk);
  }
  client.close();
  return builder.toString();
}

Future<int> fetchBytes(String url) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close();
  var length = 0;
  await for (final chunk in res) {
    length += chunk.length;
  }
  client.close();
  return length;
}

Future<void> main() async {
  final service = VideoSiteService();

  for (final path in ['/vodplay/4631-5-1.html', '/vodplay/81579-4-1.html']) {
    stdout.writeln('===== $path =====');
    final info = await service.resolvePlay(playPath: path, episodeLabel: '1');
    stdout.writeln('stream host: ${Uri.parse(info.streamUrl).host}');

    final relay = VideoStreamRelay();
    final localUrl = await relay.serve(info.streamUrl);
    stdout.writeln('local url: $localUrl');

    final playlist = await fetchText(localUrl);
    final segMatches = RegExp('/segment\\?u=\\S+').allMatches(playlist);
    stdout.writeln(
      'playlist ok: ${playlist.startsWith('#EXTM3U')}, '
      'local segment links: ${segMatches.length}, '
      'extinf: ${RegExp('#EXTINF').allMatches(playlist).length}',
    );
    stdout.writeln(
      'head: ${playlist.split('\n').take(5).join(' | ')}',
    );

    final first = segMatches.first.group(0)!;
    final bytes = await fetchBytes(localUrl.replaceFirst('/index.m3u8', first));
    stdout.writeln('first segment via relay: $bytes bytes');
    await relay.stop();
  }
  exit(0);
}
