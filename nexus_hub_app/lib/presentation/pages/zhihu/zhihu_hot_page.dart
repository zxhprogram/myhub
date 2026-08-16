import 'package:flutter/material.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_auth_store.dart';
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
import 'zhihu_feed_pane.dart';
import 'zhihu_login_page.dart';
import 'zhihu_question_page.dart';

enum _ZhihuTab { hot, feed }

/// Zhihu (知乎) sub-app entry: hot list (热榜) and, after a WebView-based
/// login (see [ZhihuLoginPage]), the personal recommend feed.
///
/// Tapping a hot-list entry opens the question's answers or the linked
/// article, rendered natively (no WebView); login itself embeds the real
/// sign-in page so the user clears the QR/captcha checks by hand and the
/// resulting session cookies are captured for API access.
class ZhihuHotPage extends StatefulWidget {
  const ZhihuHotPage({super.key});

  @override
  State<ZhihuHotPage> createState() => _ZhihuHotPageState();
}

class _ZhihuHotPageState extends State<ZhihuHotPage> {
  final ZhihuService _service = ZhihuService();
  final GlobalKey<ZhihuFeedPaneState> _feedKey = GlobalKey<ZhihuFeedPaneState>();

  _ZhihuTab _tab = _ZhihuTab.hot;
  List<ZhihuHotItem> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _authReady = false;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    ZhihuAuthStore.load().then((_) {
      if (mounted) setState(() => _authReady = true);
    });
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
    if (_tab == _ZhihuTab.feed) {
      _feedKey.currentState?.refresh();
      return;
    }
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

  void _selectTab(_ZhihuTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  /// Opens the WebView login page; on success reloads the feed pane so it
  /// picks up the captured session right away.
  Future<void> _openLogin() async {
    final succeeded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ZhihuLoginPage()),
    );
    if (!mounted) return;
    setState(() => _authReady = true);
    if (succeeded == true) {
      _feedKey.currentState?.reload();
    }
  }

  Future<void> _logout() async {
    await ZhihuAuthStore.logout();
    if (!mounted) return;
    setState(() => _authReady = true);
    _feedKey.currentState?.reload();
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('知乎', style: NexusTypography.headlineXl),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  ZhihuAuthStore.isLoggedIn ? '已登录，可浏览热榜与推荐 Feed' : '匿名可浏览热榜，登录后可查看推荐 Feed',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_authReady) _buildAuthControl(context),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: '刷新',
                icon: Icons.refresh,
                variant: NexusButtonVariant.outlined,
                onPressed: _refresh,
              ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabSelector(context),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: _tab == _ZhihuTab.hot
                ? _buildHotPane(context)
                : ZhihuFeedPane(key: _feedKey, onLoginRequested: _openLogin),
          ),
        ],
      ),
    );
  }

  /// Small user chip with logout when logged in, a login button otherwise.
  Widget _buildAuthControl(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = ZhihuAuthStore.user;
    if (ZhihuAuthStore.isLoggedIn) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 26,
              height: 26,
              child: Image.network(
                user?.avatarUrl ?? '',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: colorScheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            user?.name.isEmpty == false ? user!.name : '已登录',
            style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: '退出登录',
            onPressed: _logout,
          ),
        ],
      );
    }
    return NexusButton(label: '登录', icon: Icons.login, onPressed: _openLogin);
  }

  Widget _buildTabSelector(BuildContext context) {
    return Row(
      children: [
        for (final tab in _ZhihuTab.values)
          Padding(
            padding: const EdgeInsets.only(right: NexusSpacing.sm),
            child: _ZhihuTabChip(
              label: switch (tab) {
                _ZhihuTab.hot => '热榜',
                _ZhihuTab.feed => '推荐 Feed',
              },
              isSelected: _tab == tab,
              onTap: () => _selectTab(tab),
            ),
          ),
      ],
    );
  }

  Widget _buildHotPane(BuildContext context) {
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

/// Pill-style selectable chip used for the 热榜 / 推荐 Feed tab selector.
class _ZhihuTabChip extends StatelessWidget {
  const _ZhihuTabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.primary : Colors.transparent,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        hoverColor: isSelected
            ? null
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.fullRadius,
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: isSelected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
