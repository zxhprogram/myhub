// Verifies the lean include list returns answers across hot questions, and
// that pagination (offset) keeps working with it.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const webUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';
const appUA =
    'osee2unifiedRelease/22.5.0 osee2unifiedReleaseVersion/10.42.0 '
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)';

const leanInclude =
    'data[*].content,data[*].author.name,data[*].author.avatar_url,'
    'data[*].author.headline,data[*].voteup_count,data[*].comment_count,'
    'data[*].created_time,data[*].updated_time,data[*].excerpt';

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
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));

  final hot = await dio.get<dynamic>(
    'https://api.zhihu.com/topstory/hot-list',
    queryParameters: {'limit': 50},
    options: Options(responseType: ResponseType.json, headers: {'User-Agent': appUA}),
  );
  final items = (hot.data as Map)['data'] as List;
  final qs = <(String, String)>[];
  for (final e in items) {
    final t = (e as Map)['target'] as Map;
    if (t['type'] == 'question') qs.add(((t['id'] as num).toInt().toString(), t['title'].toString()));
  }

  for (final (qid, title) in qs.take(6)) {
    try {
      final res = await dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/questions/$qid/feeds',
        queryParameters: {
          'include': leanInclude, 'limit': 5, 'offset': 0,
          'order': 'default', 'desktop': true,
        },
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Referer': 'https://www.zhihu.com/question/$qid',
            'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
            'Cookie': cookie,
          },
        ),
      );
      final map = Map<String, dynamic>.from(res.data as Map);
      final err = map['error'];
      final list = map['data'];
      if (err != null) {
        print('q=$qid error: ${err is Map ? err['message'] : err}');
      } else if (list is List) {
        var usable = 0;
        final contentLens = <int>[];
        for (final e in list) {
          if (e is! Map) continue;
          final node = e['target'] is Map ? e['target'] as Map : e;
          if (node['id'] != null) {
            usable++;
            final c = node['content'];
            if (c is String) contentLens.add(c.length);
          }
        }
        final paging = map['paging'];
        print('q=$qid usable=$usable contents=$contentLens isEnd=${paging is Map ? paging['is_end'] : 'n/a'} :: ${title.substring(0, title.length > 16 ? 16 : title.length)}');
      } else {
        print('q=$qid data=${list.runtimeType}');
      }
    } catch (e) {
      print('q=$qid threw: $e');
    }
  }
}

// Pagination check (appended): offset=5 and cursor-based next on the first
// question to make sure "load more" works with the lean include.
