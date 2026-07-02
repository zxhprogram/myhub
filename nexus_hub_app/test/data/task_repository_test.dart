import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/task_model.dart';
import 'package:nexus_hub_app/data/repositories/task_repository.dart';
import 'package:nexus_hub_app/data/services/api_client.dart';
import 'package:nexus_hub_app/data/services/local_database.dart';

class _ThrowingApiClient extends ApiClient {
  _ThrowingApiClient() : super(baseUrl: 'http://test');

  @override
  Future<Response<T>> post<T>(String path, {dynamic data}) async {
    throw Exception('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LocalDatabase.useInMemoryDatabaseForTesting();

  test('createTask caches task with id', () async {
    final repo = TaskRepository(client: _ThrowingApiClient());
    final task = TaskModel(
      title: 'T',
      description: '{}',
      tag: '',
      priority: '',
      status: 'todo',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final created = await repo.createTask(task);

    expect(created.id, isNotNull);
  });
}
