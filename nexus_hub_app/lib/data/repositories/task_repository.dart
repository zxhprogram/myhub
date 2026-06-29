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
      final local = task.copyWith(id: null);
      await _insertLocal(local);
      return local;
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
    final db = await LocalDatabase.instance;
    await db.delete('tasks');
    for (final t in tasks) {
      await _insertLocal(t);
    }
  }

  Future<void> _insertLocal(TaskModel task) async {
    final db = await LocalDatabase.instance;
    await db.insert('tasks', {
      'title': task.title,
      'description': task.description,
      'tag': task.tag,
      'priority': task.priority,
      'status': task.status,
      'due_date': task.dueDate?.millisecondsSinceEpoch,
      'created_at': task.createdAt.millisecondsSinceEpoch,
      'updated_at': task.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> _updateLocal(TaskModel task) async {
    final db = await LocalDatabase.instance;
    final id = task.id;
    if (id == null) return;
    await db.update(
      'tasks',
      {
        'title': task.title,
        'description': task.description,
        'tag': task.tag,
        'priority': task.priority,
        'status': task.status,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _deleteLocal(int id) async {
    final db = await LocalDatabase.instance;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TaskModel>> _loadCachedTasks({String? status}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'tasks',
      where: status != null ? 'status = ?' : null,
      whereArgs: status != null ? [status] : null,
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToModel).toList();
  }

  TaskModel _rowToModel(Map<String, dynamic> row) {
    return TaskModel(
      id: row['id'] as int,
      title: row['title'] as String,
      description: row['description'] as String,
      tag: row['tag'] as String,
      priority: row['priority'] as String,
      status: row['status'] as String,
      dueDate: row['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['due_date'] as int)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
