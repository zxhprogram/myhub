import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/presentation/components/nexus_json_formatter.dart';
import 'package:nexus_hub_app/theme/app_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
}

Future<void> _pumpFormatter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShadcnApp(
      theme: NexusAppTheme.shadcnLight,
      home: const Scaffold(child: NexusJsonFormatter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state renders placeholder', (tester) async {
    await _pumpFormatter(tester);
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('GRID'), findsOneWidget);
    expect(find.textContaining('Click Format or Validate'), findsOneWidget);
  });

  testWidgets('sample loads, formats editor and renders grid columns', (
    tester,
  ) async {
    await _pumpFormatter(tester);

    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();

    // Editor was formatted and validated.
    expect(_richTextContaining('Valid JSON'), findsOneWidget);
    // Root table headers (union of object keys) are rendered.
    expect(find.text('match'), findsWidgets);
    expect(find.text('forcedOnly'), findsWidgets);
    // Breadcrumb summarises the unwrapped root.
    expect(find.text('completions[10]'), findsOneWidget);
    // Scalar cells show booleans; collapsed container cells show chips.
    expect(_richTextContaining('true'), findsWidgets);
    expect(_richTextContaining('false'), findsWidgets);
    expect(find.text('meta{2}'), findsOneWidget);
  });

  testWidgets('nested containers expand and collapse in place', (tester) async {
    await _pumpFormatter(tester);
    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();

    // Expand the first row's match[2] cell.
    await tester.tap(find.text('match[2]').first);
    await tester.pumpAndSettle();

    // Inner single-column table shows the string elements.
    expect(_richTextContaining('"has:"'), findsWidgets);
    expect(find.text('match[2]'), findsWidgets); // chip stays, now [-]

    // Collapse again.
    await tester.tap(find.text('match[2]').first);
    await tester.pumpAndSettle();
    expect(_richTextContaining('"has:"'), findsNothing);

    // Expand the object-valued meta cell in the dependency row.
    await tester.ensureVisible(find.text('meta{2}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('meta{2}'));
    await tester.pumpAndSettle();
    expect(find.text('counts{3}'), findsOneWidget);
    expect(find.text('resolved[3]'), findsOneWidget);
  });

  testWidgets('expand all and collapse all work without layout errors', (
    tester,
  ) async {
    await _pumpFormatter(tester);
    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Expand All'));
    await tester.pumpAndSettle();
    expect(find.text('counts{3}'), findsOneWidget);
    expect(_richTextContaining('"path"'), findsWidgets);

    await tester.tap(find.text('Collapse All'));
    await tester.pumpAndSettle();
    expect(find.text('counts{3}'), findsNothing);
  });

  testWidgets('grid search filters rows to matching subtrees', (tester) async {
    await _pumpFormatter(tester);
    await tester.tap(find.text('Sample'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Filter rows by key or value...'),
      'flutter',
    );
    await tester.pumpAndSettle();

    expect(_richTextContaining('flutter-favorite'), findsWidgets);
    // Rows that do not match anywhere are filtered out.
    expect(_richTextContaining('"publisher:"'), findsNothing);
  });

  testWidgets('invalid JSON shows error banner with position', (tester) async {
    await _pumpFormatter(tester);

    await tester.enterText(
      find.byType(TextField).first,
      '{"a": 1,,}',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Validate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid JSON'), findsOneWidget);
  });
}
