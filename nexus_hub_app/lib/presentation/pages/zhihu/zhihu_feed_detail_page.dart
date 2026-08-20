import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_card.dart';
import '../../components/zhihu_detail_pane.dart';
import 'zhihu_question_page.dart'
    show ZhihuAuthorAvatar, ZhihuMetricRow, zhihuOpenInBrowser;

/// Feed entry detail rendered straight from the payload the feed request
/// already carried (body, author, metrics) — no follow-up request, no
/// WebView. Entries without embedded content show the excerpt instead.
///
/// With [pane] the page renders inside a [ZhihuDetailPane] without its own
/// Scaffold/app bar, so it can be embedded as the right-hand content of the
/// sub-app's wide two-column layout.
class ZhihuFeedDetailPage extends StatelessWidget {
  const ZhihuFeedDetailPage({
    super.key,
    required this.item,
    this.pane = false,
    this.onBack,
  });

  final ZhihuFeedItem item;

  /// Renders as an embedded pane (no Scaffold/app bar) when true.
  final bool pane;

  /// Shown in the pane header's back button in pane mode (e.g. clearing the
  /// wide layout's selection). Null hides the back affordance.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _buildBody(context, item);
    if (pane) {
      return ZhihuDetailPane(
        title: item.title.isEmpty ? _fallbackTitle : item.title,
        onBack: onBack,
        // The body is a self-scrolling list; expand it to the remaining
        // pane height so the ListView gets a finite viewport.
        enableScroll: false,
        expandChild: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () => zhihuOpenInBrowser(item.webUrl),
          ),
        ],
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        title: Text(
          item.title.isEmpty ? _fallbackTitle : item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () => zhihuOpenInBrowser(item.webUrl),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, ZhihuFeedItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(NexusSpacing.md),
      children: [
        _buildHeader(context, item),
        const SizedBox(height: NexusSpacing.sm),
        NexusCard(
          child: item.hasContent
              ? HtmlWidget(
                  item.contentHtml,
                  textStyle: NexusTypography.bodyMd.copyWith(height: 1.6),
                  onTapUrl: zhihuOpenInBrowser,
                )
              : Text(
                  item.excerpt.isEmpty ? '（没有可显示的内容，可在浏览器中打开）' : item.excerpt,
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: NexusSpacing.xl),
      ],
    );
  }

  String get _fallbackTitle => item.type == 'pin'
      ? '想法'
      : (item.authorName.isEmpty ? '详情' : item.authorName);

  Widget _buildHeader(BuildContext context, ZhihuFeedItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title.isNotEmpty) ...[
            Text(
              item.title,
              style: NexusTypography.bodyLg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
          ],
          Row(
            children: [
              ZhihuAuthorAvatar(imageUrl: item.authorAvatarUrl),
              const SizedBox(width: NexusSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.authorName.isEmpty ? '匿名用户' : item.authorName,
                      style: NexusTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.authorHeadline.isNotEmpty)
                      Text(
                        item.authorHeadline,
                        style: NexusTypography.labelSm.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.xs,
            children: [
              if (item.type.isNotEmpty)
                Text(item.typeLabel, style: NexusTypography.labelSm),
              if (item.voteupCount > 0)
                ZhihuMetricRow(
                  icon: Icons.thumb_up_outlined,
                  label: '${item.voteupCount} 赞同',
                ),
              if (item.commentCount > 0)
                ZhihuMetricRow(
                  icon: Icons.mode_comment_outlined,
                  label: '${item.commentCount} 评论',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on ZhihuFeedItem {
  String get typeLabel => switch (type) {
    'answer' => '回答',
    'article' => '文章',
    'pin' => '想法',
    _ => type,
  };
}
