// ignore_for_file: unnecessary_lambdas
// @Tags(['collections'])

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../lib/database.dart';
import '../../routes/collections/[id].dart' as collection_route;
import '../../routes/collections/[id]/bookmarks/[bookmarkId].dart'
    as collection_bookmark_route;
import '../../routes/collections/[id]/bookmarks/index.dart'
    as collection_bookmarks_route;
import '../../routes/collections/index.dart' as collections_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

Future<Map<String, dynamic>> _namePayload(String name) async => {'name': name};

Future<Map<String, dynamic>> _bookmarkIdsPayload(List<int> ids) async => {
  'bookmarkIds': ids,
};

void main() {
  setUp(() {
    DatabaseProvider.useTestDatabase(sqlite3.openInMemory());
  });

  tearDown(() {
    final db = DatabaseProvider.instance;
    DatabaseProvider.useTestDatabase(null);
    db.dispose();
  });

  group('GET /collections', () {
    test('responds with empty list when no collections', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(
        () => request.uri,
      ).thenReturn(Uri.parse('http://localhost/collections'));

      final response = await collections_route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.ok));
      await expectLater(
        response.json(),
        completion(isEmpty),
      );
    });

    test('sorts by name descending', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO collections (name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['Alpha', 0, now, now],
      );
      db.execute(
        'INSERT INTO collections (name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['Zulu', 0, now, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(
        () => request.uri,
      ).thenReturn(Uri.parse('http://localhost/collections?sort=name_desc'));

      final response = await collections_route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.ok));
      final body = await response.json() as List<dynamic>;
      expect((body.first as Map<String, dynamic>)['name'], equals('Zulu'));
      expect((body.last as Map<String, dynamic>)['name'], equals('Alpha'));
    });
  });

  group('POST /collections', () {
    test('creates a collection and responds with 201', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) => _namePayload('Read Later'));

      final response = await collections_route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.created));
      final body = await response.json();
      expect(body['name'], equals('Read Later'));
      expect(body['id'], isNotNull);
    });

    test('responds with 400 when name is empty', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) => _namePayload(''));

      final response = await collections_route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.badRequest));
    });

    test('responds with 409 when name already exists', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO collections (name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['Read Later', 0, now, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) => _namePayload('Read Later'));

      final response = await collections_route.onRequest(context);
      expect(response.statusCode, equals(HttpStatus.conflict));
    });
  });

  group('GET /collections/:id', () {
    test('responds with collection when found', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);

      final response = await collection_route.onRequest(context, '1');
      expect(response.statusCode, equals(HttpStatus.ok));
      final body = await response.json();
      expect(body['name'], equals('Work'));
    });

    test('responds with 404 when not found', () async {
      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);

      final response = await collection_route.onRequest(context, '999');
      expect(response.statusCode, equals(HttpStatus.notFound));
    });
  });

  group('PUT /collections/:id', () {
    test('renames a collection', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.put);
      when(() => request.json()).thenAnswer((_) => _namePayload('Personal'));

      final response = await collection_route.onRequest(context, '1');
      expect(response.statusCode, equals(HttpStatus.ok));
      final body = await response.json();
      expect(body['name'], equals('Personal'));
    });
  });

  group('DELETE /collections/:id', () {
    test('deletes a collection without removing bookmarks', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO bookmarks (id, title, url, tags, category, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [1, 'Flutter', 'https://flutter.dev', '', 'dev', now, now],
      );
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );
      db.execute(
        'INSERT INTO bookmark_collections (bookmark_id, collection_id, created_at) VALUES (?, ?, ?)',
        [1, 1, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.delete);

      final response = await collection_route.onRequest(context, '1');
      expect(response.statusCode, equals(HttpStatus.noContent));

      final bookmarks = db.select('SELECT * FROM bookmarks');
      expect(bookmarks.length, equals(1));
      final relations = db.select('SELECT * FROM bookmark_collections');
      expect(relations.length, equals(0));
    });
  });

  group('POST /collections/:id/bookmarks', () {
    test('adds bookmarks to collection', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO bookmarks (id, title, url, tags, category, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [1, 'Flutter', 'https://flutter.dev', '', 'dev', now, now],
      );
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer((_) => _bookmarkIdsPayload([1]));

      final response = await collection_bookmarks_route.onRequest(context, '1');
      expect(response.statusCode, equals(HttpStatus.created));

      final relations = db.select('SELECT * FROM bookmark_collections');
      expect(relations.length, equals(1));
    });
  });

  group('GET /collections/:id/bookmarks', () {
    test('returns bookmarks in collection with collectionIds', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO bookmarks (id, title, url, tags, category, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [1, 'Flutter', 'https://flutter.dev', '', 'dev', now, now],
      );
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );
      db.execute(
        'INSERT INTO bookmark_collections (bookmark_id, collection_id, created_at) VALUES (?, ?, ?)',
        [1, 1, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);

      final response = await collection_bookmarks_route.onRequest(context, '1');
      expect(response.statusCode, equals(HttpStatus.ok));
      final body = await response.json() as List<dynamic>;
      expect(body.length, equals(1));
      expect(
        (body.first as Map<String, dynamic>)['collectionIds'],
        contains(1),
      );
    });
  });

  group('DELETE /collections/:id/bookmarks/:bookmarkId', () {
    test('removes bookmark from collection', () async {
      final db = DatabaseProvider.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO bookmarks (id, title, url, tags, category, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [1, 'Flutter', 'https://flutter.dev', '', 'dev', now, now],
      );
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [1, 'Work', 0, now, now],
      );
      db.execute(
        'INSERT INTO bookmark_collections (bookmark_id, collection_id, created_at) VALUES (?, ?, ?)',
        [1, 1, now],
      );

      final context = _MockRequestContext();
      final request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.delete);

      final response = await collection_bookmark_route.onRequest(
        context,
        '1',
        '1',
      );
      expect(response.statusCode, equals(HttpStatus.noContent));

      final relations = db.select('SELECT * FROM bookmark_collections');
      expect(relations.length, equals(0));
    });
  });
}
