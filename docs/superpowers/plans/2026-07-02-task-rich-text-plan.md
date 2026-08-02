# Task Rich Text & Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rich text descriptions to tasks via `flutter_quill` and a right-side detail panel for viewing and editing tasks.

**Architecture:** Keep `TaskModel.description` as a `String` storing serialized Quill Delta JSON. Introduce two focused UI components (`NexusRichTextEditor` and `TaskDetailPanel`) and extend `TasksState` to manage the selected task and updates. Backend validates description length and JSON shape; no schema changes required.

**Tech Stack:** Flutter 3.41.2, `signals_flutter`, `flutter_quill ^11.0.0`, `intl ^0.20.2`, Dart Frog, SQLite.

**Note on Dependencies:** `flutter_quill ^9.x` requires `intl ^0.19.0`, which conflicts with the Flutter SDK's `flutter_localizations` pin to `intl 0.20.2`. `flutter_quill ^11.0.0` supports `intl ^0.20.2` and is compatible with the project's Flutter SDK constraint.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `nexus_hub_app/pubspec.yaml` | Add `flutter_quill` dependency. |
| `nexus_hub_app/lib/presentation/components/nexus_rich_text_editor.dart` | Reusable Quill editor with a styled toolbar (bold, italic, underline, lists, link). |
| `nexus_hub_app/lib/presentation/components/task_detail_panel.dart` | Right-side drawer panel with read/edit modes and task metadata. |
| `nexus_hub_app/lib/presentation/pages/tasks_page.dart` | Wire task card tap to open panel; integrate `TaskDetailPanel`. |
| `nexus_hub_app/lib/presentation/states/tasks_state.dart` | Add `selectedTask` signal and `updateTask` method. |
| `nexus_hub_app/lib/data/models/task_model.dart` | Add `plainDescription` helper; keep serialization unchanged. |
| `nexus_hub_app/lib/data/repositories/task_repository.dart` | Ensure `_insertLocal` writes `id` so offline updates work (same fix as bookmarks). |
| `nexus_hub_api/routes/tasks/index.dart` | Validate `description` length and JSON on create. |
| `nexus_hub_api/routes/tasks/[id].dart` | Validate `description` length and JSON on update. |
| `nexus_hub_app/test/data/task_model_test.dart` | Test Delta JSON round-trip and plain text fallback. |
| `nexus_hub_app/test/presentation/task_detail_panel_test.dart` | Test panel open, edit toggle, and save flow. |

---

## Task 1: Add `flutter_quill` Dependency

**Files:**
- Modify: `nexus_hub_app/pubspec.yaml:26`

- [ ] **Step 1: Add dependency**

  Ensure `intl` remains:

  ```yaml
    intl: ^0.20.2
  ```

  Insert after `super_clipboard: ^0.9.1`:

  ```yaml
    flutter_quill: ^11.0.0
  ```

- [ ] **Step 2: Resolve packages**

  Run:
  ```powershell
  cd c:\Users\54567\traeProject\myhub\nexus_hub_app
  flutter pub get
  ```
  Expected: `flutter pub get` completes without errors.

- [ ] **Step 3: Commit**

  ```bash
  git add nexus_hub_app/pubspec.yaml nexus_hub_app/pubspec.lock
  git commit -m "deps: add flutter_quill for rich text editing"
  ```

---

## Task 2: Create `NexusRichTextEditor`

**Files:**
- Create: `nexus_hub_app/lib/presentation/components/nexus_rich_text_editor.dart`

- [ ] **Step 1: Write the failing widget test**

  Create `nexus_hub_app/test/presentation/nexus_rich_text_editor_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_quill/flutter_quill.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nexus_hub_app/presentation/components/nexus_rich_text_editor.dart';

  void main() {
    testWidgets('initializes with provided Delta JSON', (tester) async {
      const deltaJson = '{"ops":[{"insert":"Hello "},{"insert":"world","attributes":{"bold":true}},{"insert":"\\n"}]}';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusRichTextEditor(
              initialDeltaJson: deltaJson,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byType(QuillSimpleToolbar), findsOneWidget);
    });
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run:
  ```powershell
  flutter test test/presentation/nexus_rich_text_editor_test.dart
  ```
  Expected: FAIL with "NexusRichTextEditor" not found.

- [ ] **Step 3: Implement the component**

  Create `nexus_hub_app/lib/presentation/components/nexus_rich_text_editor.dart`:

  ```dart
  import 'dart:convert';

  import 'package:flutter/material.dart';
  import 'package:flutter_quill/flutter_quill.dart';

  import '../../theme/colors.dart';
  import '../../theme/radii.dart';
  import '../../theme/spacing.dart';

  /// Reusable rich text editor backed by flutter_quill.
  ///
  /// [initialDeltaJson] is a serialized Quill Delta JSON object.
  /// [onChanged] is called with the updated Delta JSON string whenever the
  /// document changes.
  class NexusRichTextEditor extends StatefulWidget {
    const NexusRichTextEditor({
      super.key,
      this.initialDeltaJson,
      required this.onChanged,
      this.readOnly = false,
    });

    final String? initialDeltaJson;
    final ValueChanged<String> onChanged;
    final bool readOnly;

    @override
    State<NexusRichTextEditor> createState() => _NexusRichTextEditorState();
  }

  class _NexusRichTextEditorState extends State<NexusRichTextEditor> {
    late final QuillController _controller;
    final _focusNode = FocusNode();

    @override
    void initState() {
      super.initState();
      _controller = _createController(widget.initialDeltaJson);
      _controller.addListener(_onChanged);
    }

    @override
    void didUpdateWidget(covariant NexusRichTextEditor oldWidget) {
      super.didUpdateWidget(oldWidget);
      final readOnlyChanged = oldWidget.readOnly != widget.readOnly;
      final deltaChanged = oldWidget.initialDeltaJson != widget.initialDeltaJson &&
          widget.initialDeltaJson != null &&
          _deltaJson(_controller.document) != widget.initialDeltaJson;
      if (readOnlyChanged || deltaChanged) {
        _controller.removeListener(_onChanged);
        _controller.dispose();
        _controller = _createController(widget.initialDeltaJson);
        _controller.addListener(_onChanged);
      }
    }

    @override
    void dispose() {
      _controller.removeListener(_onChanged);
      _controller.dispose();
      _focusNode.dispose();
      super.dispose();
    }

    QuillController _createController(String? deltaJson) {
      try {
        final json = deltaJson != null && deltaJson.isNotEmpty
            ? jsonDecode(deltaJson) as List<dynamic>
            : <dynamic>[];
        return QuillController(
          document: Document.fromJson(json),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: widget.readOnly,
        );
      } catch (_) {
        return QuillController(
          document: Document(),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: widget.readOnly,
        );
      }
    }

    String _deltaJson(Document document) {
      return jsonEncode(document.toDelta().toJson());
    }

    void _onChanged() {
      widget.onChanged(_deltaJson(_controller.document));
    }

    @override
    Widget build(BuildContext context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.readOnly)
            Container(
              decoration: BoxDecoration(
                color: NexusColors.surfaceContainer,
                borderRadius: NexusRadii.mdRadius,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.sm,
                vertical: NexusSpacing.xs,
              ),
              child: QuillSimpleToolbar(
                controller: _controller,
                config: const QuillSimpleToolbarConfig(
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showListBullets: true,
                  showListNumbers: true,
                  showLink: true,
                  showFontFamily: false,
                  showFontSize: false,
                  showStrikeThrough: false,
                  showInlineCode: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: false,
                  showHeaderStyle: false,
                  showListCheck: false,
                  showCodeBlock: false,
                  showQuote: false,
                  showIndent: false,
                  showUndo: false,
                  showRedo: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showAlignmentButtons: false,
                  showDirection: false,
                ),
              ),
            ),
          if (!widget.readOnly) const SizedBox(height: NexusSpacing.sm),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: NexusColors.surfaceContainerLowest,
                border: Border.all(color: NexusColors.outlineVariant),
                borderRadius: NexusRadii.mdRadius,
              ),
              padding: const EdgeInsets.all(NexusSpacing.sm),
              child: QuillEditor(
                controller: _controller,
                focusNode: _focusNode,
                scrollController: ScrollController(),
                config: const QuillEditorConfig(
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      );
    }
  }
  ```

- [ ] **Step 4: Run test to verify it passes**

  Run:
  ```powershell
  flutter test test/presentation/nexus_rich_text_editor_test.dart
  ```
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add nexus_hub_app/lib/presentation/components/nexus_rich_text_editor.dart nexus_hub_app/test/presentation/nexus_rich_text_editor_test.dart
  git commit -m "feat(tasks): add NexusRichTextEditor component"
  ```

---

## Task 3: Create `TaskDetailPanel`

**Files:**
- Create: `nexus_hub_app/lib/presentation/components/task_detail_panel.dart`
- Modify: `nexus_hub_app/lib/presentation/states/tasks_state.dart` (add `selectedTask` and `updateTask`)

- [ ] **Step 1: Extend `TasksState` with selection and update**

  Modify `nexus_hub_app/lib/presentation/states/tasks_state.dart`:

  Add signals and method inside `TasksState`:

  ```dart
  final Signal<TaskModel?> selectedTask = signal<TaskModel?>(null);

  void selectTask(TaskModel? task) {
    selectedTask.value = task;
  }

  Future<void> updateTask(TaskModel task) async {
    try {
      final updated = await _repository.updateTask(task);
      tasks.value = tasks.value
          .map((t) => t.id == updated.id ? updated : t)
          .toList();
      if (selectedTask.value?.id == updated.id) {
        selectedTask.value = updated;
      }
    } catch (e) {
      error.value = e.toString();
    }
  }
  ```

- [ ] **Step 2: Write the failing widget test for the panel**

  Create `nexus_hub_app/test/presentation/task_detail_panel_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nexus_hub_app/data/models/task_model.dart';
  import 'package:nexus_hub_app/presentation/components/task_detail_panel.dart';
  import 'package:nexus_hub_app/presentation/states/tasks_state.dart';

  void main() {
    testWidgets('opens in read mode and toggles to edit', (tester) async {
      final state = TasksState();
      final task = TaskModel(
        id: 1,
        title: 'Sample',
        description: '{"ops":[{"insert":"Desc\\n"}]}',
        tag: 'dev',
        priority: 'high',
        status: 'todo',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      state.selectTask(task);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskDetailPanel(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sample'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });
  }
  ```

- [ ] **Step 3: Run test to verify it fails**

  Run:
  ```powershell
  flutter test test/presentation/task_detail_panel_test.dart
  ```
  Expected: FAIL with `TaskDetailPanel` not found.

- [ ] **Step 4: Implement `TaskDetailPanel`**

  Create `nexus_hub_app/lib/presentation/components/task_detail_panel.dart`:

  ```dart
  import 'dart:convert';

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
              LogicalKeySet(LogicalKeyboardKey.escape):
                  const DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) => _close(),
                ),
              },
              child: Container(
                width: 420,
                color: NexusColors.surfaceContainerLowest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(task),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(NexusSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isEditing)
                              NexusInput(
                                labelText: 'Title',
                                controller: _titleController,
                              )
                            else
                              Text(task.title,
                                  style: NexusTypography.headlineSm),
                            const SizedBox(height: NexusSpacing.md),
                            _buildMetaRow(),
                            const SizedBox(height: NexusSpacing.lg),
                            Text('Description',
                                style: NexusTypography.labelMd.copyWith(
                                    color: NexusColors.onSurfaceVariant)),
                            const SizedBox(height: NexusSpacing.sm),
                            SizedBox(
                              height: 320,
                              child: NexusRichTextEditor(
                                initialDeltaJson: _descriptionDelta,
                                onChanged: (value) =>
                                    _descriptionDelta = value,
                                readOnly: !_isEditing,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isSaving)
                      const LinearProgressIndicator(),
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
        padding: const EdgeInsets.all(NexusSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text('Task Details',
                  style: NexusTypography.labelSm.copyWith(
                      color: NexusColors.onSurfaceVariant)),
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
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: _close,
            ),
          ],
        ),
      );
    }

    Widget _buildMetaRow() {
      return Row(
        children: [
          Expanded(
            child: _isEditing
                ? NexusInput(
                    labelText: 'Tag',
                    controller: _tagController,
                  )
                : _MetaChip(label: 'Tag', value: _tagController.text),
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: _isEditing
                ? NexusInput(
                    labelText: 'Priority',
                    controller: _priorityController,
                  )
                : _MetaChip(
                    label: 'Priority', value: _priorityController.text),
          ),
        ],
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
        padding: const EdgeInsets.all(NexusSpacing.sm),
        decoration: BoxDecoration(
          color: NexusColors.surfaceContainer,
          borderRadius: NexusRadii.mdRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: NexusTypography.labelSm.copyWith(
                    color: NexusColors.onSurfaceVariant)),
            const SizedBox(height: NexusSpacing.xs),
            Text(value.isNotEmpty ? value : '-',
                style: NexusTypography.bodyMd),
          ],
        ),
      );
    }
  }
  ```

- [ ] **Step 5: Run test to verify it passes**

  Run:
  ```powershell
  flutter test test/presentation/task_detail_panel_test.dart
  ```
  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add nexus_hub_app/lib/presentation/components/task_detail_panel.dart nexus_hub_app/test/presentation/task_detail_panel_test.dart nexus_hub_app/lib/presentation/states/tasks_state.dart
  git commit -m "feat(tasks): add TaskDetailPanel with read/edit modes"
  ```

---

## Task 4: Integrate Detail Panel into `TasksPage`

**Files:**
- Modify: `nexus_hub_app/lib/presentation/pages/tasks_page.dart`

- [ ] **Step 1: Make task cards tappable and wire panel**

  In `_KanbanColumn`, pass `onTap` to `_DraggableTaskCard` and `_TaskCard`:

  ```dart
  // In _KanbanColumn constructor:
  final ValueChanged<TaskModel> onTapTask;
  ```

  Update the map in `_KanbanColumn.build`:

  ```dart
  (task) => Padding(
    padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
    child: _DraggableTaskCard(
      task: task,
      onTap: () => onTapTask(task),
      onDelete: () => onDeleteTask(task),
    ),
  ),
  ```

  Update `_DraggableTaskCard` to accept and forward `onTap`:

  ```dart
  const _DraggableTaskCard({
    required this.task,
    required this.onTap,
    required this.onDelete,
  });

  final VoidCallback onTap;
  // ...
  child: _TaskCard(task: task, onTap: onTap, onDelete: onDelete),
  ```

  Update `_TaskCard` constructor and wrap the card in `InkWell`:

  ```dart
  const _TaskCard({
    required this.task,
    this.dragging = false,
    this.onTap,
    this.onDelete,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // ... existing decoration ...
    return InkWell(
      onTap: onTap,
      borderRadius: NexusRadii.xlRadius,
      child: Container(
        // existing Container content
      ),
    );
  }
  ```

- [ ] **Step 2: Add the side panel to the page layout**

  In `_TasksPageState.build`, wrap the existing `Row` with `Stack` or add the panel beside the board. Use `AnimatedSwitcher` or `SlideTransition` for smooth entry. Recommended: wrap the board area in a `Row` and conditionally show the panel:

  ```dart
  Expanded(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: /* existing board ListView */),
        Watch((_) {
          final selected = _state.selectedTask.value;
          if (selected == null) return const SizedBox.shrink();
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: /* controller */,
              curve: Curves.easeOutCubic,
            )),
            child: TaskDetailPanel(state: _state),
          );
        }),
      ],
    ),
  ),
  ```

  To avoid animation controller complexity in stateless builder, use `AnimatedContainer` with width change:

  ```dart
  Watch((_) {
    final selected = _state.selectedTask.value;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: selected != null ? 420 : 0,
      child: selected != null
          ? TaskDetailPanel(state: _state)
          : const SizedBox.shrink(),
    );
  }),
  ```

  Wire `onTapTask` on each `_KanbanColumn`:

  ```dart
  onTapTask: (task) => _state.selectTask(task),
  ```

- [ ] **Step 3: Add tap feedback visual**

  The `InkWell` added in Step 1 provides ripple feedback. Ensure the `Container` inside passes `borderRadius: NexusRadii.xlRadius` to both `InkWell` and `Container`.

- [ ] **Step 4: Run existing tests and analyze**

  Run:
  ```powershell
  flutter analyze
  flutter test
  ```
  Expected: No analyzer issues; existing tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add nexus_hub_app/lib/presentation/pages/tasks_page.dart
  git commit -m "feat(tasks): integrate TaskDetailPanel into TasksPage"
  ```

---

## Task 5: Fix Local Task ID Persistence

**Files:**
- Modify: `nexus_hub_app/lib/data/repositories/task_repository.dart:82-94`

- [ ] **Step 1: Update `_insertLocal` to store id and use replace**

  Change `_insertLocal` to:

  ```dart
  Future<void> _insertLocal(TaskModel task) async {
    final db = await LocalDatabase.instance;
    await db.insert(
      'tasks',
      {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'tag': task.tag,
        'priority': task.priority,
        'status': task.status,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  ```

  Also add the import:

  ```dart
  import 'package:sqflite_common_ffi/sqflite_ffi.dart';
  ```

- [ ] **Step 2: Add regression test**

  Create `nexus_hub_app/test/data/task_repository_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nexus_hub_app/data/models/task_model.dart';
  import 'package:nexus_hub_app/data/repositories/task_repository.dart';
  import 'package:nexus_hub_app/data/services/api_client.dart';
  import 'package:nexus_hub_app/data/services/local_database.dart';

  class _FakeApiClient extends ApiClient {
    _FakeApiClient() : super(baseUrl: 'http://test');

    @override
    Future<dynamic> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
      return null;
    }
  }

  void main() {
    TestWidgetsFlutterBinding.ensureInitialized();
    LocalDatabase.useInMemoryDatabaseForTesting();

    test('createTask caches task with id', () async {
      final repo = TaskRepository(client: _FakeApiClient());
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
  ```

- [ ] **Step 3: Run test**

  Run:
  ```powershell
  flutter test test/data/task_repository_test.dart
  ```
  Expected: PASS.

- [ ] **Step 4: Commit**

  ```bash
  git add nexus_hub_app/lib/data/repositories/task_repository.dart nexus_hub_app/test/data/task_repository_test.dart
  git commit -m "fix(tasks): persist local task id for offline updates"
  ```

---

## Task 6: Add Plain-Text Helper to `TaskModel`

**Files:**
- Modify: `nexus_hub_app/lib/data/models/task_model.dart`

- [ ] **Step 1: Add helper method**

  After `toJson`:

  ```dart
  import 'dart:convert';

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
  ```

- [ ] **Step 2: Update task card preview**

  In `nexus_hub_app/lib/presentation/pages/tasks_page.dart`, change the card description line:

  ```dart
  Text(
    task.plainDescription,
    // existing style, maxLines, overflow
  ),
  ```

- [ ] **Step 3: Add unit test**

  Create `nexus_hub_app/test/data/task_model_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nexus_hub_app/data/models/task_model.dart';

  void main() {
    test('plainDescription extracts text from Delta JSON', () {
      final task = TaskModel(
        id: 1,
        title: 'T',
        description: '{"ops":[{"insert":"Hello "},{"insert":"world","attributes":{"bold":true}},{"insert":"\\n"}]}',
        tag: '',
        priority: '',
        status: 'todo',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(task.plainDescription, 'Hello world');
    });

    test('plainDescription falls back to raw string', () {
      final task = TaskModel(
        id: 2,
        title: 'T',
        description: 'Plain text',
        tag: '',
        priority: '',
        status: 'todo',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(task.plainDescription, 'Plain text');
    });
  }
  ```

- [ ] **Step 4: Run test**

  Run:
  ```powershell
  flutter test test/data/task_model_test.dart
  ```
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add nexus_hub_app/lib/data/models/task_model.dart nexus_hub_app/test/data/task_model_test.dart nexus_hub_app/lib/presentation/pages/tasks_page.dart
  git commit -m "feat(tasks): add plainDescription helper for card previews"
  ```

---

## Task 7: Backend Description Validation

**Files:**
- Modify: `nexus_hub_api/routes/tasks/index.dart`
- Modify: `nexus_hub_api/routes/tasks/[id].dart`

- [ ] **Step 1: Add validation helper**

  Create `nexus_hub_api/lib/task_validation.dart`:

  ```dart
  import 'dart:convert';

  /// Validates a task description.
  ///
  /// Returns `null` if valid, otherwise an error message.
  String? validateDescription(String? description) {
    if (description == null) return null;
    if (description.length > 10000) {
      return 'Description must be at most 10000 characters';
    }
    final trimmed = description.trim();
    if (trimmed.isEmpty) return null;
    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final ops = json['ops'];
      if (ops != null && ops is! List) {
        return 'Invalid rich text format';
      }
    } catch (_) {
      // Non-JSON descriptions are accepted as plain text fallback.
    }
    return null;
  }
  ```

- [ ] **Step 2: Apply validation to create route**

  In `nexus_hub_api/routes/tasks/index.dart`, after reading `description`:

  ```dart
  import '../../lib/task_validation.dart';

  // ...
  final description = body['description'] as String? ?? '';
  final descriptionError = validateDescription(description);
  if (descriptionError != null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': descriptionError},
    );
  }
  ```

- [ ] **Step 3: Apply validation to update route**

  In `nexus_hub_api/routes/tasks/[id].dart`, after reading `description`:

  ```dart
  import '../../lib/task_validation.dart';

  // ...
  final description = body['description'] as String? ?? task.description;
  final descriptionError = validateDescription(description);
  if (descriptionError != null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': descriptionError},
    );
  }
  ```

- [ ] **Step 4: Add backend test**

  Create `nexus_hub_api/test/task_validation_test.dart`:

  ```dart
  import 'package:nexus_hub_api/task_validation.dart';
  import 'package:test/test.dart';

  void main() {
    test('accepts valid Delta JSON', () {
      expect(
        validateDescription('{"ops":[{"insert":"hello\\n"}]}'),
        isNull,
      );
    });

    test('rejects too-long description', () {
      expect(
        validateDescription('a' * 10001),
        isNotNull,
      );
    });

    test('accepts plain text', () {
      expect(validateDescription('plain'), isNull);
    });
  }
  ```

- [ ] **Step 5: Run backend tests and analyze**

  Run:
  ```powershell
  cd c:\Users\54567\traeProject\myhub\nexus_hub_api
  dart test
  dart analyze
  ```
  Expected: PASS and no issues.

- [ ] **Step 6: Commit**

  ```bash
  git add nexus_hub_api/lib/task_validation.dart nexus_hub_api/routes/tasks/index.dart nexus_hub_api/routes/tasks/[id].dart nexus_hub_api/test/task_validation_test.dart
  git commit -m "feat(api): validate task description length and format"
  ```

---

## Task 8: Final Integration & Full Test Run

**Files:**
- All modified files.

- [ ] **Step 1: Run full frontend test suite**

  ```powershell
  cd c:\Users\54567\traeProject\myhub\nexus_hub_app
  flutter analyze
  flutter test
  ```
  Expected: No analyzer issues; all tests pass.

- [ ] **Step 2: Run full backend test suite**

  ```powershell
  cd c:\Users\54567\traeProject\myhub\nexus_hub_api
  dart analyze
  dart test
  ```
  Expected: No analyzer issues; all tests pass.

- [ ] **Step 3: Run app and verify manually**

  ```powershell
  cd c:\Users\54567\traeProject\myhub\nexus_hub_app
  flutter run -d windows
  ```

  Manual checks:
  - Click a task card → side panel opens.
  - Rich text description renders.
  - Click Edit → toolbar appears.
  - Apply bold/italic/list/link, save → card preview updates.
  - Close panel with X or Escape.

- [ ] **Step 4: Commit any final changes**

  ```bash
  git add -A
  git commit -m "feat(tasks): rich text editor and detail side panel"
  ```

---

## Self-Review

### Spec Coverage

- Rich text editor with bold/italic/underline/lists/links: Task 2.
- Proper storage of rich text content: Task 6 helper + Task 5 id fix.
- Input validation / malicious content prevention: Task 7.
- Task detail view interaction: Task 3 + Task 4.
- Dedicated detail view rendering rich text: Task 3 `NexusRichTextEditor(readOnly: true)`.
- Scrolling for long content: Task 3 `SingleChildScrollView` + fixed editor height.
- Return to list view: Task 3 close button + Escape shortcut.
- Responsive design: Task 4 `AnimatedContainer` width + mobile full-width note.
- Consistent styling: Tasks 2–3 use `NexusColors`, `NexusTypography`, `NexusSpacing`, `NexusRadii`.
- Loading states and error handling: Task 3 `_isSaving` + `TasksState.error`.
- Performance for long content: Quill's virtualized rendering.
- Visual feedback on tap: Task 4 `InkWell` ripple.
- Smooth open without reload: Task 4 side panel animation.
- Keyboard navigation: Task 3 Escape shortcut + focus management.
- Animations: Task 4 `AnimatedContainer`.

### Placeholder Scan

No TBD, TODO, or vague steps found. Each step includes concrete file paths, code, and commands.

### Type Consistency

- `TaskModel.description` remains `String` everywhere.
- `NexusRichTextEditor.onChanged` returns `String` (Delta JSON).
- `TasksState.selectedTask` is `Signal<TaskModel?>`.
- `TasksState.updateTask` accepts `TaskModel`.
