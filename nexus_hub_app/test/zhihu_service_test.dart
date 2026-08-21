import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexus_hub_app/data/services/local_database.dart';
import 'package:nexus_hub_app/data/services/zhihu_exception.dart';
import 'package:nexus_hub_app/data/services/zhihu_service.dart';

void main() {
  setUpAll(() async {
    LocalDatabase.useInMemoryDatabaseForTesting();
    SharedPreferences.setMockInitialValues({});
    // The in-memory path uses a temp directory; `initFlutter` would hit the
    // path_provider platform channel, so init the in-memory backend instead.
  });

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  group('_parseAnswerPage', () {
    test('accepts inline answer nodes (web v4 feeds shape)', () {
      final page = ZhihuService.parseAnswerPageForTest({
        'data': [
          {
            'id': '123',
            'author': {'name': '甲', 'headline': 'h', 'avatar_url': 'a'},
            'voteup_count': 7,
            'comment_count': 3,
            'content': '<p>正文甲</p>',
            'created_time': 1700000000,
          },
        ],
        'paging': {'is_end': true},
      }, questionId: 'q1', requested: 5);

      expect(page.answers, hasLength(1));
      expect(page.answers.first.id, '123');
      expect(page.answers.first.authorName, '甲');
      expect(page.answers.first.contentHtml, '<p>正文甲</p>');
      expect(page.hasMore, isFalse);
    });

    test('accepts target-wrapped answer nodes (mobile feeds shape)', () {
      final page = ZhihuService.parseAnswerPageForTest({
        'data': [
          {
            'target': {
              'id': 456,
              'author': {
                'name': '乙',
                'headline': '',
                'avatar_url': '',
              },
              'voteup_count': 10,
              'comment_count': 2,
              'content': '<p>正文乙</p>',
              'updated_time': 1700000000,
            },
          },
        ],
        'paging': {'is_end': true},
      }, questionId: 'q2', requested: 5);

      expect(page.answers, hasLength(1));
      expect(page.answers.first.id, '456');
      expect(page.answers.first.authorName, '乙');
      expect(page.hasMore, isFalse);
    });

    test('treats a shallow wrapper payload as a parse failure', () {
      // The mobile app gateway answers risk-control: this exact 10003 body
      // used to slip through `_asJsonMap` + `_ensureNoApiError` and then
      // crash with a non-Exception type error while parsing its `data`
      // (a String, not a List). Both sources fail, so the user only ever
      // saw "回答数据解析失败".
      expect(
        () => ZhihuService.parseAnswerPageForTest({
          'error': {
            'message': '请求参数异常，请升级客户端后重试。',
            'code': 10003,
          },
        }, questionId: 'q3', requested: 5),
        throwsA(isA<ZhihuException>()),
      );
    });

    test('surfaces the top-level string error shape as a ZhihuException', () {
      expect(
        () => ZhihuService.parseAnswerPageForTest({
          'error': '接口返回错误',
        }, questionId: 'q4', requested: 5),
        throwsA(isA<ZhihuException>()),
      );
    });

    test('returns hasMore=false when paging is absent (only recent pages '
        'are fetched)', () {
      final page = ZhihuService.parseAnswerPageForTest({
        'data': [
          {
            'id': '789',
            'author': {
              'name': '丙',
              'headline': '',
              'avatar_url': '',
            },
            'voteup_count': 1,
            'comment_count': 0,
            'content': '<p>正文丙</p>',
            'created_time': 1700000000,
          },
        ],
      }, questionId: 'q5', requested: 5);

      expect(page.answers, hasLength(1));
      expect(page.hasMore, isFalse);
    });
  });
}