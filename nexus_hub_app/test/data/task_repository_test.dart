import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/task_model.dart';
import 'package:nexus_hub_app/data/repositories/task_repository.dart';
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

  TaskModel buildTask({String status = 'todo', String title = 'T'}) {
    return TaskModel(
      title: title,
      description: '{}',
      tag: '',
      priority: 'medium',
      status: status,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  test('createTask persists task with generated id', () async {
    final repo = TaskRepository();

    final created = await repo.createTask(buildTask());

    expect(created.id, isNotNull);
    final tasks = await repo.fetchTasks();
    expect(tasks.length, 1);
    expect(tasks.first.id, created.id);
    expect(tasks.first.title, 'T');
  });

  test('updateTask persists changes', () async {
    final repo = TaskRepository();
    final created = await repo.createTask(buildTask());

    final updated = await repo.updateTask(created.copyWith(title: 'Renamed'));
    expect(updated.title, 'Renamed');

    final tasks = await repo.fetchTasks();
    expect(tasks.first.title, 'Renamed');
  });

  test('deleteTask removes the task', () async {
    final repo = TaskRepository();
    final created = await repo.createTask(buildTask());

    await repo.deleteTask(created.id!);

    expect(await repo.fetchTasks(), isEmpty);
  });

  test('fetchTasks filters by status', () async {
    final repo = TaskRepository();
    await repo.createTask(buildTask(status: 'done'));
    final fresh = await repo.createTask(buildTask(status: 'todo'));

    final todoTasks = await repo.fetchTasks(status: 'todo');
    expect(todoTasks.map((t) => t.id), [fresh.id]);
  });

  test('fetchTasks sorts by updatedAt desc', () async {
    final repo = TaskRepository();
    final older = await repo.createTask(buildTask(title: 'Old'));
    final newer = await repo.createTask(buildTask(title: 'New'));
    await repo.updateTask(older.copyWith(updatedAt: DateTime.now()));

    final tasks = await repo.fetchTasks();
    expect(tasks.first.id, older.id);
    expect(tasks.last.id, newer.id);
  });
}
