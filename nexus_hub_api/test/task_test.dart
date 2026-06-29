import 'package:nexus_hub_api/models/task.dart';
import 'package:test/test.dart';

void main() {
  group('Task', () {
    test('serializes to JSON', () {
      final now = DateTime.now();
      final task = Task(
        id: 1,
        title: 'Implement API',
        description: 'Build REST endpoints',
        tag: 'backend',
        priority: 'high',
        status: 'todo',
        createdAt: now,
        updatedAt: now,
      );

      final json = task.toJson();
      expect(json['id'], 1);
      expect(json['title'], 'Implement API');
      expect(json['status'], 'todo');
    });
  });
}
