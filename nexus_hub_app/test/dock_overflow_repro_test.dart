import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test: the macOS-style dock used to overflow by 2px.
///
/// The dock's icon column needs 56px of vertical content space (48 icon +
/// 4 dot margin + 4 dot). With height 72 + vertical padding 8, the decoration
/// border shrink leaves only ~54px, so a RenderFlex overflowed by 2px.
///
/// Height 80 + vertical padding 10 guarantees >= 56px of content space.
void main() {
  Future<bool> hasOverflow(WidgetTester tester, Widget dock) async {
    FlutterError? caught;
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      caught = d.exception as FlutterError?;
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [Positioned(bottom: 8, left: 0, right: 0, child: dock)]),
      ),
    ));
    FlutterError.onError = old;
    return caught != null;
  }

  Widget dockIcon() => Container(width: 48, height: 48);

  Widget activeDot() => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.only(top: 4),
      );

  Future<bool> dockOverflow(WidgetTester tester, {required double height, required double padding}) {
    return hasOverflow(
      tester,
      Center(
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: padding),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < 10; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Column(mainAxisSize: MainAxisSize.min, children: [dockIcon(), activeDot()]),
            ],
          ]),
        ),
      ),
    );
  }

  testWidgets('dock at height 72 overflows by 2px', (tester) async {
    expect(await dockOverflow(tester, height: 72, padding: 8), isTrue,
        reason: '72px height + 8px padding leaves too little room for the icon dot.');
  });

  testWidgets('dock at height 80 does not overflow', (tester) async {
    expect(await dockOverflow(tester, height: 80, padding: 10), isFalse,
        reason: '80px height + 10px padding should host the 56px dock icon column comfortably.');
  });
}