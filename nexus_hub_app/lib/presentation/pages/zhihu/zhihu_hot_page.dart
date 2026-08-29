import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_auth_store.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/nexus_page_route.dart';
import '../../components/zhihu_detail_pane.dart';
import '../../components/zhihu_ui.dart';
import 'zhihu_article_page.dart';
import 'zhihu_feed_detail_page.dart';
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
///
/// The whole sub-app is built from shadcn_flutter components (installed by
/// [ZhihuShadcnHost]) and tuned for the desktop: tight paddings, dense
/// list cards and a wide two-column layout (list left, reading pane
/// right).
class ZhihuHotPage extends StatefulWidget {
  const ZhihuHotPage({super.key});

  @override
  State<ZhihuHotPage> createState() => _ZhihuHotPageState();
}

class _ZhihuHotPageState extends State<ZhihuHotPage> {
  final ZhihuService _service = ZhihuService();
  final GlobalKey<ZhihuFeedPaneState> _feedKey =
      GlobalKey<ZhihuFeedPaneState>();

  _ZhihuTab _tab = _ZhihuTab.hot;
  List<ZhihuHotItem> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _authReady = false;

  /// Currently selected detail, shown in the wide layout's right-hand pane.
  /// Null while the layout is narrow.
  _ZhihuDetailSelection? _selection;

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
    setState(() {
      _tab = tab;
      // Switching list type never leaves a stale detail in the pane, both
      // in the wide layout and after returning to the narrow one.
      _selection = null;
    });
  }

  void _clearSelection() {
    setState(() => _selection = null);
  }

  /// Selects the entry into the wide layout's reading pane (see
  /// [ZhihuDetailSelection]); the fallback is the list area's previous
  /// full-screen navigation.
  void _openHotItem(ZhihuHotItem item) {
    if (_isWide) {
      setState(() => _selection = _ZhihuDetailSelection.hot(item));
      return;
    }
    Navigator.of(context).push(
      NexusPageRoute<void>(
        builder: (_) => item.isArticle
            ? ZhihuArticlePage(articleId: item.id, title: item.title)
            : ZhihuQuestionPage(item: item),
      ),
    );
  }

  void _openFeedItem(ZhihuFeedItem item) {
    if (_isWide) {
      setState(() => _selection = _ZhihuDetailSelection.feed(item));
      return;
    }
    Navigator.of(context).push(
      NexusPageRoute<void>(builder: (_) => ZhihuFeedDetailPage(item: item)),
    );
  }

  /// Opens the WebView login page; on success reloads the feed pane so it
  /// picks up the captured session right away.
  Future<void> _openLogin() async {
    final succeeded = await Navigator.of(context).push<bool>(
      NexusPageRoute<bool>(builder: (_) => const ZhihuLoginPage()),
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

  @override
  Widget build(BuildContext context) {
    return ZhihuShadcnHost(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: theme.colorScheme.background,
          child: SafeArea(
            child: Padding(
              padding: ZhihuDense.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const Gap(8),
                  _buildTabSelector(context),
                  const Gap(8),
                  Expanded(child: _buildContent(context)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Wide (two-column) layout flag. Deliberately computed from the available
  /// width, so it follows window resizing and the same code path serves both
  /// the embedded desktop window and the mobile routing shell.
  bool get _isWide => MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '知乎',
          style: theme.typography.large.copyWith(fontWeight: FontWeight.w700),
        ),
        const Gap(10),
        Expanded(
          child: Text(
            ZhihuAuthStore.isLoggedIn
                ? '已登录，可浏览热榜与推荐 Feed'
                : '匿名可浏览热榜，登录后可查看推荐 Feed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.xSmall.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        if (_authReady) ...[
          _buildAuthControl(context),
          const Gap(6),
        ],
        Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _refresh,
          child: const Text('刷新'),
        ),
      ],
    );
  }

  /// Small user chip with logout when logged in, a login button otherwise.
  Widget _buildAuthControl(BuildContext context) {
    final theme = Theme.of(context);
    final user = ZhihuAuthStore.user;
    if (ZhihuAuthStore.isLoggedIn) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZhihuAvatar(
            imageUrl: user?.avatarUrl ?? '',
            name: user?.name ?? '',
            size: 22,
          ),
          const Gap(6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              user?.name.isEmpty == false ? user!.name : '已登录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.small.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Gap(2),
          Tooltip(
            tooltip: (context) => const Text('退出登录'),
            child: IconButton.ghost(
              icon: const Icon(LucideIcons.logOut, size: 15),
              size: ButtonSize.small,
              onPressed: _logout,
            ),
          ),
        ],
      );
    }
    return Button.outline(
      leading: const Icon(LucideIcons.logIn, size: 14),
      style: const ButtonStyle.outline(
        size: ButtonSize.small,
        density: ButtonDensity.dense,
      ),
      onPressed: _openLogin,
      child: const Text('登录'),
    );
  }

  Widget _buildTabSelector(BuildContext context) {
    return Row(
      children: [
        for (final tab in _ZhihuTab.values) ...[
          SelectedButton(
            value: _tab == tab,
            onPressed: () => _selectTab(tab),
            style: const ButtonStyle.ghost(density: ButtonDensity.dense),
            selectedStyle: const ButtonStyle.secondary(
              density: ButtonDensity.dense,
            ),
            child: _TabLabel(
              icon: switch (tab) {
                _ZhihuTab.hot => LucideIcons.flame,
                _ZhihuTab.feed => LucideIcons.rss,
              },
              label: switch (tab) {
                _ZhihuTab.hot => '热榜',
                _ZhihuTab.feed => '推荐 Feed',
              },
            ),
          ),
          if (tab != _ZhihuTab.values.last) const Gap(4),
        ],
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!_isWide) {
      return _tab == _ZhihuTab.hot
          ? _buildHotPane(context)
          : ZhihuFeedPane(key: _feedKey, onLoginRequested: _openLogin);
    }

    final theme = Theme.of(context);
    final selection = _selection;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _kListPaneWidth,
          child: _tab == _ZhihuTab.hot
              ? _buildHotPane(context)
              : ZhihuFeedPane(
                  key: _feedKey,
                  onLoginRequested: _openLogin,
                  selectedItemId: selection?.itemKey,
                  onItemSelected: _openFeedItem,
                ),
        ),
        const Gap(8),
        Container(width: 1, color: theme.colorScheme.border),
        const Gap(8),
        Expanded(child: _buildReadingPane(context, selection)),
      ],
    );
  }

  Widget _buildReadingPane(
    BuildContext context,
    _ZhihuDetailSelection? selection,
  ) {
    if (selection == null) {
      return ZhihuDetailPane(
        title: _tab == _ZhihuTab.hot ? '热榜详情' : '推荐 Feed 详情',
        subtitle: '从左侧列表选择一条内容查看详情',
        // The placeholder is a plain Center; give it bounded constraints so
        // it centers instead of shrink-wrapping inside a scroll view.
        enableScroll: false,
        child: ZhihuEmptyState(
          icon: LucideIcons.newspaper,
          title: '尚未选择内容',
        ),
      );
    }
    // The detail pages render their own complete pane (header, actions and
    // a self-scrolling body); they only need a parent with bounded height,
    // which the wide layout's Expanded provides, and an onBack to clear the
    // selection.
    return switch (selection.kind) {
      _ZhihuDetailKind.hotQuestion => ZhihuQuestionPage(
        item: selection.hotItem!,
        pane: true,
        onBack: _clearSelection,
      ),
      _ZhihuDetailKind.hotArticle => ZhihuArticlePage(
        articleId: selection.hotItem!.id,
        title: selection.hotItem!.title,
        pane: true,
        onBack: _clearSelection,
      ),
      _ZhihuDetailKind.feed => ZhihuFeedDetailPage(
        item: selection.feedItem!,
        pane: true,
        onBack: _clearSelection,
      ),
    };
  }

  Widget _buildHotPane(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(size: 18));
    }
    if (_hasError) {
      return ZhihuEmptyState(
        icon: LucideIcons.cloudOff,
        title: '加载失败',
        subtitle: '无法连接知乎，请检查网络后重试。',
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
    if (_items.isEmpty) {
      return ZhihuEmptyState(
        icon: LucideIcons.flame,
        title: '暂无内容',
        subtitle: '刷新以获取最新的知乎热榜。',
        action: Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _refresh,
          child: const Text('刷新'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Gap(ZhihuDense.listGap),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _HotCard(
          item: item,
          selected: item.id == _selection?.itemKey,
          onTap: () => _openHotItem(item),
        );
      },
    );
  }
}

/// A single hot-list card: rank, title, excerpt and a compact metrics row
/// (label tag, heat, answer/follower counts), plus an optional thumbnail.
class _HotCard extends StatelessWidget {
  const _HotCard({
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  final ZhihuHotItem item;
  final VoidCallback onTap;

  /// Highlights the card in the wide layout's list column.
  final bool selected;

  static const _topRankColor = Color(0xFFF56A00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isTop = item.rank <= 3;
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
              SizedBox(
                width: 18,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '${item.rank}',
                    textAlign: TextAlign.center,
                    style: theme.typography.small.copyWith(
                      color: isTop ? _topRankColor : scheme.mutedForeground,
                      fontWeight: isTop ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.typography.small.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.excerpt.isNotEmpty &&
                        item.excerpt != '[视频]') ...[
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.cardLabel.isNotEmpty)
                          ZhihuTag(
                            item.cardLabel,
                            foreground: _topRankColor,
                            background: _topRankColor.withValues(alpha: 0.1),
                          ),
                        if (item.detailText.isNotEmpty)
                          ZhihuMetric(
                            icon: LucideIcons.flame,
                            label: item.detailText,
                            color: isTop ? _topRankColor : null,
                          ),
                        if (item.isArticle)
                          const ZhihuTag('文章')
                        else ...[
                          if (item.answerCount > 0)
                            ZhihuMetric(
                              icon: LucideIcons.messageSquare,
                              label: '${item.answerCount} 回答',
                            ),
                          if (item.followerCount > 0)
                            ZhihuMetric(
                              icon: LucideIcons.eye,
                              label: '${item.followerCount} 关注',
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (item.thumbnail.isNotEmpty) ...[
                const Gap(8),
                _HotThumbnail(imageUrl: item.thumbnail),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Optional 84x60 card cover with a graceful placeholder on load errors.
class _HotThumbnail extends StatelessWidget {
  const _HotThumbnail({required this.imageUrl});

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

/// Icon + label inside the dense tab pills.
class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.mutedForeground),
        const Gap(4),
        Text(
          label,
          style: theme.typography.small.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// The width above which the Zhihu sub-app switches to the wide two-column
/// layout (list on the left, reading pane on the right).
const double _kWideBreakpoint = 1000;

/// Fixed width of the left-hand list column in the wide layout.
const double _kListPaneWidth = 380;

enum _ZhihuDetailKind {
  /// A hot-list question opened in the reading pane.
  hotQuestion,

  /// A hot-list article opened in the reading pane.
  hotArticle,

  /// A recommend-feed entry opened in the reading pane.
  feed,
}

/// What the wide layout's right-hand reading pane currently shows. `null`
/// means "no selection"; the pane then displays the placeholder hint.
class _ZhihuDetailSelection {
  const _ZhihuDetailSelection._({
    required this.kind,
    this.hotItem,
    this.feedItem,
  });

  factory _ZhihuDetailSelection.hot(ZhihuHotItem item) {
    return _ZhihuDetailSelection._(
      kind: item.isArticle
          ? _ZhihuDetailKind.hotArticle
          : _ZhihuDetailKind.hotQuestion,
      hotItem: item,
    );
  }

  factory _ZhihuDetailSelection.feed(ZhihuFeedItem item) {
    return _ZhihuDetailSelection._(kind: _ZhihuDetailKind.feed, feedItem: item);
  }

  final _ZhihuDetailKind kind;

  /// The originating hot-list entry for the hot kinds (`hotArticle` and
  /// `hotQuestion`).
  final ZhihuHotItem? hotItem;

  /// The originating feed entry for the `feed` kind.
  final ZhihuFeedItem? feedItem;

  /// Key shared by the list card and the reading pane, so the card can be
  /// visually highlighted while the pane shows the same entry. Ids are
  /// unique per entry type.
  String get itemKey => feedItem?.id ?? hotItem!.id;
}
