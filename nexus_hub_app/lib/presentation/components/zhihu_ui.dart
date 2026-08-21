import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared shadcn_flutter-based building blocks for the Zhihu sub-app.

/// Scopes the Zhihu sub-app build. The shadcn theme infrastructure is
/// installed app-wide by `ShadcnApp`, so this host is now a plain builder
/// passthrough kept for call-site stability.
class ZhihuShadcnHost extends StatelessWidget {
  const ZhihuShadcnHost({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: builder);
  }
}

/// Density tokens shared by the Zhihu panes: the sub-app targets the
/// desktop, so paddings and gaps stay tight to keep the information
/// density high.
abstract final class ZhihuDense {
  /// Padding around a whole page/pane.
  static const EdgeInsets pagePadding = EdgeInsets.all(12);

  /// Padding inside a list card.
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 7,
  );

  /// Padding inside a reading (detail) card.
  static const EdgeInsets readingPadding = EdgeInsets.all(14);

  /// Vertical gap between two list cards.
  static const double listGap = 6;

  /// Fixed width of the optional card thumbnail.
  static const double thumbWidth = 84;

  /// Fixed height of the optional card thumbnail.
  static const double thumbHeight = 60;
}

/// Circular author avatar built on the shadcn [Avatar]; falls back to the
/// author's initials on load errors or empty URLs.
class ZhihuAvatar extends StatelessWidget {
  const ZhihuAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 20,
  });

  final String imageUrl;

  /// Author name; used for the initials fallback.
  final String name;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = name.trim().isEmpty ? '知' : name.trim().substring(0, 1);
    if (imageUrl.isEmpty) {
      return Avatar(
        initials: initials,
        size: size,
        backgroundColor: theme.colorScheme.muted,
      );
    }
    return Avatar.network(
      initials: initials,
      photoUrl: imageUrl,
      size: size,
      backgroundColor: theme.colorScheme.muted,
    );
  }
}

/// Compact icon + label metric (voteup counts, timestamps, ...) used in
/// list cards and reading headers.
class ZhihuMetric extends StatelessWidget {
  const ZhihuMetric({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.iconSize = 13,
  });

  final IconData icon;
  final String label;

  /// Text (and icon) color; defaults to the theme's muted foreground.
  final Color? color;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: effective),
        const Gap(3),
        Text(
          label,
          style: theme.typography.xSmall.copyWith(color: effective),
        ),
      ],
    );
  }
}

/// Small tinted tag for card labels (置顶 / 新 / 热 / 文章 ...). Built from
/// plain primitives so the tint stays fully controllable; neutral tags can
/// use [SecondaryBadge] directly.
class ZhihuTag extends StatelessWidget {
  const ZhihuTag(
    this.label, {
    super.key,
    this.foreground,
    this.background,
  });

  final String label;

  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        label,
        style: theme.typography.xSmall.copyWith(
          color: foreground ?? theme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// shadcn-styled empty / error / login-prompt state for the Zhihu panes.
class ZhihuEmptyState extends StatelessWidget {
  const ZhihuEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// A shadcn button (or any widget) shown below the text.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: scheme.mutedForeground,
              ),
            ),
            const Gap(10),
            Text(
              title,
              style: theme.typography.small.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const Gap(4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.typography.xSmall.copyWith(
                    color: scheme.mutedForeground,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const Gap(12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Transient feedback (replaces Material snack bars) built on the shadcn
/// toast overlay; requires the shadcn layer installed by [ZhihuShadcnHost].
void zhihuShowToast(BuildContext context, String message) {
  showToast(
    context: context,
    showDuration: const Duration(seconds: 3),
    builder: (context, overlay) => _ZhihuToast(message: message),
  );
}

class _ZhihuToast extends StatelessWidget {
  const _ZhihuToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedContainer(
      backgroundColor: theme.colorScheme.popover,
      borderRadius: theme.borderRadiusMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          style: theme.typography.small.copyWith(
            color: theme.colorScheme.popoverForeground,
          ),
        ),
      ),
    );
  }
}

/// Opens [url] in the system browser; used for links inside rich-text
/// bodies and the pane header actions. Always returns true so [HtmlWidget]
/// does not attempt its own navigation.
Future<bool> zhihuOpenInBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return true;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
  return true;
}
