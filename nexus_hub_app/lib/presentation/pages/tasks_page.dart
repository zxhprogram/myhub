import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/task_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_input.dart';
import '../components/task_detail_panel.dart';
import '../states/tasks_state.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _state = TasksState();

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.background,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tasks', style: NexusTypography.headlineXl),
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    'Manage your work across the board',
                    style: NexusTypography.bodyMd.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              NexusButton(
                label: 'New Task',
                icon: Icons.add,
                onPressed: () =>
                    _showAddDialog(context, _state.columns.value.first.status),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          // Board
          Expanded(
            child: Watch((_) {
              if (_state.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_state.error.value != null) {
                return Center(
                  child: Text(
                    'Error: ${_state.error.value}',
                    style: NexusTypography.bodyMd.copyWith(
                      color: NexusColors.error,
                    ),
                  ),
                );
              }

              final tasksByStatus = <String, List<TaskModel>>{};
              for (final task in _state.tasks.value) {
                tasksByStatus.putIfAbsent(task.status, () => []).add(task);
              }

              final selected = _state.selectedTask.value;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ..._state.columns.value.map(
                          (column) => Padding(
                            padding: const EdgeInsets.only(
                              right: NexusSpacing.lg,
                            ),
                            child: _KanbanColumn(
                              column: column,
                              tasks: tasksByStatus[column.status] ?? [],
                              onMoveTask: (task) =>
                                  _state.moveTask(task, column.status),
                              onAddTask: () =>
                                  _showAddDialog(context, column.status),
                              onDeleteColumn: () =>
                                  _confirmDeleteColumn(column),
                              onDeleteTask: _state.deleteTask,
                              onTapTask: (task) => _state.selectTask(task),
                            ),
                          ),
                        ),
                        _AddColumnButton(
                          onAdd: () => _showAddColumnDialog(context),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: selected != null ? 420 : 0,
                    child: selected != null
                        ? TaskDetailPanel(state: _state)
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, String defaultStatus) {
    showDialog(
      context: context,
      builder: (context) => _AddTaskDialog(
        defaultStatus: defaultStatus,
        columns: _state.columns.value,
        onSave: (task) => _state.add(task),
      ),
    );
  }

  void _showAddColumnDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
        title: Text('Add List', style: NexusTypography.headlineSm),
        content: SizedBox(
          width: 360,
          child: NexusInput(
            labelText: 'List title',
            controller: controller,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          NexusButton(
            label: 'Add',
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                _state.addColumn(title);
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteColumn(TaskColumn column) {
    final fallback = _state.columns.value.firstWhere(
      (c) => c.status != column.status,
      orElse: () => column,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
        title: Text(
          'Delete "${column.title}"?',
          style: NexusTypography.headlineSm,
        ),
        content: Text(
          fallback.status == column.status
              ? 'This is the only list and cannot be deleted.'
              : 'Tasks in this list will be moved to "${fallback.title}".',
          style: NexusTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          NexusButton(
            label: 'Delete',
            variant: NexusButtonVariant.filled,
            onPressed: fallback.status == column.status
                ? null
                : () {
                    Navigator.of(context).pop();
                    _state.deleteColumn(column);
                  },
          ),
        ],
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.column,
    required this.tasks,
    required this.onMoveTask,
    required this.onAddTask,
    required this.onDeleteColumn,
    required this.onDeleteTask,
    required this.onTapTask,
  });

  final TaskColumn column;
  final List<TaskModel> tasks;
  final ValueChanged<TaskModel> onMoveTask;
  final VoidCallback onAddTask;
  final VoidCallback onDeleteColumn;
  final ValueChanged<TaskModel> onDeleteTask;
  final ValueChanged<TaskModel> onTapTask;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
            child: Row(
              children: [
                Text(column.title, style: NexusTypography.headlineSm),
                const SizedBox(width: NexusSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: NexusColors.surfaceContainerHighest,
                    borderRadius: NexusRadii.fullRadius,
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: NexusTypography.labelMd.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz,
                    color: NexusColors.onSurfaceVariant,
                  ),
                  tooltip: 'List options',
                  shape: RoundedRectangleBorder(
                    borderRadius: NexusRadii.mdRadius,
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 18),
                          const SizedBox(width: NexusSpacing.sm),
                          Text('Delete list', style: NexusTypography.bodyMd),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'delete') onDeleteColumn();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: NexusSpacing.md),
          // Cards area (drag target + scrollable list)
          Expanded(
            child: DragTarget<TaskModel>(
              onAcceptWithDetails: (details) => onMoveTask(details.data),
              builder: (context, candidateData, rejectedData) {
                final isHovering = candidateData.isNotEmpty;
                return Container(
                  decoration: BoxDecoration(
                    color: isHovering
                        ? NexusColors.surfaceContainerHigh.withValues(
                            alpha: 0.6,
                          )
                        : NexusColors.surfaceContainerLow.withValues(
                            alpha: 0.4,
                          ),
                    borderRadius: NexusRadii.xlRadius,
                    border: isHovering
                        ? Border.all(
                            color: NexusColors.secondary.withValues(alpha: 0.5),
                            width: 2,
                          )
                        : null,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(NexusSpacing.sm),
                    children: [
                      ...tasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: NexusSpacing.sm,
                          ),
                          child: _DraggableTaskCard(
                            task: task,
                            onDelete: () => onDeleteTask(task),
                            onTap: () => onTapTask(task),
                          ),
                        ),
                      ),
                      _AddTaskButton(onPressed: onAddTask),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DraggableTaskCard extends StatelessWidget {
  const _DraggableTaskCard({
    required this.task,
    required this.onDelete,
    required this.onTap,
  });

  final TaskModel task;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<TaskModel>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: NexusRadii.xlRadius,
        child: SizedBox(
          width: 288,
          child: _TaskCard(task: task, dragging: true, onTap: onTap),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _TaskCard(task: task, onDelete: onDelete, onTap: onTap),
      ),
      child: _TaskCard(task: task, onDelete: onDelete, onTap: onTap),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.dragging = false,
    this.onDelete,
    this.onTap,
  });

  final TaskModel task;
  final bool dragging;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  Color _tagColor(String tag) {
    return switch (tag.toLowerCase()) {
      'design' => const Color(0xFF7C3AED),
      'backend' => NexusColors.tertiary,
      'frontend' => NexusColors.primary,
      'research' => const Color(0xFF2563EB),
      _ => NexusColors.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tagColor = _tagColor(task.tag);
    return InkWell(
      onTap: onTap,
      borderRadius: NexusRadii.xlRadius,
      child: Container(
        padding: const EdgeInsets.all(NexusSpacing.md),
        decoration: BoxDecoration(
          color: NexusColors.surfaceContainerLowest,
          borderRadius: NexusRadii.xlRadius,
          border: Border.all(
            color: NexusColors.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: dragging
              ? [
                  BoxShadow(
                    color: NexusColors.onSurface.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.tag.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.1),
                  borderRadius: NexusRadii.smRadius,
                ),
                child: Text(
                  task.tag.toUpperCase(),
                  style: NexusTypography.labelSm.copyWith(
                    color: tagColor,
                    letterSpacing: 0.05 * 11,
                  ),
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
            ],
            Text(
              task.title,
              style: NexusTypography.bodyLg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (task.plainDescription.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.xs),
              Text(
                task.plainDescription,
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                if (task.priority.isNotEmpty)
                  NexusChip(label: task.priority, color: tagColor),
                const Spacer(),
                if (task.dueDate != null) ...[
                  const Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: NexusColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${task.dueDate!.month}/${task.dueDate!.day}',
                    style: NexusTypography.labelMd,
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                InkWell(
                  onTap: onDelete,
                  borderRadius: NexusRadii.fullRadius,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: NexusRadii.xlRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(
              color: NexusColors.outlineVariant,
              style: BorderStyle.solid,
            ),
            borderRadius: NexusRadii.xlRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, size: 18),
              const SizedBox(width: NexusSpacing.xs),
              Text('Add Task', style: NexusTypography.labelMd),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddColumnButton extends StatelessWidget {
  const _AddColumnButton({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAdd,
            borderRadius: NexusRadii.xlRadius,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(
                  color: NexusColors.outlineVariant,
                  style: BorderStyle.solid,
                ),
                borderRadius: NexusRadii.xlRadius,
                color: NexusColors.surfaceContainerLow.withValues(alpha: 0.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 20),
                  const SizedBox(width: NexusSpacing.xs),
                  Text(
                    'Add another list',
                    style: NexusTypography.bodyLg.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog({
    required this.defaultStatus,
    required this.columns,
    required this.onSave,
  });

  final String defaultStatus;
  final List<TaskColumn> columns;
  final ValueChanged<TaskModel> onSave;

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  late final TextEditingController _title;
  final _description = TextEditingController();
  final _tag = TextEditingController();
  final _priority = TextEditingController();
  late String _status;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _status = widget.defaultStatus;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexusColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Text('New Task', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NexusInput(labelText: 'Title', controller: _title),
            const SizedBox(height: NexusSpacing.md),
            NexusInput(
              labelText: 'Description',
              controller: _description,
              maxLines: 3,
            ),
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Expanded(
                  child: NexusInput(labelText: 'Tag', controller: _tag),
                ),
                const SizedBox(width: NexusSpacing.md),
                Expanded(
                  child: NexusInput(
                    labelText: 'Priority',
                    controller: _priority,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: 'List',
                border: OutlineInputBorder(borderRadius: NexusRadii.mdRadius),
              ),
              items: widget.columns
                  .map(
                    (c) =>
                        DropdownMenuItem(value: c.status, child: Text(c.title)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        NexusButton(
          label: 'Create',
          onPressed: () {
            final now = DateTime.now();
            widget.onSave(
              TaskModel(
                title: _title.text,
                description: _description.text,
                tag: _tag.text,
                priority: _priority.text,
                status: _status,
                createdAt: now,
                updatedAt: now,
              ),
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

extension _TaskModelHelpers on TaskModel {
  /// Returns a plain-text fallback of the description for previews.
  String get plainDescription {
    try {
      final json = jsonDecode(description) as Map<String, dynamic>;
      final ops = json['ops'] as List<dynamic>?;
      if (ops == null) return description;
      final buffer = StringBuffer();
      for (final op in ops) {
        final map = op as Map<String, dynamic>;
        buffer.write(map['insert'] ?? '');
      }
      return buffer.toString().trim();
    } catch (_) {
      return description;
    }
  }
}
