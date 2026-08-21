import 'dart:convert';
import 'package:dio/dio.dart';

const appUA =
    'osee2unifiedRelease/22.5.0 osee2unifiedReleaseVersion/10.42.0 '
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)';
const webUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';
const botUA =
    'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)';

const feedInclude =
    'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,'
    'annotation_action,annotation_detail,collapse_reason,collapsed_by,'
    'suggest_edit,comment_count,can_comment,content,editable_content,'
    'voteup_count,created_time,upvoted_followees,'
    'author.badge[?(type=best_answerer)].topics';

Future<void> main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
    validateStatus: (s) => s != null && s < 500,
  ));

  const qid = '4312592838';

  final tests = <(String, String, Map<String, dynamic>)>[
    // (label, url, query)
    ('web v4 feeds desktop', 'https://www.zhihu.com/api/v4/questions/$qid/feeds',
     {'include': feedInclude, 'limit': 5, 'offset': 0, 'order': 'default', 'desktop': true}),
    ('web v4 feeds no-desktop', 'https://www.zhihu.com/api/v4/questions/$qid/feeds',
     {'include': feedInclude, 'limit': 5, 'offset': 0, 'order': 'default'}),
    ('web v4 feeds order created', 'https://www.zhihu.com/api/v4/questions/$qid/feeds',
     {'include': feedInclude, 'limit': 5, 'offset': 0, 'order': 'created'}),
    ('web v3 question answers', 'https://www.zhihu.com/api/v3/question/$qid/answers',
     {'limit': 5, 'offset': 0, 'order': 'default'}),
    ('web v4 question answers', 'https://www.zhihu.com/api/v4/questions/$qid/answers',
     {'include': feedInclude, 'limit': 5, 'offset': 0}),
    ('app feeds', 'https://api.zhihu.com/questions/$qid/feeds',
     {'limit': 5, 'offset': 0}),
    ('app answers', 'https://api.zhihu.com/questions/$qid/answers',
     {'limit': 5, 'offset': 0}),
    ('app feeds x-api-version', 'https://api.zhihu.com/questions/$qid/feeds',
     {'limit': 5, 'offset': 0}),
    ('zhihu.com www no www', 'https://www.zhihu.com/question/$qid',
     {}),
  ];

  final headerSets = <(String, Map<String, String>)>[
    ('web', {
      'User-Agent': webUA,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch',
      'Origin': 'https://www.zhihu.com',
    }),
    ('web-no-xfetch', {
      'User-Agent': webUA,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
    }),
    ('app', {'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*'}),
    ('app+xapi', {'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*', 'x-api-version': '3.0.91'}),
    ('bot', {'User-Agent': botUA, 'Accept': 'text/html,application/xhtml+xml'}),
    ('web+xapi', {
      'User-Agent': webUA,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://www.zhihu.com/question/$qid',
      'x-requested-with': 'fetch',
      'x-api-version': '3.0.91',
    }),
  ];

  // Map each test to a header set.
  for (final (label, url, query) in tests) {
    final hdr = switch (label) {
      'app feeds x-api-version' => 'app+xapi',
      'web v4 feeds desktop' => 'web',
      'web v4 feeds no-desktop' => 'web',
      'web v4 feeds order created' => 'web',
      'web v3 question answers' => 'web',
      'web v4 question answers' => 'web',
      'zhihu.com www no www' => 'web-no-xfetch',
      _ => 'app',
    };
    final headers = headerSets.firstWhere((e) => e.$1 == hdr).$2;
    // For HTML page test, responseType plain; else json.
    final isHtml = label == 'zhihu.com www no www';
    final isApp = label.startsWith('app');
    final isBot = hdr == 'bot';
    if (isBot) {
      final botHeaders = headerSets.firstWhere((e) => e.$1 == 'bot').$2;
      print('===== $label (bot UA) =====');
      try {
        final res = await dio.get<String>(url,
            options: Options(responseType: ResponseType.plain, headers: botHeaders));
        print('  status: ${res.statusCode} html len: ${(res.data ?? '').length}');
        final html = res.data ?? '';
        final hasInitial = RegExp(r'js-initialData').hasMatch(html);
        final hasAnswer = RegExp(r'answer').hasMatch(html);
        print('  has js-initialData: $hasInitial, has answer text: $hasAnswer');
        if (html.length < 2000) print('  body: ${html.substring(0, html.length < 2000 ? html.length : 2000)}');
      } catch (e) {
        print('  threw: $e');
      }
      continue;
    }
    final isXapi = label == 'app feeds x-api-version';
    if (isXapi) {
      print('===== $label (app + x-api-version) =====');
      try {
        final res = await dio.get<dynamic>(url,
            queryParameters: query,
            options: Options(responseType: ResponseType.json,
                headers: headerSets.firstWhere((e) => e.$1 == 'app+xapi').$2));
        _show(res, label);
      } catch (e) { print('  threw: $e'); }
      continue;
    }
    print('===== $label ($hdr) =====');
    final headers2 = isHtml
        ? headerSets.firstWhere((e) => e.$1 == 'web-no-xfetch').$2
        : isApp
            ? headerSets.firstWhere((e) => e.$1 == 'app').$2
            : headerSets.firstWhere((e) => e.$1 == hdr).$2;
    try {
      final res = await dio.get<dynamic>(url,
          queryParameters: isHtml ? null : query,
          options: Options(responseType: isHtml ? ResponseType.plain : ResponseType.json,
              headers: headers2));
      if (isHtml) {
        final html = res.data?.toString() ?? '';
        print('  status: ${res.statusCode} html len: ${html.length}');
        final hasInitial = RegExp(r'js-initialData').hasMatch(html);
        print('  has js-initialData: $hasInitial');
        if (html.length < 2000) print('  body: ${html}');
      } else {
        _show(res, label);
      }
    } catch (e) {
      print('  threw: $e');
    }
  }
}

void _show(Response<dynamic> res, String label) {
  print('  status: ${res.statusCode}');
  final data = res.data;
  if (data is! Map && data is! String) {
    print('  data type: ${data.runtimeType}');
    return;
  }
  Map<String, dynamic> map;
  if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else {
    try {
      map = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (e) {
      print('  data is string but not JSON: ${(data as String).length > 200 ? (data as String).substring(0,200) : data}');
      return;
    }
  }
  final err = map['error'];
  if (err != null) {
    print('  error: ${err is Map ? err['message'] : err}');
    return;
  }
  final list = map['data'];
  print('  data key type: ${list.runtimeType}${list is List ? ' len=${list.length}' : ''}');
  if (list is List) {
    var usable = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final node = e['target'] is Map ? e['target'] as Map : e;
      if (node['id'] != null) usable++;
    }
    print('  usable answer nodes: $usable');
  }
  final paging = map['paging'];
  print('  paging: ${paging is Map ? jsonEncode(paging).substring(0, (jsonEncode(paging).length > 150 ? 150 : jsonEncode(paging).length)) : paging}');
}
