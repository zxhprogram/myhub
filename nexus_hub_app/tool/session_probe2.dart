// Reproduces the app's answer/article loading with the user's stored session
// cookie against live hot-list ids, to see the logged-in response shape.
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
  final decoded = jsonDecode(raw) as Map;
  return decoded['cookie'] as String? ?? '';
}

Future<void> main(List<String> args) async {
  final cookie = loadCookie();
  stderr.writeln('cookie len: ${cookie.length}');
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
    options: Options(responseType: ResponseType.json, headers: {'User-Agent': appUA}),
  );
  final items = (hot.data as Map)['data'] as List;
  final qItem = items.firstWhere((e) => (e as Map)['target']['type'] == 'question');
  final aItem =
      items.where((e) => (e as Map)['target']['type'] == 'article').firstOrNull;
  final qid = (qItem['target']['id'] as num).toInt().toString();
  final aid = aItem == null ? null : (aItem['target']['id'] as num).toInt().toString();
  print('hot question: $qid (${qItem['target']['title']})');
  print('hot article:  $aid');

  for (final id in [qid, aid].whereType<String>()) {
    print('\n===== v4 feeds: $id (WITH cookie) =====');
    try {
      final res = await dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/questions/$id/feeds',
        queryParameters: {
          'include': feedInclude,
          'limit': 5,
          'offset': 0,
          'order': 'default',
          'desktop': true,
        },
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'User-Agent': webUA,
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Referer': 'https://www.zhihu.com/question/$id',
            'x-requested-with': 'fetch',
            'Origin': 'https://www.zhihu.com',
            'Cookie': cookie,
          },
        ),
      );
      _analyze('web v4 feeds', res);
    } catch (e) {
      print('threw: $e');
    }
    print('===== v4 articles: $id (WITH cookie) =====');
    try {
      final res = await dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/articles/$id',
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'User-Agent': webUA,
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Referer': 'https://zhuanlan.zhihu.com/p/$id',
            'x-requested-with': 'fetch',
            'Origin': 'https://www.zhihu.com',
            'Cookie': cookie,
          },
        ),
      );
      _analyze('web v4 article', res);
    } catch (e) {
      print('threw: $e');
    }
  }

  print('\n===== SSR question page: $qid (WITH cookie) =====');
  try {
    final res = await dio.get<String>(
      'https://www.zhihu.com/question/$qid',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': webUA,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Cookie': cookie,
        },
      ),
    );
    final html = res.data ?? '';
    print('status: ${res.statusCode} len: ${html.length}');
    final m = RegExp(r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>')
        .firstMatch(html);
    print('has js-initialData: ${m != null}');
    if (m != null) {
      final raw = m.group(1)!;
      Map<String, dynamic> decoded;
      try {
        decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        decoded = Map<String, dynamic>.from(
          jsonDecode(
            raw
                .replaceAll('&quot;', '"')
                .replaceAll('&#39;', "'")
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>')
                .replaceAll('&amp;', '&'),
          ) as Map,
        );
      }
      final state = decoded['initialState'] is Map
          ? Map<String, dynamic>.from(decoded['initialState']! as Map)
          : const <String, dynamic>{};
      print('initialState keys: ${state.keys.toList()}');
      final question = state['question'] is Map
          ? Map<String, dynamic>.from(state['question']! as Map)
          : null;
      if (question != null) {
        print('question title: ${question['title']}');
        final answers = question['answers'] ?? question['topAnswers'];
        print(
          'answers type: ${answers.runtimeType}'
          '${answers is List ? ' len=${answers.length}' : ''}',
        );
      }
    } else if (html.length < 1000) {
      print('body: $html');
    }
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
      print('$label: not json: ${(data as String).length > 200 ? (data as String).substring(0, 200) : data}');
      return;
    }
  }
  final err = map['error'];
  if (err != null) {
    print('$label: error ${err.runtimeType}: ${err is Map ? err['message'] : err}');
    return;
  }
  final list = map['data'];
  if (list is! List) {
    print('$label: data["data"] is ${list.runtimeType} -> 回答数据解析失败');
    return;
  }
  print('$label: List len ${list.length}');
  var usable = 0;
  for (final e in list) {
    if (e is! Map) continue;
    final node = e['target'] is Map ? e['target'] as Map : e;
    if (node['id'] != null) usable++;
  }
  print('$label: usable=$usable');
  if (usable == 0) print('$label: -> 回答数据解析失败 (empty)');
  final paging = map['paging'];
  print('$label: paging=${paging is Map ? jsonEncode(paging) : paging}');
}
