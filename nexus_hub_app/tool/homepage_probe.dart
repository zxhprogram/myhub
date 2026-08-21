// With the stored cookie, scrape the server-rendered homepage feed and the
// hot question page HTML (different UA/referer patterns) to see if answers
// are available via SSR at all.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const webUA =
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

Future<void> main() async {
  final cookie = loadCookie();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  const qid = '2073421689262532035';
  const pageUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  final attempts = <(String, String, Map<String, String>)>[
    ('hot page desktop', 'https://www.zhihu.com/question/$qid', {
      'User-Agent': pageUA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cookie': cookie,
    }),
    ('hot page w/ referer', 'https://www.zhihu.com/question/$qid', {
      'User-Agent': pageUA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/',
      'Cookie': cookie,
    }),
    ('hot page x-requested-with', 'https://www.zhihu.com/question/$qid', {
      'User-Agent': pageUA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'x-requested-with': 'XMLHttpRequest',
      'Referer': 'https://www.zhihu.com/',
      'Cookie': cookie,
    }),
    ('homepage', 'https://www.zhihu.com/', {
      'User-Agent': pageUA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cookie': cookie,
    }),
  ];

  for (final (label, url, headers) in attempts) {
    print('===== $label =====');
    try {
      final res = await dio.get<String>(url,
          options: Options(responseType: ResponseType.plain, headers: headers));
      final html = res.data ?? '';
      print('status: ${res.statusCode} len: ${html.length}');
      final hasInitial = RegExp(r'js-initialData').hasMatch(html);
      print('has js-initialData: $hasInitial');
      if (hasInitial) {
        final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>').firstMatch(html);
        if (m != null) {
          final raw = m.group(1)!;
          print('initialData len: ${raw.length}');
          Map<String, dynamic> decoded;
          try {
            decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } catch (_) {
            decoded = Map<String, dynamic>.from(jsonDecode(raw
                .replaceAll('&quot;', '"').replaceAll('&#39;', "'")
                .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
                .replaceAll('&amp;', '&')) as Map);
          }
          final state = decoded['initialState'] is Map
              ? Map<String, dynamic>.from(decoded['initialState']! as Map)
              : const <String, dynamic>{};
          print('initialState keys: ${state.keys.toList()}');
          if (state.containsKey('question')) {
            final q = Map<String, dynamic>.from(state['question'] as Map);
            print('question title: ${q['title']}');
            final answers = q['answers'] ?? q['topAnswers'];
            print('answers type: ${answers.runtimeType}${answers is List ? ' len=${answers.length}' : ''}');
            if (answers is List && answers.isNotEmpty) {
              final a = answers.first as Map;
              print('first answer keys: ${a.keys.toList()}');
            }
          }
          if (state.containsKey('topstory')) {
            final topstory = Map<String, dynamic>.from(state['topstory'] as Map);
            print('topstory keys: ${topstory.keys.toList()}');
          }
        }
      } else if (html.length < 1200) {
        print('body: $html');
      }
    } catch (e) {
      print('threw: $e');
    }
  }
}
