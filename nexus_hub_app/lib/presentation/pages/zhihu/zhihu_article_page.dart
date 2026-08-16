import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';
import 'zhihu_question_page.dart'
    show ZhihuAuthorAvatar, ZhihuMetricRow, zhihuOpenInBrowser;

/// Article (专栏) detail for hot-list entries that link to a Zhihu article
/// instead of a question. The body is rendered natively with
/// `flutter_widget_from_html` — no WebView.
class ZhihuArticlePage extends StatefulWidget {
  const ZhihuArticlePage({
    super.key,
    required this.articleId,
    required this.title,
  });

  final String articleId;

  /// Hot-list title used as placeholder while the article downloads.
  final String title;

  @override
  State<ZhihuArticlePage> createState() => _ZhihuArticlePageState();
}

class _ZhihuArticlePageState extends State<ZhihuArticlePage> {
  final ZhihuService _service = ZhihuService();

  ZhihuArticle? _article;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final article = await _service.fetchArticle(widget.articleId);
      if (!mounted) return;
      setState(() {
        _article = article;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final article = _article;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        title: Text(
          article?.title ?? widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () => zhihuOpenInBrowser(
              article?.webUrl ??
                  'https://zhuanlan.zhihu.com/p/${widget.articleId}',
            ),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null) {
      return NexusEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: NexusButton(label: '重试', icon: Icons.refresh, onPressed: _load),
      );
    }
    final article = _article;
    if (article == null) {
      return const NexusEmptyState(icon: Icons.article_outlined, title: '没有数据');
    }
    return ListView(
      padding: const EdgeInsets.all(NexusSpacing.md),
      children: [
        _buildHeader(context, article),
        const SizedBox(height: NexusSpacing.sm),
        NexusCard(
          child: article.contentHtml.isEmpty
              ? Text(
                  '（该文章没有文本内容，可在浏览器中查看）',
                  style: NexusTypography.labelMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : HtmlWidget(
                  article.contentHtml,
                  textStyle: NexusTypography.bodyMd.copyWith(height: 1.6),
                  onTapUrl: zhihuOpenInBrowser,
                ),
        ),
        const SizedBox(height: NexusSpacing.xl),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, ZhihuArticle article) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: NexusTypography.bodyLg.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Row(
            children: [
              ZhihuAuthorAvatar(imageUrl: article.authorAvatarUrl),
              const SizedBox(width: NexusSpacing.sm),
              Expanded(
                child: Text(
                  article.authorName.isEmpty ? '匿名用户' : article.authorName,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.xs,
            children: [
              if (article.authorHeadline.isNotEmpty)
                Text(
                  article.authorHeadline,
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              if (article.voteupCount > 0)
                ZhihuMetricRow(icon: Icons.thumb_up_outlined, label: '${article.voteupCount} 赞同'),
              if (article.commentCount > 0)
                ZhihuMetricRow(icon: Icons.mode_comment_outlined, label: '${article.commentCount} 评论'),
              if (article.updatedAtMs > 0)
                ZhihuMetricRow(
                  icon: Icons.schedule,
                  label: DateFormat('MM-dd HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(article.updatedAtMs),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
