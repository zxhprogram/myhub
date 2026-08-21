// Verifies that following paging.next (cursor) yields answers when the
// offset-based first request returns an empty data array.
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
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  Map<String, String> webHeaders({required String referer}) => {
        'User-Agent': webUA,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': referer,
        'x-requested-with': 'fetch',
        'Origin': 'https://www.zhihu.com',
        'Cookie': cookie,
      };

  // 1. First request with offset (the app's current call) - expect empty.
  print('===== request 1: offset=0 =====');
  Response<dynamic> res1 = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': feedInclude, 'limit': 5, 'offset': 0,
      'order': 'default', 'desktop': true,
    },
    options: Options(
      responseType: ResponseType.json,
      headers: webHeaders(referer: 'https://www.zhihu.com/question/$qid'),
    ),
  );
  var map = Map<String, dynamic>.from(res1.data as Map);
  print('status: ${res1.statusCode} data len: ${(map['data'] as List).length}');

  // 2. Follow paging.next with the cursor.
  final next = map['paging']['next'] as String;
  print('\n===== request 2: follow paging.next =====');
  var res2 = await dio.get<dynamic>(
    next,
    options: Options(
      responseType: ResponseType.json,
      headers: webHeaders(referer: 'https://www.zhihu.com/question/$qid'),
    ),
  );
  map = Map<String, dynamic>.from(res2.data as Map);
  final list = map['data'];
  print('status: ${res2.statusCode} data type: ${list.runtimeType}'
      '${list is List ? ' len=${list.length}' : ''}');
  if (list is List) {
    var usable = 0;
    final samples = <String>[];
    for (final e in list) {
      if (e is! Map) continue;
      final node = e['target'] is Map ? e['target'] as Map : e;
      if (node['id'] != null) usable++;
      final author = node['author'];
      samples.add(
        'id=${node['id']} author=${author is Map ? author['name'] : author}'
        ' content=${node['content'] is String ? 'str:${(node['content'] as String).length}' : node['content']?.runtimeType}',
      );
    }
    print('usable answers: $usable');
    for (final s in samples.take(3)) print('  $s');
  }
  final paging = map['paging'];
  print('paging: ${paging is Map ? jsonEncode(paging).substring(0, 200) : paging}');

  // 3. Also test with cursor passed directly to the base URL.
  final cursorUri = Uri.parse(next);
  final cursor = cursorUri.queryParameters['cursor'];
  print('\n===== request 3: cursor=$cursor via base endpoint =====');
  var res3 = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': feedInclude, 'limit': 5, 'offset': 0,
      'order': 'default', 'desktop': true, 'cursor': cursor,
    },
    options: Options(
      responseType: ResponseType.json,
      headers: webHeaders(referer: 'https://www.zhihu.com/question/$qid'),
    ),
  );
  map = Map<String, dynamic>.from(res3.data as Map);
  final list3 = map['data'];
  print('status: ${res3.statusCode} data len: ${list3 is List ? list3.length : list3}');
  var usable3 = 0;
  if (list3 is List) {
    for (final e in list3) {
      if (e is! Map) continue;
      final node = e['target'] is Map ? e['target'] as Map : e;
      if (node['id'] != null) usable3++;
    }
  }
  print('usable answers: $usable3');
}
