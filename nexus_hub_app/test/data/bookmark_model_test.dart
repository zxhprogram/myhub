import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/bookmark_model.dart';

void main() {
  group('BookmarkModel', () {
    test('fromJson parses collectionIds', () {
      final json = {
        'id': 1,
        'title': 'Flutter',
        'url': 'https://flutter.dev',
        'tags': ['dev'],
        'category': 'framework',
        'image': 'https://flutter.dev/image.png',
        'sortOrder': 2,
        'collectionIds': [3, 5],
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      };

      final model = BookmarkModel.fromJson(json);

      expect(model.id, 1);
      expect(model.title, 'Flutter');
      expect(model.collectionIds, [3, 5]);
      expect(model.image, 'https://flutter.dev/image.png');
      expect(model.sortOrder, 2);
    });

    test('fromJson defaults collectionIds to empty list', () {
      final json = {
        'id': 1,
        'title': 'Flutter',
        'url': 'https://flutter.dev',
        'tags': ['dev'],
        'category': 'framework',
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      };

      final model = BookmarkModel.fromJson(json);

      expect(model.collectionIds, isEmpty);
    });

    test('toJson includes collectionIds', () {
      final now = DateTime(2026, 6, 28);
      final model = BookmarkModel(
        id: 1,
        title: 'Flutter',
        url: 'https://flutter.dev',
        tags: ['dev'],
        category: 'framework',
        collectionIds: [2, 4],
        createdAt: DateTime(2026, 6, 28),
        updatedAt: DateTime(2026, 6, 28),
      );

      final json = model.toJson();

      expect(json['collectionIds'], [2, 4]);
      expect(json['title'], 'Flutter');
      expect(json['createdAt'], now.toIso8601String());
    });

    test('copyWith updates collectionIds', () {
      final model = BookmarkModel(
        id: 1,
        title: 'Flutter',
        url: 'https://flutter.dev',
        tags: ['dev'],
        category: 'framework',
        createdAt: DateTime(2026, 6, 28),
        updatedAt: DateTime(2026, 6, 28),
      );

      final updated = model.copyWith(collectionIds: [7]);

      expect(updated.collectionIds, [7]);
      expect(updated.title, 'Flutter');
      expect(updated.id, 1);
    });
  });
}
