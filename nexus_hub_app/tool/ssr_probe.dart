import 'dart:convert';
import 'package:dio/dio.dart';

const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  for (final qid in ['2073421689262532035', '4312592838', '349097600']) {
    print('===== question $qid =====');
    try {
      final res = await dio.get<String>(
        'https://www.zhihu.com/question/$qid',
        options: Options(responseType: ResponseType.plain, headers: {
          'User-Agent': browserUserAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        }),
      );
      print('status: ${res.statusCode}');
      final html = res.data ?? '';
      print('html length: ${html.length}');
      final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>').firstMatch(html);
      if (m == null) {
        print('NO js-initialData block');
        continue;
      }
      final raw = m.group(1)!;
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
          continue;
        }
      }
      print('initialData top keys: ${decoded.keys.toList()}');
      final state = decoded['initialState'] is Map ? Map<String, dynamic>.from(decoded['initialState']! as Map) : const <String,dynamic>{};
      print('initialState keys: ${state.keys.toList()}');
      final question = state['question'] is Map ? Map<String, dynamic>.from(state['question']! as Map) : null;
      if (question != null) {
        print('question title: ${question['title']}');
        final topAnswers = question['answers'] ?? question['topAnswers'];
        print('question.answers type: ${topAnswers.runtimeType}');
        if (topAnswers is List) {
          print('topAnswers count: ${topAnswers.length}');
          for (final a in topAnswers.take(2)) {
            if (a is Map) {
              final content = a['content'];
              final author = a['author'];
              print('  answer id=${a['id']} author=${author is Map ? author['name'] : author} contentType=${content.runtimeType} contentLen=${content is String ? content.length : (content is List ? content.length : 'n/a')}');
            }
          }
        }
      } else {
        print('no question key in initialState');
        // dump some structure to see where answers live
        final feed = state['topstory'] is Map ? state['topstory'] : null;
        print('topstory present: ${feed != null}');
      }
    } catch (e) {
      print('threw: $e');
    }
  }
}
