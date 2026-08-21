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

  group('_parseCommentPage', () {
    test('parses the root_comments shape (member author, embedded '
        'replies, reply_to chain)', () {
      final page = ZhihuService.parseCommentPageForTest({
        'count': 2,
        'data': [
          {
            'id': 1001,
            'author': {
              'member': {
                'name': '张三',
                'avatar_url': 'https://pic/avatar.png',
              },
            },
            'content': '这是一条评论',
            'created_time': 1700000000,
            'vote_count': 3,
            'reply_count': 2,
            'is_author': true,
            'child_comments': {
              'data': [
                {
                  'id': 2001,
                  'author': {
                    'member': {
                      'name': '李四',
                      'avatar_url': '',
                    },
                  },
                  'content': '这是回复一',
                  'created_time': 1700000100,
                  'vote_count': 0,
                  'reply_to': {
                    'id': 1001,
                    'author': {
                      'member': {'name': '张三'},
                    },
                    'content': '这是一条评论',
                    'created_time': 1700000000,
                  },
                },
              ],
              'paging': {'is_end': false},
            },
          },
          {
            'id': 1002,
            'author': {'name': '匿名用户', 'avatar_url': ''},
            'content': '第二条',
            'created_time': 1700000200,
            'vote_count': 0,
            'reply_count': 0,
          },
        ],
        'paging': {'is_end': false, 'next': 'https://www.zhihu.com/api/v4'},
      }, requested: 2);

      expect(page.total, 2);
      expect(page.hasMore, isTrue);
      expect(page.comments, hasLength(2));

      final first = page.comments.first;
      expect(first.id, '1001');
      expect(first.authorName, '张三');
      expect(first.isContentAuthor, isTrue);
      expect(first.voteCount, 3);
      expect(first.replyCount, 2);
      expect(first.createdAtMs, 1700000000000);
      expect(first.replies, hasLength(1));
      expect(first.replies.first.authorName, '李四');
      expect(first.replies.first.replyTo?.authorName, '张三');

      // Flat author objects (legacy /comments shape) parse as-is.
      expect(page.comments[1].authorName, '匿名用户');
    });

    test('sanitizes rich-text comment bodies (noscript copies + lazy '
        'images)', () {
      final page = ZhihuService.parseCommentPageForTest({
        'data': [
          {
            'id': '4001',
            'author': {'name': '赵六'},
            'content': '<p>看图</p>'
                '<noscript><img src="https://pic/full.png"></noscript>'
                '<img src="data:image/svg+xml;base64,PHN2Zw==" '
                'data-actualsrc="https://pic/720.png" '
                'data-original="https://pic/full.png">',
            'created_time': 1700000000,
          },
        ],
        'paging': {'is_end': true},
      }, requested: 20);

      final html = page.comments.single.contentHtml;
      expect(html, contains('<p>看图</p>'));
      // The no-JS duplicate is stripped and the lazy placeholder src is
      // promoted to the loadable URL, so neither renders as literal tags.
      expect(html.contains('<noscript>'), isFalse);
      expect(html, contains('src="https://pic/720.png"'));
    });

    test('treats an empty data list as a valid empty section', () {
      final page = ZhihuService.parseCommentPageForTest({
        'count': 0,
        'data': [],
        'paging': {'is_end': true},
      }, requested: 20);

      expect(page.comments, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.total, 0);
    });

    test('returns hasMore=false at the end of the thread', () {
      final page = ZhihuService.parseCommentPageForTest({
        'count': 1,
        'data': [
          {
            'id': '3001',
            'author': {'name': '王五'},
            'content': '最后一条',
            'created_time': 1700000000,
            'vote_count': 0,
            'reply_count': 0,
          },
        ],
        'paging': {'is_end': true},
      }, requested: 20);

      expect(page.hasMore, isFalse);
    });

    test('surfaces error bodies as ZhihuException', () {
      expect(
        () => ZhihuService.parseCommentPageForTest({
          'error': {'message': '身份未经过验证', 'code': 101},
        }, requested: 20),
        throwsA(isA<ZhihuException>()),
      );
      expect(
        () => ZhihuService.parseCommentPageForTest(
          {'data': 'oops'},
          requested: 20,
        ),
        throwsA(isA<ZhihuException>()),
      );
    });
  });
}