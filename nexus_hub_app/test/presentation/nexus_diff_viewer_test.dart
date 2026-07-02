import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/presentation/components/nexus_diff_viewer.dart';

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
}

void main() {
  testWidgets('loads sample and renders modified text in diff output', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: NexusDiffViewer())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();

    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Modified'), findsOneWidget);
    expect(_richTextContaining('San Francisco'), findsOneWidget);
    expect(_richTextContaining('New York'), findsOneWidget);
    expect(_richTextContaining('age'), findsWidgets);
  });
}
