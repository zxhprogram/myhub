import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/app.dart';

void main() {
  testWidgets('App renders shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NexusHubApp());
    // The desktop shell renders the application icons on the desktop.
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
