import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/task_model.dart';
import '../../data/repositories/task_repository.dart';

/// Definition of a kanban column.
class TaskColumn {
  const TaskColumn({required this.status, required this.title});

  /// Stable key stored on each task's `status` field.
  final String status;

  /// Display title shown in the column header.
  final String title;

  TaskColumn copyWith({String? status, String? title}) =>
      TaskColumn(status: status ?? this.status, title: title ?? this.title);
}

/// Signals-backed state for tasks.
class TasksState {
  TasksState({TaskRepository? repository})
    : _repository = repository ?? TaskRepository();

  final TaskRepository _repository;

  final Signal<List<TaskModel>> tasks = signal<List<TaskModel>>([]);
  final Signal<List<TaskColumn>> columns = signal<List<TaskColumn>>([
    TaskColumn(status: 'todo', title: 'To Do'),
    TaskColumn(status: 'in_progress', title: 'In Progress'),
    TaskColumn(status: 'done', title: 'Done'),
  ]);
  final Signal<String?> error = signal<String?>(null);
  final Signal<bool> isLoading = signal<bool>(false);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      tasks.value = await _repository.fetchTasks();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> add(TaskModel task) async {
    try {
      final created = await _repository.createTask(task);
      tasks.value = [...tasks.value, created];
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> moveTask(TaskModel task, String newStatus) async {
    if (task.status == newStatus) return;
    final updated = task.copyWith(status: newStatus, updatedAt: DateTime.now());
    // Optimistically update the UI.
    tasks.value = tasks.value
        .map((t) => t.id == task.id ? updated : t)
        .toList();
    try {
      final persisted = await _repository.updateTask(updated);
      tasks.value = tasks.value
          .map((t) => t.id == task.id ? persisted : t)
          .toList();
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> deleteTask(TaskModel task) async {
    final previous = tasks.value;
    tasks.value = tasks.value.where((t) => t.id != task.id).toList();
    try {
      if (task.id != null) {
        await _repository.deleteTask(task.id!);
      }
    } catch (e) {
      error.value = e.toString();
      tasks.value = previous;
    }
  }

  void addColumn(String title) {
    final status = _slugify(title);
    if (columns.value.any((c) => c.status == status)) return;
    columns.value = [
      ...columns.value,
      TaskColumn(status: status, title: title),
    ];
  }

  /// Removes a column and reassigns its tasks to the first remaining column.
  Future<void> deleteColumn(TaskColumn column) async {
    final remaining = columns.value
        .where((c) => c.status != column.status)
        .toList();
    if (remaining.isEmpty) return;
    columns.value = remaining;
    final target = remaining.first;
    final affected = tasks.value
        .where((t) => t.status == column.status)
        .toList();
    if (affected.isEmpty) return;
    for (final task in affected) {
      await moveTask(task, target.status);
    }
  }
}

String _slugify(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceFirst(RegExp(r'^_+'), '')
      .replaceFirst(RegExp(r'_+$'), '');
}
