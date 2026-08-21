import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../components/zhihu_detail_pane.dart';
import '../../components/zhihu_ui.dart';

/// Feed entry detail rendered straight from the payload the feed request
/// already carried (body, author, metrics) — no follow-up request, no
/// WebView. Entries without embedded content show the excerpt instead.
///
/// With [pane] the page renders inside a [ZhihuDetailPane] without its own
/// page chrome, so it can be embedded as the right-hand content of the
/// sub-app's wide two-column layout; standalone (narrow) mode wraps the
/// same pane in a [ZhihuShadcnHost] with a back affordance.
class ZhihuFeedDetailPage extends StatelessWidget {
  const ZhihuFeedDetailPage({
    super.key,
    required this.item,
    this.pane = false,
    this.onBack,
  });

  final ZhihuFeedItem item;

  /// Renders as an embedded pane when true.
  final bool pane;

  /// Shown in the pane header's back button in pane mode (e.g. clearing the
  /// wide layout's selection). Null hides the back affordance.
  final VoidCallback? onBack;

  String get _fallbackTitle => item.type == 'pin'
      ? '想法'
      : (item.authorName.isEmpty ? '详情' : item.authorName);

  String get _typeLabel => switch (item.type) {
    'answer' => '回答',
    'article' => '文章',
    'pin' => '想法',
    _ => item.type,
  };

  @override
  Widget build(BuildContext context) {
    if (pane) {
      return _buildPane(context);
    }
    return ZhihuShadcnHost(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: theme.colorScheme.background,
          child: SafeArea(child: _buildPane(context)),
        );
      },
    );
  }

  Widget _buildPane(BuildContext context) {
    return ZhihuDetailPane(
      title: item.title.isEmpty ? _fallbackTitle : item.title,
      onBack: pane
          ? onBack
          : () => Navigator.of(context).maybePop(),
      // The body is a self-scrolling list; expand it to the remaining
      // pane height so the ListView gets a finite viewport.
      enableScroll: false,
      expandChild: true,
      actions: [
        IconButton.ghost(
          icon: const Icon(LucideIcons.externalLink, size: 15),
          size: ButtonSize.small,
          onPressed: () => zhihuOpenInBrowser(item.webUrl),
        ),
      ],
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: ZhihuDense.pagePadding,
      children: [_FeedDetailCard(item: item, typeLabel: _typeLabel), const Gap(24)],
    );
  }
}

/// The feed entry as a single dense reading card: title, author and metrics
/// in compact rows, then the rich-text body (or the excerpt).
class _FeedDetailCard extends StatelessWidget {
  const _FeedDetailCard({required this.item, required this.typeLabel});

  final ZhihuFeedItem item;
  final String typeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OutlinedContainer(
      borderRadius: theme.borderRadiusMd,
      padding: ZhihuDense.readingPadding,
      backgroundColor: scheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.typography.base.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                const Gap(6),
                ZhihuTag(typeLabel),
              ],
            ),
            const Gap(8),
          ],
          Row(
            children: [
              ZhihuAvatar(
                imageUrl: item.authorAvatarUrl,
                name: item.authorName,
                size: 22,
              ),
              const Gap(6),
              Flexible(
                child: Text(
                  item.authorName.isEmpty ? '匿名用户' : item.authorName,
                  style: theme.typography.small.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.authorHeadline.isNotEmpty) ...[
                const Gap(6),
                Expanded(
                  child: Text(
                    item.authorHeadline,
                    style: theme.typography.xSmall.copyWith(
                      color: scheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const Gap(4),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ZhihuMetric(icon: LucideIcons.hash, label: typeLabel),
              if (item.voteupCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.arrowBigUp,
                  label: '${item.voteupCount} 赞同',
                ),
              if (item.commentCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.messageCircle,
                  label: '${item.commentCount} 评论',
                ),
            ],
          ),
          const Gap(10),
          Container(height: 1, color: scheme.border),
          const Gap(10),
          if (item.hasContent)
            HtmlWidget(
              item.contentHtml,
              textStyle: theme.typography.small.copyWith(height: 1.7),
              onTapUrl: zhihuOpenInBrowser,
            )
          else
            Text(
              item.excerpt.isEmpty ? '（没有可显示的内容，可在浏览器中打开）' : item.excerpt,
              style: theme.typography.small.copyWith(
                color: scheme.mutedForeground,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}
