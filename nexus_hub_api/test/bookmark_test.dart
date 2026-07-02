import 'package:nexus_hub_api/models/bookmark.dart';
import 'package:test/test.dart';

void main() {
  group('Bookmark', () {
    test('serializes to JSON', () {
      final now = DateTime.now();
      final bookmark = Bookmark(
        id: 1,
        title: 'Flutter',
        url: 'https://flutter.dev',
        tags: const ['dev'],
        category: 'framework',
        createdAt: now,
        updatedAt: now,
      );

      final json = bookmark.toJson();
      expect(json['id'], 1);
      expect(json['title'], 'Flutter');
      expect(json['url'], 'https://flutter.dev');
      expect(json['collectionIds'], isEmpty);

      final withCollections = bookmark.toJson(collectionIds: [2, 5]);
      expect(withCollections['collectionIds'], equals([2, 5]));
    });
  });
}
