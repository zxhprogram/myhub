import '../models/task_model.dart';
import '../services/local_database.dart';

/// Repository for task CRUD operations backed by the local Hive store.
class TaskRepository {
  TaskRepository();

  Future<List<TaskModel>> fetchTasks({String? status}) {
    return _loadTasks(status: status);
  }

  Future<TaskModel> createTask(TaskModel task) async {
    final local = task.copyWith(updatedAt: DateTime.now());
    final id = await _insertLocal(local);
    return local.copyWith(id: id);
  }

  Future<TaskModel> updateTask(TaskModel task) async {
    final id = task.id;
    if (id == null) {
      final newId = await _insertLocal(task);
      return task.copyWith(id: newId);
    }
    final updated = task.copyWith(updatedAt: DateTime.now());
    await _updateLocal(updated);
    return updated;
  }

  Future<void> deleteTask(int id) async {
    final box = await LocalDatabase.box('tasks');
    await box.delete(id);
  }

  Future<int> _insertLocal(TaskModel task) async {
    final box = await LocalDatabase.box('tasks');
    final id = task.id;
    if (id != null) {
      await box.put(id, task.toJson());
      return id;
    }
    final newId = await box.add(task.toJson());
    // Backfill the generated id into the stored record so later loads see it.
    await box.put(newId, task.copyWith(id: newId).toJson());
    return newId;
  }

  Future<void> _updateLocal(TaskModel task) async {
    final id = task.id;
    if (id == null) return;
    final box = await LocalDatabase.box('tasks');
    await box.put(id, task.toJson());
  }

  Future<List<TaskModel>> _loadTasks({String? status}) async {
    final box = await LocalDatabase.box('tasks');
    final rows = box.values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
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
