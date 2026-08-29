import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/repositories/collection_repository.dart';
import 'package:nexus_hub_app/data/services/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LocalDatabase.useInMemoryDatabaseForTesting();

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  tearDown(() async {
    await LocalDatabase.close();
  });

  Map<String, dynamic> bookmarkRecord(int id, String title) => {
        'id': id,
        'title': title,
        'url': 'https://flutter.dev',
        'tags': <String>[],
        'category': 'dev',
        'image': '',
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      };

  Map<String, dynamic> collectionRecord(int id, String name) => {
        'id': id,
        'name': name,
        'sortOrder': 0,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      };

  test('createCollection persists collection with generated id', () async {
    final repository = CollectionRepository();

    final created = await repository.createCollection('Read Later');

    expect(created.id, isNotNull);
    expect(created.name, 'Read Later');
    final collections = await repository.fetchCollections();
    expect(collections.length, 1);
    expect(collections.first.id, created.id);
  });

  test('createCollection rejects duplicate names', () async {
    final repository = CollectionRepository();
    await repository.createCollection('Work');

    expect(
      () => repository.createCollection('Work'),
      throwsStateError,
    );
  });

  test('updateCollection renames the collection', () async {
    final repository = CollectionRepository();
    final created = await repository.createCollection('Old');

    final updated = await repository.updateCollection(created.id!, 'Renamed');

    expect(updated.name, 'Renamed');
    final collections = await repository.fetchCollections();
    expect(collections.first.name, 'Renamed');
  });

  test('updateCollection rejects renaming to an existing name', () async {
    final repository = CollectionRepository();
    final first = await repository.createCollection('Work');
    final second = await repository.createCollection('Play');

    expect(
      () => repository.updateCollection(second.id!, 'Work'),
      throwsStateError,
    );
    // The first collection still has the original name.
    final collections = await repository.fetchCollections();
    expect(
      collections.firstWhere((c) => c.id == first.id).name,
      'Work',
    );
  });

  test('deleteCollection removes collection and its associations', () async {
    final bookmarkBox = await LocalDatabase.box('bookmarks');
    await bookmarkBox.put(1, bookmarkRecord(1, 'Flutter'));

    final collectionBox = await LocalDatabase.box('collections');
    await collectionBox.put(5, collectionRecord(5, 'Work'));

    final bcBox = await LocalDatabase.box('bookmark_collections');
    await bcBox.put('1:5', {
      'bookmark_id': 1,
      'collection_id': 5,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final repository = CollectionRepository();
    await repository.deleteCollection(5);

    expect(collectionBox.get(5), isNull);
    expect(bcBox.values, isEmpty);
    // Bookmark should still exist.
    expect(bookmarkBox.get(1), isNotNull);
  });

  test('addBookmarksToCollection inserts associations', () async {
    final bookmarkBox = await LocalDatabase.box('bookmarks');
    await bookmarkBox.put(1, bookmarkRecord(1, 'Flutter'));

    final collectionBox = await LocalDatabase.box('collections');
    await collectionBox.put(6, collectionRecord(6, 'Articles'));

    final repository = CollectionRepository();
    await repository.addBookmarksToCollection(6, [1]);

    final bcBox = await LocalDatabase.box('bookmark_collections');
    expect(bcBox.get('1:6'), isNotNull);
    expect(await repository.countBookmarks(6), 1);
  });

  test('removeBookmarksFromCollection deletes association', () async {
    final bcBox = await LocalDatabase.box('bookmark_collections');
    await bcBox.put('1:7', {
      'bookmark_id': 1,
      'collection_id': 7,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final repository = CollectionRepository();
    await repository.removeBookmarksFromCollection(7, [1]);

    expect(bcBox.get('1:7'), isNull);
  });

  test('getBookmarksInCollection returns bookmarks with collectionIds',
      () async {
    final bookmarkBox = await LocalDatabase.box('bookmarks');
    await bookmarkBox.put(10, bookmarkRecord(10, 'Dart'));

    final collectionBox = await LocalDatabase.box('collections');
    await collectionBox.put(8, collectionRecord(8, 'Dev'));

    final bcBox = await LocalDatabase.box('bookmark_collections');
    await bcBox.put('10:8', {
      'bookmark_id': 10,
      'collection_id': 8,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final repository = CollectionRepository();
    final bookmarks = await repository.getBookmarksInCollection(8);

    expect(bookmarks.length, 1);
    expect(bookmarks.first.collectionIds, contains(8));
  });
}
