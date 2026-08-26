import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A [Window.controlled] variant that pins `alwaysOnTop` to a non-null value.
///
/// Workaround for a controlled-window drag bug in published shadcn_flutter
/// 0.0.53: `Window.controlled(...)` hard-codes `alwaysOnTop = null`, and while
/// a window is being dragged the navigator renders it only in the layer whose
/// flag equals the raw `alwaysOnTop` value. `null` matches neither the
/// background layer (`false`) nor the top layer (`true`), so the dragged
/// window disappears from the tree mid-gesture; its pan recognizer is then
/// disposed without firing `onPanEnd`, the drag state gets stuck, and the
/// window stays invisible while still "open".
///
/// Overriding the getter to a non-null `false` keeps the dragged window in
/// the background layer. Drop this class when upgrading to a shadcn_flutter
/// version that already fixes the bug (see test/window_drag_test.dart).
class ControlledWindow extends Window {
  ControlledWindow({
    required super.controller,
    super.title,
    super.actions,
    super.content,
  }) : super.controlled();

  @override
  // ignore: overridden_fields
  bool get alwaysOnTop => false;
}
