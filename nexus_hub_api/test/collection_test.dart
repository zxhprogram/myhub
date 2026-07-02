import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../lib/models/collection.dart';

void main() {
  group('Collection', () {
    test('serializes to JSON', () {
      final now = DateTime.now();
      final collection = Collection(
        id: 1,
        name: 'Read Later',
        sortOrder: 2,
        createdAt: now,
        updatedAt: now,
      );

      final json = collection.toJson();
      expect(json['id'], 1);
      expect(json['name'], 'Read Later');
      expect(json['sortOrder'], 2);
      expect(json['createdAt'], now.toIso8601String());
      expect(json['updatedAt'], now.toIso8601String());
    });

    test('parses from row', () {
      final db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE collections (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO collections (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [5, 'Work', 1, now, now],
      );

      final row = db.select('SELECT * FROM collections WHERE id = ?', [5]).first;
      final collection = Collection.fromRow(row);

      expect(collection.id, 5);
      expect(collection.name, 'Work');
      expect(collection.sortOrder, 1);
      expect(collection.createdAt.millisecondsSinceEpoch, now);
      expect(collection.updatedAt.millisecondsSinceEpoch, now);

      db.dispose();
    });

    test('copyWith updates fields', () {
      final now = DateTime.now();
      final collection = Collection(
        id: 1,
        name: 'Old',
        createdAt: now,
        updatedAt: now,
      );

      final renamed = collection.copyWith(name: 'New');
      expect(renamed.id, 1);
      expect(renamed.name, 'New');
      expect(renamed.createdAt, now);
    });
  });
}
