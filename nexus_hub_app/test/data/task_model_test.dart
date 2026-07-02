import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/task_model.dart';

void main() {
  group('TaskModel', () {
    TaskModel makeTask({required String description}) {
      return TaskModel(
        id: 1,
        title: 'Task title',
        description: description,
        tag: 'test',
        priority: 'high',
        status: 'todo',
        createdAt: DateTime(2026, 7, 2),
        updatedAt: DateTime(2026, 7, 2),
      );
    }

    test('plainDescription extracts text from Quill delta JSON', () {
      const delta = '{"ops":[{"insert":"Hello "},{"insert":"world"}]}';
      final task = makeTask(description: delta);

      expect(task.plainDescription, 'Hello world');
    });

    test(
      'plainDescription falls back to raw string for non-JSON description',
      () {
        const raw = 'Plain text description';
        final task = makeTask(description: raw);

        expect(task.plainDescription, raw);
      },
    );
  });
}
