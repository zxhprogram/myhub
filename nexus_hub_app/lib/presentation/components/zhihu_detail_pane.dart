import 'package:flutter/material.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// A [PrimaryScrollController] key shared by the detail panes that embed a
/// self-scrolling body (answers list, article/feed lists). The pane header
/// is exposed through [ZhihuDetailPane] only when the body supplies its own
/// scrollable; the key lets the body's scrollable adopt the pane-level
/// scroll state so `Scrollbar`s (`ListView` default) and page-level
/// scroll-to actions keep working inside the pane.
final GlobalKey<ScrollableState> zhihuPaneScrollKey = GlobalKey<ScrollableState>();

/// Surfaces the given [child] with a header bar comprising an optional back
/// button, a title, and trailing [actions].
///
/// Used as the invariant right-hand pane of the Zhihu sub-app's wide (two
/// column) layout, both by [ZhihuHotPage]'s own wide mode and — inside a
/// [Scaffold] with `pane: true` — by the standalone detail pages, so that
/// full-screen navigation and the embedded pane share one visual container.
///
/// When the [child] does not provide its own scrollable (e.g. question
/// answers render a self-scrolling [ListView]), pass [enableScroll] as
/// false; [ZhihuDetailPane] then stays out of the way and lets the child's
/// scrollable be the one the page-level scroll keys attach to.
class ZhihuDetailPane extends StatelessWidget {
  const ZhihuDetailPane({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.enableScroll = true,
    this.expandChild = false,
  });

  /// Falls back to [subtitle] when null (the detail pages keep their
  /// Scaffold app bars in standalone mode).
  final String? title;

  /// Optional secondary header line, shown under the title on wide panes.
  final String? subtitle;

  /// When non-null the header shows a back button and the app bar's own
  /// leading is replaced, keeping a single back affordance.
  final VoidCallback? onBack;

  final List<Widget> actions;
  final Widget child;
  final bool enableScroll;

  /// Forces the [child] to fill the remaining pane height even when the
  /// child itself would otherwise shrink-wrap (e.g. a [ListView] under an
  /// unbounded constraint). Keep in sync with [enableScroll]: a child that
  /// is its own scrollable needs `expandChild: true` to be given a finite
  /// viewport; a scaffolded child (loading/empty states) expands naturally
  /// inside a scroll view and should leave it false.
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = enableScroll
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(NexusSpacing.md),
            child: child,
          )
        : (expandChild
            ? SizedBox.expand(child: child)
            : SizedBox(width: double.infinity, child: child));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexusSpacing.sm,
            NexusSpacing.sm,
            NexusSpacing.sm,
            NexusSpacing.sm,
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  tooltip: '返回',
                  onPressed: onBack,
                ),
                const SizedBox(width: NexusSpacing.xs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title ?? subtitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NexusTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && title != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexusTypography.labelSm.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              ...actions,
            ],
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          color: Color(0x33000000),
        ),
        Expanded(
          child: content,
        ),
      ],
    );
  }
}