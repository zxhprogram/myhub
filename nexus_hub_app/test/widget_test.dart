import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/app.dart';

void main() {
  testWidgets('App renders shell', (WidgetTester tester) async {
    await tester.pumpWidget(const NexusHubApp());
    expect(find.text('Nexus Hub'), findsOneWidget);
  });
}
