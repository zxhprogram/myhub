// Dump the exact 200 empty-data response body for the hot question, plus
// the 404 body for a made-up question, to see what the app's parser sees.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const webUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

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
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  final res = await dio.get<dynamic>(
    'https://www.zhihu.com/api/v4/questions/$qid/feeds',
    queryParameters: {
      'include': feedInclude, 'limit': 5, 'offset': 0,
      'order': 'default', 'desktop': true,
    },
    options: Options(
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Referer': 'https://www.zhihu.com/question/$qid',
        'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
        'Cookie': cookie,
      },
    ),
  );
  print('status: ${res.statusCode}');
  final body = res.data?.toString() ?? '';
  print('body: $body');
  print('---');
  print('body len: ${body.length}');
}
