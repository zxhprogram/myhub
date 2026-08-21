// On a FRESH hot question (not previously probed), test whether cursor-based
// pagination (paging.next) returns answers while offset-based returns empty.
// This decides whether the fix is "follow the cursor" or "clearer error".
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
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  // Use a provided qid or pull a fresh one from the hot list.
  var qid = args.isNotEmpty ? args.first : '';
  if (qid.isEmpty) {
    final hot = await dio.get<dynamic>(
      'https://api.zhihu.com/topstory/hot-list',
      queryParameters: {'limit': 50},
      options: Options(responseType: ResponseType.json, headers: {'User-Agent': appUA}),
    );
    final items = (hot.data as Map)['data'] as List;
    final q = items.lastWhere((e) => (e as Map)['target']['type'] == 'question');
    qid = (q['target']['id'] as num).toInt().toString();
  }
  print('question: $qid');

  Map<String, String> webHeaders() => {
        'User-Agent': webUA,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.zhihu.com/question/$qid',
        'x-requested-with': 'fetch',
        'Origin': 'https://www.zhihu.com',
        'Cookie': cookie,
      };

  // Step 1: offset-based (the app's current call).
  final r1 = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': feedInclude, 'limit': 5, 'offset': 0,
      'order': 'default', 'desktop': true,
    },
    options: Options(responseType: ResponseType.json, headers: webHeaders()),
  );
  var map = Map<String, dynamic>.from(r1.data as Map);
  var list = map['data'];
  print('step1 offset=0: status=${r1.statusCode} data=${list is List ? 'len ${list.length}' : list.runtimeType}');
  final next = map['paging'] is Map ? (map['paging'] as Map)['next'] : null;
  print('step1 paging.next present: ${next != null} is_end=${map['paging'] is Map ? (map['paging'] as Map)['is_end'] : 'n/a'}');

  // Step 2: follow paging.next (cursor).
  if (next is String && next.isNotEmpty) {
    final r2 = await dio.get<dynamic>(
      next,
      options: Options(responseType: ResponseType.json, headers: webHeaders()),
    );
    map = Map<String, dynamic>.from(r2.data as Map);
    list = map['data'];
    var usable = 0;
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final node = e['target'] is Map ? e['target'] as Map : e;
        if (node['id'] != null) usable++;
      }
    }
    print('step2 follow cursor: status=${r2.statusCode} data=${list is List ? 'len ${list.length}' : list.runtimeType} usable=$usable');
  }

  // Step 3: order=created offset-based.
  final r3 = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': feedInclude, 'limit': 5, 'offset': 0,
      'order': 'created', 'desktop': true,
    },
    options: Options(responseType: ResponseType.json, headers: webHeaders()),
  );
  map = Map<String, dynamic>.from(r3.data as Map);
  list = map['data'];
  print('step3 order=created: status=${r3.statusCode} data=${list is List ? 'len ${list.length}' : list.runtimeType}');

  // Step 4: cursor on order=created.
  final next3 = map['paging'] is Map ? (map['paging'] as Map)['next'] : null;
  if (next3 is String && next3.isNotEmpty) {
    final r4 = await dio.get<dynamic>(
      next3,
      options: Options(responseType: ResponseType.json, headers: webHeaders()),
    );
    map = Map<String, dynamic>.from(r4.data as Map);
    list = map['data'];
    var usable = 0;
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final node = e['target'] is Map ? e['target'] as Map : e;
        if (node['id'] != null) usable++;
      }
    }
    print('step4 order=created cursor: status=${r4.statusCode} data=${list is List ? 'len ${list.length}' : list.runtimeType} usable=$usable');
  }
}
