import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/zhihu_detail_pane.dart';
import '../../components/zhihu_ui.dart';

/// Article (专栏) detail for hot-list entries that link to a Zhihu article
/// instead of a question. The body is rendered natively with
/// `flutter_widget_from_html` — no WebView.
///
/// With [pane] the page renders inside a [ZhihuDetailPane] without its own
/// page chrome, so it can be embedded as the right-hand content of the
/// sub-app's wide two-column layout; standalone (narrow) mode wraps the
/// same pane in a [ZhihuShadcnHost] with a back affordance.
class ZhihuArticlePage extends StatefulWidget {
  const ZhihuArticlePage({
    super.key,
    required this.articleId,
    required this.title,
    this.pane = false,
    this.onBack,
  });

  final String articleId;

  /// Hot-list title used as placeholder while the article downloads.
  final String title;

  /// Renders as an embedded pane when true.
  final bool pane;

  /// Shown in the pane header's back button in pane mode (e.g. clearing the
  /// wide layout's selection). Null hides the back affordance.
  final VoidCallback? onBack;

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
    if (widget.pane) {
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
    final article = _article;
    return ZhihuDetailPane(
      title: article?.title ?? widget.title,
      onBack: widget.pane
          ? widget.onBack
          : () => Navigator.of(context).maybePop(),
      // The body is a self-scrolling article list; expand it to the
      // remaining pane height so the ListView gets a finite viewport.
      enableScroll: false,
      expandChild: true,
      actions: [
        IconButton.ghost(
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          size: ButtonSize.small,
          onPressed: _loading ? null : _load,
        ),
        IconButton.ghost(
          icon: const Icon(LucideIcons.externalLink, size: 15),
          size: ButtonSize.small,
          onPressed: () => zhihuOpenInBrowser(
            article?.webUrl ??
                'https://zhuanlan.zhihu.com/p/${widget.articleId}',
          ),
        ),
      ],
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(size: 18));
    }
    if (_error != null) {
      return ZhihuEmptyState(
        icon: LucideIcons.cloudOff,
        title: '加载失败',
        subtitle: _error,
        action: Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _load,
          child: const Text('重试'),
        ),
      );
    }
    final article = _article;
    if (article == null) {
      return const ZhihuEmptyState(
        icon: LucideIcons.newspaper,
        title: '没有数据',
      );
    }
    return ListView(
      padding: ZhihuDense.pagePadding,
      children: [
        _ArticleCard(article: article),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The article as a single dense reading card: title, author and metrics
/// in compact rows, then the rich-text body.
class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});

  final ZhihuArticle article;

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
          Text(
            article.title,
            style: theme.typography.large.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const Gap(8),
          Row(
            children: [
              ZhihuAvatar(
                imageUrl: article.authorAvatarUrl,
                name: article.authorName,
                size: 22,
              ),
              const Gap(6),
              Flexible(
                child: Text(
                  article.authorName.isEmpty ? '匿名用户' : article.authorName,
                  style: theme.typography.small.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (article.authorHeadline.isNotEmpty) ...[
                const Gap(6),
                Expanded(
                  child: Text(
                    article.authorHeadline,
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
              if (article.voteupCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.arrowBigUp,
                  label: '${article.voteupCount} 赞同',
                ),
              if (article.commentCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.messageCircle,
                  label: '${article.commentCount} 评论',
                ),
              if (article.updatedAtMs > 0)
                ZhihuMetric(
                  icon: LucideIcons.clock,
                  label: DateFormat('yyyy-MM-dd HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(article.updatedAtMs),
                  ),
                ),
            ],
          ),
          const Gap(10),
          Container(height: 1, color: scheme.border),
          const Gap(10),
          if (article.contentHtml.isEmpty)
            Text(
              '（该文章没有文本内容，可在浏览器中查看）',
              style: theme.typography.xSmall.copyWith(
                color: scheme.mutedForeground,
              ),
            )
          else
            HtmlWidget(
              article.contentHtml,
              textStyle: theme.typography.small.copyWith(height: 1.7),
              onTapUrl: zhihuOpenInBrowser,
            ),
        ],
      ),
    );
  }
}
