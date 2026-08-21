import 'dart:convert';
import 'package:dio/dio.dart';

const appUserAgent =
    'osee2unifiedRelease/22.5.0 osee2unifiedReleaseVersion/10.42.0 '
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)';
const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (s) => s != null && s < 500,
  ));

  // Grab an article from the hot list.
  final hot = await dio.get<dynamic>(
    'https://api.zhihu.com/topstory/hot-list',
    queryParameters: {'limit': 50},
    options: Options(responseType: ResponseType.json, headers: {'User-Agent': appUserAgent}),
  );
  final items = (hot.data as Map)['data'] as List;
  final article = items.firstWhere((e) => (e as Map)['target']['type'] == 'article',
      orElse: () => items.first);
  final t = (article as Map)['target'] as Map;
  final aid = t['id'].toString();
  print('article id: $aid type: ${t['type']}');

  for (final (label, url, headers) in [
    ('web', 'https://www.zhihu.com/api/v4/articles/$aid', {
      'User-Agent': browserUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': 'https://zhuanlan.zhihu.com/p/$aid',
      'x-requested-with': 'fetch',
    }),
    ('app', 'https://api.zhihu.com/articles/$aid', {'User-Agent': appUserAgent}),
  ]) {
    print('----- $label: $url -----');
    try {
      final res = await dio.get<dynamic>(url, options: Options(responseType: ResponseType.json, headers: headers));
      print('status: ${res.statusCode}');
      final raw = res.data is String ? res.data : jsonEncode(res.data);
      print('raw (first 500): ${raw.length > 500 ? raw.substring(0, 500) : raw}');
      final map = res.data is Map ? Map<String, dynamic>.from(res.data as Map)
          : Map<String, dynamic>.from(jsonDecode(res.data as String) as Map);
      final err = map['error'];
      if (err != null) {
        print('error field: ${err is Map ? err['message'] : err}');
      } else {
        print('id=${map['id']} title=${map['title']} content len=${(map['content'] as String?)?.length}');
      }
    } catch (e) {
      print('threw: $e');
    }
  }
}
