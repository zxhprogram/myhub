import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/bookmark_model.dart';
import 'package:nexus_hub_app/data/repositories/bookmark_repository.dart';
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

  BookmarkModel buildBookmark({String title = 'Flutter', int? id}) {
    final now = DateTime.now();
    return BookmarkModel(
      id: id,
      title: title,
      url: 'https://flutter.dev',
      tags: const ['dev'],
      category: 'framework',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('createBookmark persists bookmark with generated id', () async {
    final repo = BookmarkRepository();

    final created = await repo.createBookmark(buildBookmark());

    expect(created.id, isNotNull);
    final bookmarks = await repo.fetchBookmarks();
    expect(bookmarks.length, 1);
    expect(bookmarks.first.id, created.id);
    expect(bookmarks.first.title, 'Flutter');
  });

  test('createBookmark stores the generated id inside the record', () async {
    final repo = BookmarkRepository();
    final created = await repo.createBookmark(buildBookmark());

    // The stored record must carry the id so later loads see it.
    final box = await LocalDatabase.box('bookmarks');
    final record = Map<String, dynamic>.from(box.get(created.id) as Map);
    expect(record['id'], created.id);
  });

  test('updateBookmark persists changes', () async {
    final repo = BookmarkRepository();
    final created = await repo.createBookmark(buildBookmark());

    final updated = await repo.updateBookmark(
      created.copyWith(title: 'Renamed'),
    );
    expect(updated.title, 'Renamed');

    final bookmarks = await repo.fetchBookmarks();
    expect(bookmarks.first.title, 'Renamed');
  });

  test('deleteBookmark removes bookmark and collection associations',
      () async {
    final repo = BookmarkRepository();
    final created = await repo.createBookmark(buildBookmark());

    final bcBox = await LocalDatabase.box('bookmark_collections');
    await bcBox.put('${created.id}:1', {
      'bookmark_id': created.id,
      'collection_id': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await repo.deleteBookmark(created.id!);

    expect(await repo.fetchBookmarks(), isEmpty);
    expect(bcBox.values, isEmpty);
  });

  test('fetchBookmarks attaches collectionIds from associations', () async {
    final repo = BookmarkRepository();
    final created = await repo.createBookmark(buildBookmark());

    final bcBox = await LocalDatabase.box('bookmark_collections');
    await bcBox.put('${created.id}:3', {
      'bookmark_id': created.id,
      'collection_id': 3,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final bookmarks = await repo.fetchBookmarks();
    expect(bookmarks.first.collectionIds, contains(3));
  });

  test('fetchBookmarks filters by title query', () async {
    final repo = BookmarkRepository();
    await repo.createBookmark(buildBookmark(title: 'Flutter'));
    await repo.createBookmark(buildBookmark(title: 'Dart'));

    final results = await repo.fetchBookmarks(query: 'dart');
    expect(results.map((b) => b.title), ['Dart']);
  });

  test('reorder writes positional sort orders', () async {
    final repo = BookmarkRepository();
    final a = await repo.createBookmark(buildBookmark(title: 'A'));
    final b = await repo.createBookmark(buildBookmark(title: 'B'));
    final c = await repo.createBookmark(buildBookmark(title: 'C'));

    final reordered = await repo.reorder([c.id!, a.id!, b.id!]);

    expect(reordered.map((b) => b.id).toList(), [c.id, a.id, b.id]);
    final stored = await repo.fetchBookmarks();
    expect(
      stored.map((b) => b.id).toList(),
      [c.id, a.id, b.id],
    );
  });
}
