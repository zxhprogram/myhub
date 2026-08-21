// Batch: with the stored cookie, test several hot-list questions and the
// mobile app feeds fallback to find any that return answers.
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

Future<void> main() async {
  final cookie = loadCookie();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  final hot = await dio.get<dynamic>(
    'https://api.zhihu.com/topstory/hot-list',
    queryParameters: {'limit': 50},
    options: Options(
      responseType: ResponseType.json,
      headers: {'User-Agent': appUA},
    ),
  );
  final items = (hot.data as Map)['data'] as List;
  final qs = <(String, String)>[];
  for (final e in items) {
    final t = (e as Map)['target'] as Map;
    if (t['type'] == 'question') {
      qs.add(((t['id'] as num).toInt().toString(), t['title'].toString()));
    }
  }
  print('questions on hot list: ${qs.length}');

  for (final (qid, title) in qs) {
    // web v4 feeds with cookie
    final webRes = await dio.get<dynamic>(
      'https://www.zhihu.com/api/v4/questions/$qid/feeds',
      queryParameters: {
        'include': feedInclude, 'limit': 5, 'offset': 0,
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
    final webMap = Map<String, dynamic>.from(webRes.data as Map);
    final webErr = webMap['error'];
    final webList = webMap['data'];
    final webUsable = webList is List
        ? webList.where((e) => e is Map && (e['target'] is Map ? (e['target'] as Map)['id'] != null : e['id'] != null)).length
        : -1;
    // app feeds with cookie
    final appRes = await dio.get<dynamic>(
      'https://api.zhihu.com/questions/$qid/feeds',
      queryParameters: {'limit': 5, 'offset': 0},
      options: Options(
        responseType: ResponseType.json,
        headers: {'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*', 'Cookie': cookie},
      ),
    );
    final appMap = Map<String, dynamic>.from(appRes.data as Map);
    final appErr = appMap['error'];
    final appList = appMap['data'];
    final appUsable = appList is List
        ? appList.where((e) => e is Map && (e['target'] is Map ? (e['target'] as Map)['id'] != null : e['id'] != null)).length
        : -1;

    final ws = webErr != null ? 'ERR:${webErr is Map ? webErr['message'] : webErr}' : 'data=${webList is List ? webList.length : webList.runtimeType}/usable=$webUsable';
    final as_ = appErr != null ? 'ERR:${appErr is Map ? appErr['message'] : appErr}' : 'data=${appList is List ? appList.length : appList.runtimeType}/usable=$appUsable';
    print('q=$qid  web[$ws]  app[$as_]  ${title.substring(0, title.length > 18 ? 18 : title.length)}');
  }
}
