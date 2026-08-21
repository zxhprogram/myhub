// Dumps the SSR question page's initialState structure (answers, question,
// entities) to design a robust answer-fallback parser.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const pageUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

String loadCookie() {
  final home = Platform.environment['APPDATA'] ?? '';
  final sep = Platform.pathSeparator;
  final path = '$home${sep}com.nexushub${sep}nexus_hub_app'
      '${sep}shared_preferences.json';
  final data = jsonDecode(File(path).readAsStringSync()) as Map;
  final raw = data['flutter.nexus_zhihu_auth_v1'] as String? ?? '';
  return jsonDecode(raw)['cookie'] as String? ?? '';
}

Map<String, dynamic> decodeRaw(String raw) {
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return Map<String, dynamic>.from(jsonDecode(raw
        .replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')) as Map);
  }
}

Future<void> main(List<String> args) async {
  final cookie = loadCookie();
  final qid = args.isNotEmpty ? args.first : '2073421689262532035';
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  final res = await dio.get<String>(
    'https://www.zhihu.com/question/$qid',
    options: Options(
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': pageUA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cookie': cookie,
      },
    ),
  );
  final html = res.data ?? '';
  print('status: ${res.statusCode} html len: ${html.length}');
  final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>')
      .firstMatch(html);
  if (m == null) {
    print('no js-initialData');
    return;
  }
  final decoded = decodeRaw(m.group(1)!);
  final state = decoded['initialState'] is Map
      ? Map<String, dynamic>.from(decoded['initialState']! as Map)
      : const <String, dynamic>{};

  void dump(String key, int depth) {
    if (!state.containsKey(key)) {
      print('state.$key: MISSING');
      return;
    }
    final v = state[key];
    if (v is Map) {
      print('state.$key: Map with ${v.length} keys: ${v.keys.take(20).toList()}');
      if (depth > 0) {
        for (final k in v.keys.take(5)) {
          final sub = v[k];
          if (sub is Map) {
            print('  $key.$k: Map keys=${sub.keys.take(15).toList()}');
          } else if (sub is List) {
            print('  $key.$k: List len=${sub.length}');
          } else {
            print('  $key.$k: ${sub.runtimeType} = ${sub}'.substring(0, 120));
          }
        }
      }
    } else if (v is List) {
      print('state.$key: List len=${v.length}');
      if (v.isNotEmpty) {
        final first = v.first;
        if (first is Map) {
          print('  first keys: ${first.keys.toList()}');
        }
      }
    } else {
      print('state.$key: ${v.runtimeType} = ${v}'.substring(0, 120));
    }
  }

  dump('answers', 2);
  dump('question', 2);
  dump('entities', 0);
  final entities = state['entities'] is Map
      ? Map<String, dynamic>.from(state['entities']! as Map)
      : const <String, dynamic>{};
  print('entities keys: ${entities.keys.toList()}');
  for (final k in entities.keys.take(10)) {
    final bucket = entities[k];
    if (bucket is Map) {
      print('  entities.$k: ${bucket.length} entries, sample keys: ${bucket.keys.take(5).toList()}');
    }
  }
}
