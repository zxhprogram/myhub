// A single hot question, no prior probing: try several include/query/UA
// permutations to find one that returns answers.
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
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));
  const qid = '2073466638532358880'; // fresh: 大学生疯狂刷多段实习

  final includeA = 'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,annotation_action,annotation_detail,collapse_reason,collapsed_by,suggest_edit,comment_count,can_comment,content,editable_content,voteup_count,created_time,upvoted_followees,author.badge[?(type=best_answerer)].topics';
  final includeB = 'data[*].content,data[*].author.name,data[*].author.avatar_url,data[*].author.headline,data[*].voteup_count,data[*].comment_count,data[*].created_time,data[*].updated_time,data[*].excerpt';

  final tests = <(String, Map<String, String>, Map<String, dynamic>)>[
    ('v4 feeds offset webUA', {
      'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
      'Cookie': cookie,
    }, {'include': includeA, 'limit': 5, 'offset': 0, 'order': 'default', 'desktop': true}),
    ('v4 feeds offset webUA simple include', {
      'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
      'Cookie': cookie,
    }, {'include': includeB, 'limit': 5, 'offset': 0, 'order': 'default', 'desktop': true}),
    ('v4 feeds no desktop', {
      'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
      'Cookie': cookie,
    }, {'include': includeA, 'limit': 5, 'offset': 0, 'order': 'default'}),
    ('v4 feeds limit 20', {
      'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
      'Cookie': cookie,
    }, {'include': includeA, 'limit': 20, 'offset': 0, 'order': 'default', 'desktop': true}),
    ('app feeds appUA', {
      'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*',
      'Cookie': cookie,
    }, {'limit': 5, 'offset': 0}),
    ('app feeds appUA x-api', {
      'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*',
      'x-api-version': '3.0.91', 'Cookie': cookie,
    }, {'limit': 5, 'offset': 0}),
    ('web UA + app host', {
      'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
      'Cookie': cookie,
    }, {'limit': 5, 'offset': 0}),
  ];

  for (final (label, headers, query) in tests) {
    final isApp = label.startsWith('app') || (label == 'web UA + app host');
    final url = isApp
        ? 'https://api.zhihu.com/questions/$qid/feeds'
        : 'https://www.zhihu.com/api/v4/questions/$qid/feeds';
    print('===== $label =====');
    try {
      final res = await dio.get<dynamic>(url,
          queryParameters: query,
          options: Options(responseType: ResponseType.json, headers: headers));
      final map = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : Map<String, dynamic>.from(jsonDecode(res.data as String) as Map);
      final err = map['error'];
      if (err != null) { print('  error: ${err is Map ? err['message'] : err}'); continue; }
      final list = map['data'];
      if (list is List) {
        var usable = 0;
        for (final e in list) {
          if (e is! Map) continue;
          final node = e['target'] is Map ? e['target'] as Map : e;
          if (node['id'] != null) usable++;
        }
        print('  status ${res.statusCode} data len=${list.length} usable=$usable');
      } else {
        print('  status ${res.statusCode} data=${list.runtimeType}');
      }
    } catch (e) {
      print('  threw: $e');
    }
  }
}
