import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/task_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_input.dart';
import '../components/nexus_rich_text_editor.dart';
import '../states/tasks_state.dart';

class TaskDetailPanel extends StatefulWidget {
  const TaskDetailPanel({super.key, required this.state});

  final TasksState state;

  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  bool _isEditing = false;
  bool _isSaving = false;
  late final TextEditingController _titleController;
  late final TextEditingController _tagController;
  late final TextEditingController _priorityController;
  String _descriptionDelta = '';

  @override
  void initState() {
    super.initState();
    final task = widget.state.selectedTask.value;
    _titleController = TextEditingController(text: task?.title ?? '');
    _tagController = TextEditingController(text: task?.tag ?? '');
    _priorityController = TextEditingController(text: task?.priority ?? '');
    _descriptionDelta = task?.description ?? '';
  }

  @override
  void didUpdateWidget(covariant TaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final task = widget.state.selectedTask.value;
    if (task != null && !_isEditing && !_isSaving) {
      _titleController.text = task.title;
      _tagController.text = task.tag;
      _priorityController.text = task.priority;
      _descriptionDelta = task.description;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final task = widget.state.selectedTask.value;
    if (task == null) return;
    setState(() => _isSaving = true);
    final updated = task.copyWith(
      title: _titleController.text,
      description: _descriptionDelta,
      tag: _tagController.text,
      priority: _priorityController.text,
      updatedAt: DateTime.now(),
    );
    await widget.state.updateTask(updated);
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
    }
  }

  void _close() {
    widget.state.selectTask(null);
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final task = widget.state.selectedTask.value;
      if (task == null) return const SizedBox.shrink();

      return FocusTraversalGroup(
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => _close(),
              ),
            },
            child: Container(
              width: 380,
              color: NexusColors.surfaceContainerLowest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(task),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isEditing)
                            NexusInput(
                              labelText: 'Title',
                              controller: _titleController,
                            )
                          else
                            Text(task.title, style: NexusTypography.headlineSm),
                          const SizedBox(height: NexusSpacing.sm),
                          _buildMetaRow(),
                          const SizedBox(height: 12),
                          Text(
                            'Description',
                            style: NexusTypography.labelMd.copyWith(
                              color: NexusColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: NexusSpacing.xs),
                          SizedBox(
                            height: 320,
                            child: NexusRichTextEditor(
                              initialDeltaJson: _descriptionDelta,
                              onChanged: (value) => _descriptionDelta = value,
                              readOnly: !_isEditing,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isSaving) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildHeader(TaskModel task) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Task Details',
              style: NexusTypography.labelSm.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ),
          if (!_isEditing)
            NexusButton(
              label: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            )
          else ...[
            NexusButton(
              label: 'Cancel',
              variant: NexusButtonVariant.text,
              onPressed: () => setState(() => _isEditing = false),
            ),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(
              label: _isSaving ? 'Saving...' : 'Save',
              onPressed: _isSaving ? null : _save,
            ),
          ],
          const SizedBox(width: NexusSpacing.sm),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Close',
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The panel animates its width in from 0, so during the transition
        // maxWidth can be smaller than the gutter; keep widths non-negative.
        final itemWidth = math.max(
          0.0,
          (constraints.maxWidth - NexusSpacing.sm) / 2,
        );
        return Row(
          children: [
            SizedBox(
              width: itemWidth,
              child: _isEditing
                  ? NexusInput(labelText: 'Tag', controller: _tagController)
                  : _MetaChip(label: 'Tag', value: _tagController.text),
            ),
            const SizedBox(width: NexusSpacing.sm),
            SizedBox(
              width: itemWidth,
              child: _isEditing
                  ? NexusInput(
                      labelText: 'Priority',
                      controller: _priorityController,
                    )
                  : _MetaChip(
                      label: 'Priority',
                      value: _priorityController.text,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainer,
        borderRadius: NexusRadii.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : '-',
            style: NexusTypography.bodyMd,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
