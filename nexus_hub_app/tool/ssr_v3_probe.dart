import 'dart:convert';
import 'package:dio/dio.dart';

const webUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

Future<void> main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  const qid = '4312592838';
  final res = await dio.get<String>(
    'https://www.zhihu.com/api/v3/question/$qid/answers',
    queryParameters: {'limit': 5, 'offset': 0, 'order': 'default'},
    options: Options(responseType: ResponseType.plain, headers: {
      'User-Agent': webUA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
    }),
  );
  final html = res.data ?? '';
  print('status: ${res.statusCode} html len: ${html.length}');

  final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>').firstMatch(html);
  print('has js-initialData: ${m != null}');
  if (m == null) {
    print('---- first 1500 ----');
    print(html.substring(0, html.length < 1500 ? html.length : 1500));
    return;
  }
  final raw = m.group(1)!;
  print('initialData raw len: ${raw.length}');
  Map<String, dynamic> decoded;
  try {
    decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (e) {
    final un = raw
        .replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(un) as Map);
    } catch (e2) {
      print('json decode failed both ways: $e2');
      return;
    }
  }
  print('top keys: ${decoded.keys.toList()}');
  final state = decoded['initialState'] is Map
      ? Map<String, dynamic>.from(decoded['initialState']! as Map)
      : const <String, dynamic>{};
  print('initialState keys: ${state.keys.toList()}');
  final question = state['question'] is Map
      ? Map<String, dynamic>.from(state['question']! as Map)
      : null;
  if (question != null) {
    print('question title: ${question['title']}');
    for (final key in question.keys) {
      final v = question[key];
      if (v is List) print('  key $key: List len ${v.length}');
    }
    final topAnswers = question['answers'] ?? question['topAnswers'] ?? question['answerList'];
    print('answers key type: ${topAnswers.runtimeType}');
    if (topAnswers is List) {
      print('answer count: ${topAnswers.length}');
      for (final a in topAnswers.take(3)) {
        if (a is Map) {
          final content = a['content'];
          final author = a['author'];
          print('  answer id=${a['id']} author=${author is Map ? author['name'] : author} contentType=${content.runtimeType}');
        }
      }
    }
  }
}
