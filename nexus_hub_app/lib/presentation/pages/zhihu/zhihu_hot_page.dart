import 'package:flutter/material.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';
import '../../layout/page_scaffold.dart';
import 'zhihu_article_page.dart';
import 'zhihu_question_page.dart';

/// Zhihu (知乎) hot list — anonymous browsing only.
///
/// Login is intentionally out of scope: Zhihu sign-in requires QR scans or
/// rotating captchas that cannot be automated here, so the sub-app only
/// surfaces the hot list (热榜), which is reachable without credentials.
/// Tapping an entry opens the question's answers (rendered natively, no
/// WebView) or the linked article.
class ZhihuHotPage extends StatefulWidget {
  const ZhihuHotPage({super.key});

  @override
  State<ZhihuHotPage> createState() => _ZhihuHotPageState();
}

class _ZhihuHotPageState extends State<ZhihuHotPage> {
  final ZhihuService _service = ZhihuService();

  List<ZhihuHotItem> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final items = await _service.fetchHotList();
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final items = await _service.refreshHotList();
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _openItem(ZhihuHotItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isArticle
            ? ZhihuArticlePage(articleId: item.id, title: item.title)
            : ZhihuQuestionPage(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('知乎热榜', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                '匿名浏览 · 登录需要扫码与验证码，暂不支持',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          NexusButton(
            label: '刷新',
            icon: Icons.refresh,
            variant: NexusButtonVariant.outlined,
            onPressed: _refresh,
          ),
        ],
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return _buildLoading(context);
    if (_hasError) return _buildError();
    if (_items.isEmpty) {
      return NexusCard(
        child: NexusEmptyState(
          icon: Icons.local_fire_department_outlined,
          title: '暂无内容',
          subtitle: '刷新以获取最新的知乎热榜。',
          action: NexusButton(
            label: '刷新',
            icon: Icons.refresh,
            variant: NexusButtonVariant.outlined,
            onPressed: _refresh,
          ),
        ),
      );
    }
    return _buildList();
  }

  Widget _buildLoading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return NexusCard(
      child: NexusEmptyState(
        icon: Icons.cloud_off,
        title: '加载失败',
        subtitle: '无法连接知乎，请检查网络后重试。',
        action: NexusButton(label: '重试', icon: Icons.refresh, onPressed: _load),
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _HotCard(item: item, onTap: () => _openItem(item));
        },
      ),
    );
  }
}

/// A single hot-list card: rank, title, excerpt, heat badge and metrics,
/// plus an optional thumbnail.
class _HotCard extends StatelessWidget {
  const _HotCard({required this.item, required this.onTap});

  final ZhihuHotItem item;
  final VoidCallback onTap;

  static const _topRankColor = Color(0xFFF56A00);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: onTap,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${item.rank}',
                textAlign: TextAlign.center,
                style: NexusTypography.headlineSm.copyWith(
                  color: item.rank <= 3
                      ? _topRankColor
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontWeight: item.rank <= 3 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.excerpt.isNotEmpty) ...[
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    item.excerpt,
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: NexusSpacing.sm),
                Wrap(
                  spacing: NexusSpacing.sm,
                  runSpacing: NexusSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.cardLabel.isNotEmpty)
                      NexusBadge(
                        label: item.cardLabel,
                        backgroundColor: _topRankColor.withValues(alpha: 0.12),
                        foregroundColor: _topRankColor,
                      ),
                    if (item.detailText.isNotEmpty)
                      NexusBadge(label: item.detailText),
                    if (item.isArticle)
                      const NexusBadge(label: '文章'),
                    if (!item.isArticle && item.answerCount > 0)
                      Text(
                        '${item.answerCount} 回答',
                        style: NexusTypography.labelSm,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (item.thumbnail.isNotEmpty) ...[
            const SizedBox(width: NexusSpacing.md),
            _HotThumbnail(imageUrl: item.thumbnail),
          ],
        ],
      ),
    );
  }
}

/// Optional 96x72 card cover with a graceful placeholder on load errors.
class _HotThumbnail extends StatelessWidget {
  const _HotThumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: NexusRadii.lgRadius,
      child: SizedBox(
        width: 96,
        height: 72,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: colorScheme.surfaceContainerHigh,
            child: Icon(
              Icons.image_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
