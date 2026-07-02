import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(body: TaskDetailPanel(state: state)),
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
