// Second-shot SSR dump: use a session_id query param and the feed endpoint's
// session to get the logged-in question page again, printing the answers
// structure only.
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

Future<void> main(List<String> args) async {
  final cookie = loadCookie();
  final qid = args.isNotEmpty ? args.first : '2073421689262532035';
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));

  final res = await dio.get<String>(
    'https://www.zhihu.com/question/$qid',
    queryParameters: {'session_id': '1787317238850112784', 'use_resume': 'true'},
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
  print('status: ${res.statusCode} len: ${html.length}');
  if (html.length < 1200) { print('body: $html'); return; }
  final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>')
      .firstMatch(html);
  if (m == null) { print('no js-initialData'); return; }
  final raw = m.group(1)!;
  Map<String, dynamic> decoded;
  try { decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map); }
  catch (_) {
    decoded = Map<String, dynamic>.from(jsonDecode(raw
        .replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')) as Map);
  }
  final state = decoded['initialState'] is Map
      ? Map<String, dynamic>.from(decoded['initialState']! as Map)
      : const <String, dynamic>{};
  print('answers type: ${state['answers'].runtimeType}');
  if (state['answers'] is Map) {
    final a = Map<String, dynamic>.from(state['answers'] as Map);
    print('answers keys: ${a.keys.toList()}');
    for (final k in a.keys.take(10)) {
      final v = a[k];
      if (v is Map) print('  $k: Map keys=${v.keys.take(12).toList()}');
      else if (v is List) print('  $k: List len=${v.length}');
      else print('  $k: ${v.runtimeType}');
    }
  } else if (state['answers'] is List) {
    print('answers list len: ${(state['answers'] as List).length}');
  }
  final question = state['question'];
  print('question type: ${question.runtimeType}');
  if (question is Map) {
    final q = Map<String, dynamic>.from(question);
    print('question keys: ${q.keys.take(30).toList()}');
  }
  final entities = state['entities'];
  if (entities is Map) {
    print('entities buckets: ${(entities as Map).keys.toList()}');
  }
}
