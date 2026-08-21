import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const webUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';
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
  const qid = '2073421689262532035';
  Map<String, String> headers() => {
        'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.zhihu.com/question/$qid',
        'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
        'Cookie': cookie,
      };
  int usable(dynamic list) {
    if (list is! List) return -1;
    var n = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final node = e['target'] is Map ? e['target'] as Map : e;
      if (node['id'] != null) n++;
    }
    return n;
  }

  for (final offset in [0, 5, 10]) {
    final res = await dio.get<dynamic>(
      'https://www.zhihu.com/api/v4/questions/$qid/feeds',
      queryParameters: {
        'include': leanInclude, 'limit': 5, 'offset': offset,
        'order': 'default', 'desktop': true,
      },
      options: Options(responseType: ResponseType.json, headers: headers()),
    );
    final map = Map<String, dynamic>.from(res.data as Map);
    final list = map['data'];
    final paging = map['paging'];
    print('offset=$offset: status=${res.statusCode} data=${list is List ? list.length : list.runtimeType} usable=${usable(list)} isEnd=${paging is Map ? paging['is_end'] : 'n/a'}');
  }

  // Cursor-based follow from offset=0 response.
  final r0 = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': leanInclude, 'limit': 5, 'offset': 0,
      'order': 'default', 'desktop': true,
    },
    options: Options(responseType: ResponseType.json, headers: headers()),
  );
  final next = ((r0.data as Map)['paging'] as Map)['next'] as String;
  final r2 = await dio.get<dynamic>(next,
      options: Options(responseType: ResponseType.json, headers: headers()));
  final m2 = Map<String, dynamic>.from(r2.data as Map);
  print('follow cursor: status=${r2.statusCode} data=${m2['data'] is List ? (m2['data'] as List).length : m2['data'].runtimeType} usable=${usable(m2['data'])} isEnd=${m2['paging'] is Map ? (m2['paging'] as Map)['is_end'] : 'n/a'}');
}
