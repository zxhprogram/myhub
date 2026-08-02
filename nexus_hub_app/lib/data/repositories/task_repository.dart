import '../models/task_model.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// Repository for task CRUD operations with offline fallback.
class TaskRepository {
  TaskRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<TaskModel>> fetchTasks({String? status}) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/tasks',
        queryParameters: status != null ? {'status': status} : null,
      );
      final data = response.data ?? [];
      final tasks = data
          .cast<Map<String, dynamic>>()
          .map(TaskModel.fromJson)
          .toList();
      await _cacheTasks(tasks);
      return tasks;
    } catch (_) {
      return _loadCachedTasks(status: status);
    }
  }

  Future<TaskModel> createTask(TaskModel task) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/tasks',
        data: task.toJson(),
      );
      final created = TaskModel.fromJson(response.data!);
      await _insertLocal(created);
      return created;
    } catch (_) {
      final id = await _insertLocal(task);
      return task.copyWith(id: id);
    }
  }

  Future<TaskModel> updateTask(TaskModel task) async {
    final id = task.id;
    if (id == null) {
      await _updateLocal(task);
      return task;
    }
    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/tasks/$id',
        data: task.toJson(),
      );
      final updated = TaskModel.fromJson(response.data!);
      await _updateLocal(updated);
      return updated;
    } catch (_) {
      await _updateLocal(task);
      return task;
    }
  }

  Future<void> deleteTask(int id) async {
    try {
      await _client.delete<dynamic>('/tasks/$id');
    } catch (_) {
      // Best-effort: fall through to local delete.
    }
    await _deleteLocal(id);
  }

  Future<void> _cacheTasks(List<TaskModel> tasks) async {
    final box = await LocalDatabase.box('tasks');
    await box.clear();
    for (final t in tasks) {
      await _insertLocal(t);
    }
  }

  Future<int> _insertLocal(TaskModel task) async {
    final box = await LocalDatabase.box('tasks');
    final id = task.id;
    if (id != null) {
      await box.put(id, task.toJson());
      return id;
    }
    return await box.add(task.toJson());
  }

  Future<void> _updateLocal(TaskModel task) async {
    final id = task.id;
    if (id == null) return;
    final box = await LocalDatabase.box('tasks');
    await box.put(id, task.toJson());
  }

  Future<void> _deleteLocal(int id) async {
    final box = await LocalDatabase.box('tasks');
    await box.delete(id);
  }

  Future<List<TaskModel>> _loadCachedTasks({String? status}) async {
    final box = await LocalDatabase.box('tasks');
    final rows = box.values.cast<Map<String, dynamic>>().where((row) {
      if (status == null) return true;
      return row['status'] == status;
    }).toList();
    rows.sort((a, b) {
      final aUpdated = DateTime.parse(a['updatedAt'] as String);
      final bUpdated = DateTime.parse(b['updatedAt'] as String);
      return bUpdated.compareTo(aUpdated);
    });
    return rows.map(TaskModel.fromJson).toList();
  }
}
