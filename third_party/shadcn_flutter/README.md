# shadcn_flutter (vendored)

This is a vendored copy of `shadcn_flutter 0.0.53` (from pub.dev), pinned via
`dependency_overrides` in `nexus_hub_app/pubspec.yaml`.

## Why it's vendored

The published 0.0.53 package has a bug: dragging the **first** controlled window
(`Window.controlled`) makes it disappear from the window navigator mid-gesture,
leaving it invisible while the app still tracks it as open. The dock shows it
as active but the desktop is empty.

This copy ships a small fix on top of the published package. The change is in
`lib/src/components/layout/window.dart` (private `_WindowLayerGroup`):

```diff
-  if (handle._draggingWindow.value != null &&
-      handle._draggingWindow.value!.window.alwaysOnTop == alwaysOnTop)
+  if (handle._draggingWindow.value != null &&
+      _isAlwaysOnTop(handle._draggingWindow.value!.window) == alwaysOnTop)
```

plus an `_isAlwaysOnTop(Window)` helper that coalesces
`alwaysOnTop ?? controller?.value.alwaysOnTop ?? false`. `Window.controlled`
leaves `alwaysOnTop == null`, so the raw comparison never matched the layer's
non-null `bool`, and the dragged window was dropped from the tree.

## When this can be deleted

When an upgraded `shadcn_flutter` already contains this fix (or you choose to
switch to uncontrolled `Window` widgets), remove the `dependency_overrides`
block from `nexus_hub_app/pubspec.yaml`, delete this directory, and drop
`test/window_drag_test.dart`. Verify with `flutter pub get` + `flutter test`.
