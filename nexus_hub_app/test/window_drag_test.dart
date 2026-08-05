import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Guards the controlled-window drag bug in shadcn_flutter 0.0.53.
///
/// Root cause: `shadcn.Window.controlled(...)` leaves `Window.alwaysOnTop ==
/// null`, so during a drag the low-level `_WindowLayerGroup` (private, in the
/// package) drops the dragged window from the tree because its raw nullable
/// flag never equals the layer's non-null `alwaysOnTop`. The pan recognizers
/// are disposed mid-gesture without firing `onPanEnd`/`onPanCancel`, and
/// `_draggingWindow` stays stuck on that window forever, leaving it invisible
/// but "open".
///
/// This test drives the real UI. On a shadcn_flutter upgrade that already
/// fixes the bug it should be dropped.
void main() {
  testWidgets('dragging a controlled window keeps it visible', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navigatorKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: shadcn.ShadcnLayer(
          theme: const shadcn.ThemeData(radius: 0.5, scaling: 1),
          child: Material(
            type: MaterialType.transparency,
            child: shadcn.WindowNavigator(
              key: navigatorKey,
              initialWindows: const [],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    // Push a controlled window (exactly what desktop_environment.dart does).
    final controller = shadcn.WindowController(
      bounds: const Rect.fromLTWH(60, 40, 900, 600),
      resizable: true,
      draggable: true,
    );
    final window = shadcn.Window.controlled(
      controller: controller,
      title: const Text('Test Window'),
      content: const ColoredBox(color: Colors.blue),
    );
    final navigatorState =
        navigatorKey.currentState! as shadcn.WindowNavigatorHandle;
    navigatorState.pushWindow(window);
    await tester.pumpAndSettle();

    final titleFinder = find.text('Test Window');
    expect(titleFinder, findsOneWidget);

    // Drag the title bar. The intermediate pumps let the navigator rebuild
    // (and, with the bug, drop the window from the tree) while the pointer is
    // still down.
    final gesture = await tester.startGesture(tester.getCenter(titleFinder));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // The window must still be visible after the drag.
    expect(titleFinder, findsOneWidget);

    // And it must still be mounted / controllable.
    expect(window.mounted, isTrue);
    expect(controller.mounted, isTrue);
  });
}