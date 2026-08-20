import 'package:flutter/material.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_auth_store.dart';
import '../../../data/services/zhihu_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';
import 'zhihu_feed_detail_page.dart';
import 'zhihu_question_page.dart' show ZhihuAuthorAvatar;

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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('加载更多失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!ZhihuAuthStore.isLoggedIn) {
      return NexusCard(
        child: NexusEmptyState(
          icon: Icons.account_circle_outlined,
          title: '登录后查看推荐 Feed',
          subtitle: '推荐流需要知乎登录态。点击登录后在页面中完成扫码或验证，登录成功后即可浏览。',
          action: widget.onLoginRequested == null
              ? null
              : NexusButton(
                  label: '登录知乎',
                  icon: Icons.login,
                  onPressed: () => widget.onLoginRequested!(),
                ),
        ),
      );
    }
    if (_loadingFirst) {
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
    if (_error != null && _items.isEmpty) {
      return NexusCard(
        child: NexusEmptyState(
          icon: Icons.cloud_off,
          title: 'Feed 加载失败',
          subtitle: _error!,
          action: NexusButton(
            label: '重试',
            icon: Icons.refresh,
            onPressed: _loadFirst,
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return NexusCard(
        child: NexusEmptyState(
          icon: Icons.feed_outlined,
          title: '暂无推荐内容',
          subtitle: '刷新以重新获取推荐 Feed。',
          action: NexusButton(
            label: '刷新',
            icon: Icons.refresh,
            variant: NexusButtonVariant.outlined,
            onPressed: _loadFirst,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
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
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: NexusSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
        child: Center(
          child: NexusButton(
            label: '加载更多',
            icon: Icons.expand_more,
            variant: NexusButtonVariant.outlined,
            onPressed: _loadMore,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
      child: Center(
        child: Text(
          '— 没有更多推荐了 —',
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  void _openItem(ZhihuFeedItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ZhihuFeedDetailPage(item: item),
      ),
    );
  }
}

/// A single feed card: author, question/article title, excerpt preview,
/// metrics and an optional thumbnail.
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
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: onTap,
      highlight: selected,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ZhihuAuthorAvatar(imageUrl: item.authorAvatarUrl),
                    const SizedBox(width: NexusSpacing.sm),
                    Expanded(
                      child: Text(
                        item.authorName.isEmpty ? '匿名用户' : item.authorName,
                        style: NexusTypography.labelMd.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    Text(_typeLabel, style: NexusTypography.labelSm),
                  ],
                ),
                if (item.title.isNotEmpty) ...[
                  const SizedBox(height: NexusSpacing.sm),
                  Text(
                    item.title,
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.excerpt.isNotEmpty) ...[
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    item.excerpt,
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: NexusSpacing.sm),
                Row(
                  children: [
                    if (item.voteupCount > 0) ...[
                      Icon(
                        Icons.thumb_up_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(width: NexusSpacing.xs),
                      Text('${item.voteupCount}', style: NexusTypography.labelSm),
                      const SizedBox(width: NexusSpacing.md),
                    ],
                    if (item.commentCount > 0) ...[
                      Icon(
                        Icons.mode_comment_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      const SizedBox(width: NexusSpacing.xs),
                      Text('${item.commentCount}', style: NexusTypography.labelSm),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (item.thumbnail.isNotEmpty) ...[
            const SizedBox(width: NexusSpacing.md),
            _FeedThumbnail(imageUrl: item.thumbnail),
          ],
        ],
      ),
    );
  }
}

/// Optional 96x72 card cover with a graceful placeholder on load errors.
class _FeedThumbnail extends StatelessWidget {
  const _FeedThumbnail({required this.imageUrl});

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
