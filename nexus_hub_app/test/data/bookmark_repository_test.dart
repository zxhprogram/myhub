import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/bookmark_model.dart';
import 'package:nexus_hub_app/data/services/api_client.dart';

void main() {
  group('BookmarkModel', () {
    test('fromJson parses response correctly', () {
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
      expect(model.id, 1);
      expect(model.title, 'Flutter');
      expect(model.tags, ['dev']);
    });
  });

  group('ApiClient', () {
    test('uses provided baseUrl', () {
      final client = ApiClient(baseUrl: 'http://example.com');
      expect(client.dio.options.baseUrl, 'http://example.com');
    });
  });
}
