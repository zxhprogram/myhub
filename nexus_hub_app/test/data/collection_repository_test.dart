import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/repositories/collection_repository.dart';
import 'package:nexus_hub_app/data/services/api_client.dart';
import 'package:nexus_hub_app/data/services/local_database.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.responses = const {}, this.fail = const {}})
    : super(baseUrl: 'http://test');

  final Map<String, dynamic> responses;
  final Set<String> fail;
  final List<String> calls = [];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    calls.add('GET $path');
    if (fail.contains(path)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Future.value(
      Response<T>(
        data: responses[path] as T?,
        requestOptions: RequestOptions(path: path),
      ),
    );
  }

  @override
  Future<Response<T>> post<T>(String path, {dynamic data}) {
    calls.add('POST $path');
    if (fail.contains(path)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Future.value(
      Response<T>(
        data: responses[path] as T?,
        requestOptions: RequestOptions(path: path),
      ),
    );
  }

  @override
  Future<Response<T>> put<T>(String path, {dynamic data}) {
    calls.add('PUT $path');
    if (fail.contains(path)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Future.value(
      Response<T>(
        data: responses[path] as T?,
        requestOptions: RequestOptions(path: path),
      ),
    );
  }

  @override
  Future<Response<T>> delete<T>(String path) {
    calls.add('DELETE $path');
    if (fail.contains(path)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Future.value(
      Response<T>(requestOptions: RequestOptions(path: path), statusCode: 204),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LocalDatabase.useInMemoryDatabaseForTesting();

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  tearDown(() async {
    await LocalDatabase.close();
  });

  group('CollectionRepository', () {
    test('fetchCollections returns API data and caches locally', () async {
      final client = _FakeApiClient(
        responses: {
          '/collections': [
            {
              'id': 1,
              'name': 'Work',
              'sortOrder': 0,
              'createdAt': '2026-06-28T00:00:00.000',
              'updatedAt': '2026-06-28T00:00:00.000',
            },
          ],
        },
      );
      final repository = CollectionRepository(client: client);

      final collections = await repository.fetchCollections(sort: 'name_asc');

      expect(collections.length, 1);
      expect(collections.first.name, 'Work');
      expect(client.calls, contains('GET /collections'));

      final box = await LocalDatabase.box('collections');
      expect(box.length, 1);
      final record = box.get(1) as Map;
      expect(record['name'], 'Work');
    });

    test('fetchCollections falls back to local cache when API fails', () async {
      final successClient = _FakeApiClient(
        responses: {
          '/collections': [
            {
              'id': 2,
              'name': 'Local Only',
              'sortOrder': 0,
              'createdAt': '2026-06-28T00:00:00.000',
              'updatedAt': '2026-06-28T00:00:00.000',
            },
          ],
        },
      );
      final repository = CollectionRepository(client: successClient);
      await repository.fetchCollections();

      final failingClient = _FakeApiClient(fail: {'/collections'});
      final offlineRepository = CollectionRepository(client: failingClient);
      final collections = await offlineRepository.fetchCollections();

      expect(collections.length, 1);
      expect(collections.first.name, 'Local Only');
    });

    test('createCollection posts to API and inserts locally', () async {
      final client = _FakeApiClient(
        responses: {
          '/collections': {
            'id': 3,
            'name': 'Read Later',
            'sortOrder': 0,
            'createdAt': '2026-06-28T00:00:00.000',
            'updatedAt': '2026-06-28T00:00:00.000',
          },
        },
      );
      final repository = CollectionRepository(client: client);

      final created = await repository.createCollection('Read Later');

      expect(created.name, 'Read Later');
      expect(created.id, 3);
      expect(client.calls, contains('POST /collections'));

      final box = await LocalDatabase.box('collections');
      expect(box.get(3), isNotNull);
    });

    test('updateCollection puts to API and updates local row', () async {
      final box = await LocalDatabase.box('collections');
      await box.put(4, {
        'id': 4,
        'name': 'Old',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      });

      final client = _FakeApiClient(
        responses: {
          '/collections/4': {
            'id': 4,
            'name': 'Renamed',
            'sortOrder': 0,
            'createdAt': '2026-06-28T00:00:00.000',
            'updatedAt': '2026-06-28T00:00:00.000',
          },
        },
      );
      final repository = CollectionRepository(client: client);

      final updated = await repository.updateCollection(4, 'Renamed');

      expect(updated.name, 'Renamed');
      expect(client.calls, contains('PUT /collections/4'));

      final record = box.get(4) as Map;
      expect(record['name'], 'Renamed');
    });

    test('deleteCollection removes API resource and local rows', () async {
      final bookmarkBox = await LocalDatabase.box('bookmarks');
      await bookmarkBox.put(1, {
        'id': 1,
        'title': 'Flutter',
        'url': 'https://flutter.dev',
        'tags': <String>[],
        'category': 'dev',
        'image': '',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      });

      final collectionBox = await LocalDatabase.box('collections');
      await collectionBox.put(5, {
        'id': 5,
        'name': 'Work',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      });

      final bcBox = await LocalDatabase.box('bookmark_collections');
      await bcBox.put('1:5', {
        'bookmark_id': 1,
        'collection_id': 5,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final client = _FakeApiClient();
      final repository = CollectionRepository(client: client);
      await repository.deleteCollection(5);

      expect(client.calls, contains('DELETE /collections/5'));
      expect(collectionBox.get(5), isNull);

      // Verify association is removed.
      var hasAssoc = false;
      for (final value in bcBox.values) {
        final record = Map<String, dynamic>.from(value as Map);
        if (record['collection_id'] == 5) {
          hasAssoc = true;
        }
      }
      expect(hasAssoc, isFalse);

      // Bookmark should still exist.
      expect(bookmarkBox.get(1), isNotNull);
    });

    test('addBookmarksToCollection posts and inserts association', () async {
      final bookmarkBox = await LocalDatabase.box('bookmarks');
      await bookmarkBox.put(1, {
        'id': 1,
        'title': 'Flutter',
        'url': 'https://flutter.dev',
        'tags': <String>[],
        'category': 'dev',
        'image': '',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      });

      final collectionBox = await LocalDatabase.box('collections');
      await collectionBox.put(6, {
        'id': 6,
        'name': 'Articles',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      });

      final client = _FakeApiClient();
      final repository = CollectionRepository(client: client);
      await repository.addBookmarksToCollection(6, [1]);

      expect(client.calls, contains('POST /collections/6/bookmarks'));
      final bcBox = await LocalDatabase.box('bookmark_collections');
      expect(bcBox.get('1:6'), isNotNull);
    });

    test(
      'removeBookmarksFromCollection deletes association locally and remotely',
      () async {
        final bcBox = await LocalDatabase.box('bookmark_collections');
        await bcBox.put('1:7', {
          'bookmark_id': 1,
          'collection_id': 7,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        final client = _FakeApiClient();
        final repository = CollectionRepository(client: client);
        await repository.removeBookmarksFromCollection(7, [1]);

        expect(client.calls, contains('DELETE /collections/7/bookmarks/1'));
        expect(bcBox.get('1:7'), isNull);
      },
    );

    test(
      'getBookmarksInCollection returns cached bookmarks with collectionIds',
      () async {
        final bookmarkBox = await LocalDatabase.box('bookmarks');
        await bookmarkBox.put(10, {
          'id': 10,
          'title': 'Dart',
          'url': 'https://dart.dev',
          'tags': <String>[],
          'category': 'dev',
          'image': '',
          'sortOrder': 0,
          'createdAt': '2026-06-28T00:00:00.000',
          'updatedAt': '2026-06-28T00:00:00.000',
        });

        final collectionBox = await LocalDatabase.box('collections');
        await collectionBox.put(8, {
          'id': 8,
          'name': 'Dev',
          'sortOrder': 0,
          'createdAt': '2026-06-28T00:00:00.000',
          'updatedAt': '2026-06-28T00:00:00.000',
        });

        final bcBox = await LocalDatabase.box('bookmark_collections');
        await bcBox.put('10:8', {
          'bookmark_id': 10,
          'collection_id': 8,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });

        final client = _FakeApiClient(fail: {'/collections/8/bookmarks'});
        final repository = CollectionRepository(client: client);
        final bookmarks = await repository.getBookmarksInCollection(8);

        expect(bookmarks.length, 1);
        expect(bookmarks.first.collectionIds, contains(8));
      },
    );
  });
}
