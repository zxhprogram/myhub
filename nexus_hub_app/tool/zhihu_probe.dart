// Probe: reproduce the app's exact question-answer loading flow against a
// live hot-list question id and report which parse branch fails and why.
//
// Run with: dart run tool/zhihu_probe.dart <questionId>
//
// This mirrors ZhihuService.fetchQuestionAnswers' two sources (web v4 feeds
// with browser headers, app feeds with iOS UA) without importing the Flutter
// service, so it runs under plain `dart run`.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

const appUserAgent =
    'osee2unifiedRelease/22.5.0 osee2unifiedReleaseVersion/10.42.0 '
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)';

const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

const feedInclude =
    'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,'
    'annotation_action,annotation_detail,collapse_reason,collapsed_by,'
    'suggest_edit,comment_count,can_comment,content,editable_content,'
    'voteup_count,created_time,upvoted_followees,'
    'author.badge[?(type=best_answerer)].topics';

Future<void> probeWeb(Dio dio, String qid) async {
  stdout.writeln('----- web: www.zhihu.com/api/v4/questions/$qid/feeds -----');
  try {
    final res = await dio.get<dynamic>(
      'https://www.zhihu.com/api/v4/questions/$qid/feeds',
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
          'User-Agent': browserUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Referer': 'https://www.zhihu.com/question/$qid',
          'x-requested-with': 'fetch',
        },
      ),
    );
    _report('web', res);
  } catch (e) {
    stdout.writeln('web request threw: $e');
  }
}

Future<void> probeApp(Dio dio, String qid) async {
  stdout.writeln('----- app: api.zhihu.com/questions/$qid/feeds -----');
  try {
    final res = await dio.get<dynamic>(
      'https://api.zhihu.com/questions/$qid/feeds',
      queryParameters: {'limit': 5, 'offset': 0},
      options: Options(
        responseType: ResponseType.json,
        headers: {'User-Agent': appUserAgent},
      ),
    );
    _report('app', res);
  } catch (e) {
    stdout.writeln('app request threw: $e');
  }
}

void _report(String label, Response<dynamic> res) {
  final status = res.statusCode;
  final data = res.data;
  stdout.writeln('status: $status');
  final raw = data is String ? data : jsonEncode(data);
  stdout.writeln('raw (first 600): ${raw.length > 600 ? raw.substring(0, 600) : raw}');
  stdout.writeln('raw length: ${raw.length}');
  _analyze(label, data);
}

void _analyze(String label, dynamic data) {
  Map<String, dynamic> map;
  if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else if (data is String) {
    map = Map<String, dynamic>.from(jsonDecode(data) as Map);
  } else {
    stdout.writeln('$label: data is neither Map nor String -> _asJsonMap would throw "接口返回的数据格式异常"');
    return;
  }
  final error = map['error'];
  stdout.writeln('$label: error field = ${error.runtimeType} -> ${error is Map ? error : error}');
  if (error is Map) {
    stdout.writeln('$label: _ensureNoApiError would throw: ${error['message']}');
    return;
  }
  if (error is String && error.isNotEmpty) {
    stdout.writeln('$label: _ensureNoApiError would throw: $error');
    return;
  }
  if (error != null) {
    stdout.writeln('$label: data["error"] != null (non-map/string) -> my new check throws "回答数据解析失败"');
    return;
  }
  final list = map['data'];
  if (list is! List) {
    stdout.writeln('$label: data["data"] is ${list.runtimeType} (not List) -> throws "回答数据解析失败"');
    return;
  }
  stdout.writeln('$label: data["data"] is List of length ${list.length}');
  var usable = 0;
  for (final entry in list) {
    if (entry is! Map) continue;
    final node = entry['target'] is Map ? entry['target'] as Map : entry;
    if (node['id'] != null) usable++;
  }
  stdout.writeln('$label: usable answer nodes (id present): $usable');
  if (usable == 0) stdout.writeln('$label: -> throws "回答数据解析失败" (empty answers, requested=5>0)');
  final paging = map['paging'];
  stdout.writeln('$label: paging = ${paging is Map ? jsonEncode(paging) : paging}');
}

Future<void> main(List<String> args) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  String qid;
  if (args.isNotEmpty) {
    qid = args.first;
  } else {
    // Pull the top hot-list question id, same as the app does.
    final hot = await dio.get<dynamic>(
      'https://api.zhihu.com/topstory/hot-list',
      queryParameters: {'limit': 10},
      options: Options(
        responseType: ResponseType.json,
        headers: {'User-Agent': appUserAgent},
      ),
    );
    final hotData = Map<String, dynamic>.from(hot.data as Map);
    final items = hotData['data'] as List;
    final firstQuestion = items.firstWhere(
      (e) => (e as Map)['target']['type'] == 'question',
    );
    qid = (firstQuestion['target']['id'] as num).toInt().toString();
    stdout.writeln('hot-list question id: $qid');
  }

  await probeWeb(dio, qid);
  await probeApp(dio, qid);
}
