// Reproduces fetchQuestionAnswers with the user's stored session cookie to
// see the logged-in response shape. The cookie jar lives in the app's
// shared_preferences.json on Windows.
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

const feedInclude =
    'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,'
    'annotation_action,annotation_detail,collapse_reason,collapsed_by,'
    'suggest_edit,comment_count,can_comment,content,editable_content,'
    'voteup_count,created_time,upvoted_followees,'
    'author.badge[?(type=best_answerer)].topics';

String loadCookie() {
  final home = Platform.environment['APPDATA'] ?? '';
  final path =
      '$home\\com.nexushub\\nexus_hub_app\\shared_preferences.json'
      .replaceAll('\\', Platform.pathSeparator);
  final data = jsonDecode(File(path).readAsStringSync()) as Map;
  final raw = data['flutter.nexus_zhihu_auth_v1'] as String? ?? '';
  if (raw.isEmpty) {
    stderr.writeln('no stored session');
    exit(2);
  }
  final decoded = jsonDecode(raw) as Map;
  final cookie = decoded['cookie'] as String? ?? '';
  // Redact to first 120 chars for logging.
  stderr.writeln('cookie len: ${cookie.length}, head: ${cookie.substring(0, cookie.length < 120 ? cookie.length : 120)}...');
  return cookie;
}

Future<void> main(List<String> args) async {
  final cookie = loadCookie();
  final qid = args.isNotEmpty ? args.first : '4312592838';
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  // Web v4 feeds with session cookie (primary source in the app).
  print('===== web v4 feeds (WITH cookie) q=$qid =====');
  try {
    final res = await dio.get<dynamic>(
      'https://www.zhihu.com/api/v4/questions/$qid/feeds',
      queryParameters: {
        'include': feedInclude,
        'limit': 5, 'offset': 0, 'order': 'default', 'desktop': true,
      },
      options: Options(responseType: ResponseType.json, headers: {
        'User-Agent': webUA,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.zhihu.com/question/$qid',
        'x-requested-with': 'fetch',
        'Origin': 'https://www.zhihu.com',
        'Cookie': cookie,
      }),
    );
    _analyze('web+cookie', res);
  } catch (e) {
    print('threw: $e');
  }

  // App feeds with session cookie (fallback source).
  print('===== app feeds (WITH cookie) q=$qid =====');
  try {
    final res = await dio.get<dynamic>(
      'https://api.zhihu.com/questions/$qid/feeds',
      queryParameters: {'limit': 5, 'offset': 0},
      options: Options(responseType: ResponseType.json, headers: {
        'User-Agent': appUA,
        'Accept': 'application/json, text/plain, */*',
        'Cookie': cookie,
      }),
    );
    _analyze('app+cookie', res);
  } catch (e) {
    print('threw: $e');
  }
}

void _analyze(String label, Response<dynamic> res) {
  print('status: ${res.statusCode}');
  final data = res.data;
  if (data is! Map && data is! String) {
    print('$label: data type ${data.runtimeType}');
    return;
  }
  Map<String, dynamic> map;
  if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else {
    try {
      map = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (e) {
      print('$label: string but not json: ${(data as String).length > 200 ? (data as String).substring(0, 200) : data}');
      return;
    }
  }
  final err = map['error'];
  if (err != null) {
    print('$label: error field ${err.runtimeType}: ${err is Map ? err['message'] : err}');
    return;
  }
  final list = map['data'];
  if (list is! List) {
    print('$label: data["data"] is ${list.runtimeType} -> branch: 回答数据解析失败');
    return;
  }
  print('$label: data["data"] List len ${list.length}');
  var usable = 0;
  final samples = <String>[];
  for (final e in list) {
    if (e is! Map) continue;
    final node = e['target'] is Map ? e['target'] as Map : e;
    final hasId = node['id'] != null;
    if (hasId) usable++;
    samples.add('id=${node['id']?.runtimeType} author=${(node['author'] is Map ? (node['author'] as Map)['name'] : node['author'])?.runtimeType} content=${(node['content'] is String ? 'str:${(node['content'] as String).length}' : node['content']?.runtimeType)}');
  }
  print('$label: usable=$usable');
  for (final s in samples.take(3)) print('  sample: $s');
  if (usable == 0) print('$label: -> branch: 回答数据解析失败 (empty)');
  final paging = map['paging'];
  print('$label: paging=${paging is Map ? jsonEncode(paging) : paging}');
}
