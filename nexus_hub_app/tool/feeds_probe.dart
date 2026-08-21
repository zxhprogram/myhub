// Tests alternative signed-in answer sources: the new feeds/{id}/answer_list
// shape and a hot-list question's recommended answers.
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

Future<void> main() async {
  final cookie = loadCookie();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  const qid = '2073421689262532035';

  final webJson = {
    'User-Agent': webUA, 'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'x-requested-with': 'fetch', 'Origin': 'https://www.zhihu.com',
    'Cookie': cookie,
  };
  final appJson = {'User-Agent': appUA, 'Accept': 'application/json, text/plain, */*', 'Cookie': cookie};

  final tests = <(String, String, Map<String, dynamic>, bool)>[
    ('new answer_list', 'https://www.zhihu.com/api/v4/feeds/$qid/answer_list',
     {'limit': 5, 'offset': 0}, false),
    ('new answer_list next', 'https://www.zhihu.com/api/v4/feeds/$qid/answer_list',
     {'limit': 20, 'cursor': '', 'offset': 0}, false),
    ('recommend answers', 'https://www.zhihu.com/api/v4/questions/$qid/recommend-answers',
     {'limit': 5, 'offset': 0}, false),
    ('app feeds', 'https://api.zhihu.com/questions/$qid/feeds',
     {'limit': 5, 'offset': 0}, true),
    ('app answer_list', 'https://api.zhihu.com/questions/$qid/answer_list',
     {'limit': 5, 'offset': 0}, true),
  ];

  for (final (label, url, query, isApp) in tests) {
    print('===== $label =====');
    try {
      final res = await dio.get<dynamic>(url,
          queryParameters: query,
          options: Options(responseType: ResponseType.json,
              headers: isApp ? appJson : webJson));
      print('status: ${res.statusCode}');
      final data = res.data;
      if (data is! Map && data is! String) { print('type: ${data.runtimeType}'); continue; }
      Map<String, dynamic> map;
      if (data is Map) map = Map<String, dynamic>.from(data);
      else { try { map = Map<String, dynamic>.from(jsonDecode(data) as Map); } catch (e) { print('not json'); continue; } }
      final err = map['error'];
      if (err != null) { print('error: ${err is Map ? err['message'] : err}'); continue; }
      final keys = map.keys.toList();
      print('keys: $keys');
      final list = map['data'];
      if (list is List) {
        print('data len: ${list.length}');
        var usable = 0;
        for (final e in list) {
          if (e is! Map) continue;
          final node = e['target'] is Map ? e['target'] as Map : e;
          if (node['id'] != null) usable++;
        }
        print('usable: $usable');
        if (list.isNotEmpty && list.first is Map) {
          print('first entry keys: ${(list.first as Map).keys.toList()}');
        }
      } else {
        print('data: ${list.runtimeType}');
      }
    } catch (e) {
      print('threw: $e');
    }
  }
}
