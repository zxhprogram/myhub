import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'zhihu_ui.dart';

/// Surfaces the given [child] with a header bar comprising an optional back
/// button, a title, and trailing [actions].
///
/// Used as the invariant right-hand pane of the Zhihu sub-app's wide (two
/// column) layout, both by [ZhihuHotPage]'s own wide mode and — via a
/// [ZhihuShadcnHost] — by the standalone detail pages, so that full-screen
/// navigation and the embedded pane share one visual container.
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

  /// Falls back to [subtitle] when null (the detail pages keep their own
  /// header in standalone mode).
  final String? title;

  /// Optional secondary header line, shown under the title on wide panes.
  final String? subtitle;

  /// When non-null the header shows a back button.
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
    final theme = Theme.of(context);
    final content = enableScroll
        ? SingleChildScrollView(
            padding: ZhihuDense.pagePadding,
            child: child,
          )
        : (expandChild
            ? SizedBox.expand(child: child)
            : SizedBox(width: double.infinity, child: child));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton.ghost(
                  icon: const Icon(LucideIcons.arrowLeft, size: 16),
                  size: ButtonSize.small,
                  onPressed: onBack,
                ),
                const Gap(2),
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
                      style: theme.typography.small.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && title != null) ...[
                      const Gap(1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.xSmall.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(4),
              ...actions,
            ],
          ),
        ),
        Container(height: 1, color: theme.colorScheme.border),
        Expanded(child: content),
      ],
    );
  }
}
