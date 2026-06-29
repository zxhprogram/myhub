import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/rss_item.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      final feedRows = db.select(
        'SELECT * FROM rss_feeds ORDER BY created_at DESC',
      ).cast<Row>();
      final feeds = feedRows.map(RssFeed.fromRow).toList();
      final feedIds = feeds.map((f) => f.id).whereType<int>().toList();
      final articles = feedIds.isEmpty
          ? <RssArticle>[]
          : db
                .select(
                  'SELECT * FROM rss_items WHERE feed_id IN (${feedIds.map((_) => '?').join(',')}) ORDER BY published_at DESC LIMIT 50',
                  feedIds,
                ).cast<Row>()
                .map(RssArticle.fromRow)
                .toList();

      return Response.json(
        body: {
          'feeds': feeds.map((f) => f.toJson()).toList(),
          'articles': articles.map((a) => a.toJson()).toList(),
        },
      );

    case HttpMethod.post:
      final body = await context.request.json() as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      final title = body['title'] as String? ?? '';
      final url = body['url'] as String? ?? '';
      final category = body['category'] as String? ?? '';

      try {
        db.execute(
          '''
          INSERT INTO rss_feeds (title, url, category, created_at)
          VALUES (?, ?, ?, ?)
        ''',
          [title, url, category, now],
        );
      } on SqliteException catch (_) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'Feed URL already exists'},
        );
      }

      final id = db.lastInsertRowId;
      return Response.json(
        statusCode: HttpStatus.created,
        body: RssFeed(
          id: id,
          title: title,
          url: url,
          category: category,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        ).toJson(),
      );

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}
