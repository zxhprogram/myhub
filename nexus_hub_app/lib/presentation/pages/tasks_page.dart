import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/task_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_input.dart';
import '../components/nexus_rich_text_editor.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.background,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (single-line toolbar for desktop density)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Tasks', style: NexusTypography.headlineLg),
                  const SizedBox(width: NexusSpacing.sm),
                  Text(
                    'Manage your work across the board',
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
              NexusButton(
                label: 'New Task',
                icon: RadixIcons.plus,
                onPressed: () =>
                    _showAddDialog(context, _state.columns.value.first.status),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                      color: colorScheme.destructive,
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
                              right: NexusSpacing.md,
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
                    width: selected != null ? 380 : 0,
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
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => _AddTaskDialog(
          defaultStatus: defaultStatus,
          columns: _state.columns.value,
          onSave: (task) => _state.add(task),
        ),
      ),
    );
  }

  void _showAddColumnDialog(BuildContext context) {
    final controller = TextEditingController();
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) {
          return AlertDialog(
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
              Button.text(
                onPressed: () => closeOverlay<void>(context),
                child: const Text('Cancel'),
              ),
              NexusButton(
                label: 'Add',
                onPressed: () {
                  final title = controller.text.trim();
                  if (title.isNotEmpty) {
                    _state.addColumn(title);
                  }
                  closeOverlay<void>(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteColumn(TaskColumn column) {
    final fallback = _state.columns.value.firstWhere(
      (c) => c.status != column.status,
      orElse: () => column,
    );
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) {
          return AlertDialog(
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
              Button.text(
                onPressed: () => closeOverlay<void>(context),
                child: const Text('Cancel'),
              ),
              Button.destructive(
                onPressed: fallback.status == column.status
                    ? null
                    : () {
                        closeOverlay<void>(context);
                        _state.deleteColumn(column);
                      },
                child: const Text('Delete'),
              ),
            ],
          );
        },
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
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
            child: Row(
              children: [
                Text(
                  column.title,
                  style: NexusTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: NexusSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.accent,
                    borderRadius: NexusRadii.fullRadius,
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => showOverlay(
                    context,
                    PopoverConfiguration(
                      alignment: Alignment.center,
                      anchorAlignment: Alignment.bottomRight,
                      builder: (context) => MenuPopup(
                        children: [
                          MenuButton(
                            leading: const Icon(LucideIcons.trash2, size: 18),
                            onPressed: (context) => onDeleteColumn(),
                            child: Text(
                              'Delete list',
                              style: NexusTypography.bodyMd,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      LucideIcons.ellipsis,
                      size: 18,
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
          // Cards area (drag target + scrollable list)
          Expanded(
            child: DragTarget<TaskModel>(
              onAcceptWithDetails: (details) => onMoveTask(details.data),
              builder: (context, candidateData, rejectedData) {
                final isHovering = candidateData.isNotEmpty;
                return Container(
                  decoration: BoxDecoration(
                    color: isHovering
                        ? colorScheme.accent.withValues(
                            alpha: 0.6,
                          )
                        : colorScheme.muted.withValues(
                            alpha: 0.4,
                          ),
                    borderRadius: NexusRadii.lgRadius,
                    border: isHovering
                        ? Border.all(
                            color: colorScheme.secondary.withValues(alpha: 0.5),
                            width: 2,
                          )
                        : null,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(6),
                    children: [
                      ...tasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
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
      feedback: SizedBox(
          width: 276,
          child: _TaskCard(task: task, dragging: true, onTap: onTap),
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

  Color _tagColor(ColorScheme colorScheme, String tag) {
    return switch (tag.toLowerCase()) {
      'design' => const Color(0xFF7C3AED),
      'backend' => colorScheme.foreground,
      'frontend' => colorScheme.primary,
      'research' => const Color(0xFF2563EB),
      _ => colorScheme.border,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagColor = _tagColor(colorScheme, task.tag);
    return GestureDetector(
  onTap: onTap,
  child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.card,
          borderRadius: NexusRadii.lgRadius,
          border: Border.all(
            color: colorScheme.border.withValues(alpha: 0.5),
          ),
          boxShadow: dragging
              ? [
                  BoxShadow(
                    color: colorScheme.foreground.withValues(alpha: 0.15),
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
              const SizedBox(height: 6),
            ],
            Text(
              task.title,
              style: NexusTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (task.plainDescription.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.xs),
              Text(
                task.plainDescription,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: NexusSpacing.sm),
            Row(
              children: [
                if (task.priority.isNotEmpty)
                  NexusChip(label: task.priority, color: tagColor),
                const Spacer(),
                if (task.dueDate != null) ...[
                  Icon(
                    LucideIcons.calendar,
                    size: 14,
                    color: colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${task.dueDate!.month}/${task.dueDate!.day}',
                    style: NexusTypography.labelMd,
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                GestureDetector(
  onTap: onDelete,
  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 16,
                      color: colorScheme.mutedForeground,
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
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onPressed,
  child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.border,
              style: BorderStyle.solid,
            ),
            borderRadius: NexusRadii.lgRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(RadixIcons.plus, size: 16),
              const SizedBox(width: NexusSpacing.xs),
              Text('Add Task', style: NexusTypography.labelMd),
            ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
  onTap: onAdd,
  child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.border,
                  style: BorderStyle.solid,
                ),
                borderRadius: NexusRadii.lgRadius,
                color: colorScheme.muted.withValues(alpha: 0.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(RadixIcons.plus, size: 18),
                  const SizedBox(width: NexusSpacing.xs),
                  Text(
                    'Add another list',
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
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
  String _descriptionDelta = '';
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
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('New Task', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(labelText: 'Title', controller: _title),
              const SizedBox(height: NexusSpacing.sm),
              Text(
                'Description',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: NexusSpacing.xs),
              SizedBox(
                height: 200,
                child: NexusRichTextEditor(
                  onChanged: (value) => _descriptionDelta = value,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: NexusInput(labelText: 'Tag', controller: _tag),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  Expanded(
                    child: NexusInput(
                      labelText: 'Priority',
                      controller: _priority,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.sm),
              Select<String>(
                value: _status,
                itemBuilder: (context, value) => Text(
                  widget.columns
                      .firstWhere((c) => c.status == value)
                      .title,
                ),
                popup: SelectPopup(
                  items: SelectItemList(
                    children: [
                      for (final c in widget.columns)
                        SelectItem(
                          value: c.status,
                          builder: (context) => Text(c.title),
                        ),
                    ],
                  ),
                ),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        Button.text(
          onPressed: () => closeOverlay<void>(context),
          child: const Text('Cancel'),
        ),
        NexusButton(
          label: 'Create',
          onPressed: () {
            final now = DateTime.now();
            widget.onSave(
              TaskModel(
                title: _title.text,
                description: _descriptionDelta,
                tag: _tag.text,
                priority: _priority.text,
                status: _status,
                createdAt: now,
                updatedAt: now,
              ),
            );
            closeOverlay<void>(context);
          },
        ),
      ],
    );
  }
}
