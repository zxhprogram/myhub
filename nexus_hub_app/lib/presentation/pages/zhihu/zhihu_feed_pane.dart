import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_auth_store.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/zhihu_ui.dart';
import '../../components/nexus_page_route.dart';
import 'zhihu_feed_detail_page.dart';

/// The personal recommend feed (推荐 Feed) pane shown next to the hot
/// list. Requires a stored web session; when logged out the pane turns
/// into a login prompt delegating to [onLoginRequested] (the parent owns
/// the login window and calls [reload] when it returns successfully).
class ZhihuFeedPane extends StatefulWidget {
  const ZhihuFeedPane({
    super.key,
    this.onLoginRequested,
    this.selectedItemId,
    this.onItemSelected,
  });

  /// Opens the WebView login page; invoked from the logged-out prompt.
  final Future<void> Function()? onLoginRequested;

  /// Id of the entry currently selected in the wide two-column layout; the
  /// matching card is visually highlighted. Null in the narrow layout.
  final String? selectedItemId;

  /// When non-null, tapping an entry reports it here instead of pushing a
  /// full-screen detail page (used by the wide layout's reading pane).
  final ValueChanged<ZhihuFeedItem>? onItemSelected;

  @override
  State<ZhihuFeedPane> createState() => ZhihuFeedPaneState();
}

class ZhihuFeedPaneState extends State<ZhihuFeedPane> {
  final ZhihuService _service = ZhihuService();

  final List<ZhihuFeedItem> _items = [];
  bool _loadingFirst = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _nextAfterId;
  String? _error;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  /// Full reset — re-reads the auth store, so it doubles as the "auth
  /// state changed" entry point after login/logout.
  Future<void> reload() => _loadFirst();

  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    await ZhihuAuthStore.load();
    final seq = ++_requestSeq;
    if (!ZhihuAuthStore.isLoggedIn) {
      setState(() {
        _items.clear();
        _loadingFirst = false;
        _error = null;
        _hasMore = false;
        _nextAfterId = null;
      });
      return;
    }
    setState(() {
      _loadingFirst = true;
      _error = null;
    });
    try {
      final page = await _service.fetchRecommendFeed();
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _nextAfterId = page.nextAfterId;
        _loadingFirst = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e.toString();
        _loadingFirst = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextAfterId == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchRecommendFeed(afterId: _nextAfterId);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _nextAfterId = page.nextAfterId;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      if (mounted) {
        zhihuShowToast(context, '加载更多失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ZhihuAuthStore.isLoggedIn) {
      return ZhihuEmptyState(
        icon: LucideIcons.circleUser,
        title: '登录后查看推荐 Feed',
        subtitle: '推荐流需要知乎登录态。点击登录后在页面中完成扫码或验证，登录成功后即可浏览。',
        action: widget.onLoginRequested == null
            ? null
            : Button.primary(
                leading: const Icon(LucideIcons.logIn, size: 14),
                style: const ButtonStyle.primary(
                  size: ButtonSize.small,
                  density: ButtonDensity.dense,
                ),
                onPressed: () => widget.onLoginRequested!(),
                child: const Text('登录知乎'),
              ),
      );
    }
    if (_loadingFirst) {
      return const Center(child: CircularProgressIndicator(size: 18));
    }
    if (_error != null && _items.isEmpty) {
      return ZhihuEmptyState(
        icon: LucideIcons.cloudOff,
        title: 'Feed 加载失败',
        subtitle: _error!,
        action: Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _loadFirst,
          child: const Text('重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return ZhihuEmptyState(
        icon: LucideIcons.rss,
        title: '暂无推荐内容',
        subtitle: '刷新以重新获取推荐 Feed。',
        action: Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _loadFirst,
          child: const Text('刷新'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const Gap(ZhihuDense.listGap),
      itemBuilder: (context, index) {
        if (index < _items.length) {
          final item = _items[index];
          return _FeedCard(
            item: item,
            selected: item.id == widget.selectedItemId,
            onTap: () {
              final onSelected = widget.onItemSelected;
              if (onSelected != null) {
                onSelected(item);
              } else {
                _openItem(item);
              }
            },
          );
        }
        return _buildFooter(context);
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(size: 16)),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Button.outline(
            leading: const Icon(LucideIcons.chevronDown, size: 14),
            style: const ButtonStyle.outline(
              size: ButtonSize.small,
              density: ButtonDensity.dense,
            ),
            onPressed: _loadMore,
            child: const Text('加载更多'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '— 没有更多推荐了 —',
          style: theme.typography.xSmall.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }

  void _openItem(ZhihuFeedItem item) {
    Navigator.of(context).push(
      NexusPageRoute<void>(
        builder: (_) => ZhihuFeedDetailPage(item: item),
      ),
    );
  }
}

/// A single feed card: question/article title, excerpt preview, and a
/// compact author row (avatar, name, headline) with engagement metrics,
/// plus an optional thumbnail.
class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  final ZhihuFeedItem item;
  final VoidCallback onTap;

  /// Highlights the card in the wide layout's list column.
  final bool selected;

  String get _typeLabel => switch (item.type) {
    'answer' => '回答',
    'article' => '文章',
    'pin' => '想法',
    _ => item.type,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: OutlinedContainer(
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: 0.07)
              : scheme.card,
          borderColor: selected
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.border,
          borderWidth: selected ? 1.4 : 1,
          borderRadius: theme.borderRadiusMd,
          padding: ZhihuDense.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                              style: theme.typography.small.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Gap(6),
                          ZhihuTag(_typeLabel),
                        ],
                      ),
                    ] else ...[
                      ZhihuTag(_typeLabel),
                    ],
                    if (item.excerpt.isNotEmpty) ...[
                      const Gap(2),
                      Text(
                        item.excerpt,
                        style: theme.typography.xSmall.copyWith(
                          color: scheme.mutedForeground,
                          height: 1.45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Gap(5),
                    Row(
                      children: [
                        ZhihuAvatar(
                          imageUrl: item.authorAvatarUrl,
                          name: item.authorName,
                          size: 16,
                        ),
                        const Gap(4),
                        Flexible(
                          child: Text(
                            item.authorName.isEmpty ? '匿名用户' : item.authorName,
                            style: theme.typography.xSmall.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.authorHeadline.isNotEmpty) ...[
                          const Gap(4),
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
                        const Gap(8),
                        if (item.voteupCount > 0)
                          ZhihuMetric(
                            icon: LucideIcons.arrowBigUp,
                            label: '${item.voteupCount}',
                          ),
                        const Gap(8),
                        if (item.commentCount > 0)
                          ZhihuMetric(
                            icon: LucideIcons.messageCircle,
                            label: '${item.commentCount}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.thumbnail.isNotEmpty) ...[
                const Gap(8),
                _FeedThumbnail(imageUrl: item.thumbnail),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Optional 84x60 card cover with a graceful placeholder on load errors.
class _FeedThumbnail extends StatelessWidget {
  const _FeedThumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: ZhihuDense.thumbWidth,
        height: ZhihuDense.thumbHeight,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: theme.colorScheme.muted,
            child: Icon(
              LucideIcons.imageOff,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}
