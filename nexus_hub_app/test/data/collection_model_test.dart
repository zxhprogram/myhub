import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/collection_model.dart';

void main() {
  group('CollectionModel', () {
    test('fromJson parses fields correctly', () {
      final json = {
        'id': 1,
        'name': 'Read Later',
        'sortOrder': 2,
        'createdAt': '2026-06-28T00:00:00.000',
        'updatedAt': '2026-06-28T00:00:00.000',
      };

      final model = CollectionModel.fromJson(json);

      expect(model.id, 1);
      expect(model.name, 'Read Later');
      expect(model.sortOrder, 2);
    });

    test('toJson serializes fields correctly', () {
      final now = DateTime(2026, 6, 28);
      final model = CollectionModel(
        id: 1,
        name: 'Read Later',
        sortOrder: 2,
        createdAt: DateTime(2026, 6, 28),
        updatedAt: DateTime(2026, 6, 28),
      );

      final json = model.toJson();

      expect(json['id'], 1);
      expect(json['name'], 'Read Later');
      expect(json['sortOrder'], 2);
      expect(json['createdAt'], now.toIso8601String());
    });

    test('copyWith updates name and preserves other fields', () {
      final now = DateTime(2026, 6, 28);
      final model = CollectionModel(
        id: 1,
        name: 'Old',
        createdAt: now,
        updatedAt: now,
      );

      final renamed = model.copyWith(name: 'New');

      expect(renamed.id, 1);
      expect(renamed.name, 'New');
      expect(renamed.createdAt, now);
    });

    test('models with same id and name are equal', () {
      final now = DateTime(2026, 6, 28);
      final a = CollectionModel(
        id: 1,
        name: 'Work',
        createdAt: now,
        updatedAt: now,
      );
      final b = CollectionModel(
        id: 1,
        name: 'Work',
        createdAt: now,
        updatedAt: now,
      );

      expect(a, b);
    });
  });
}
