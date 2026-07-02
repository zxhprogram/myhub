import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/presentation/components/nexus_rich_text_editor.dart';

void main() {
  testWidgets('initializes with provided Delta JSON', (tester) async {
    const deltaJson =
        '{"ops":[{"insert":"Hello "},{"insert":"world","attributes":{"bold":true}},{"insert":"\\n"}]}';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        supportedLocales: const [Locale('en', 'US')],
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
