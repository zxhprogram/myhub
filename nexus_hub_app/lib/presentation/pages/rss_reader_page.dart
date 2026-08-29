import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/rss_feed_model.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_empty_state.dart';
import '../components/nexus_input.dart';
import '../components/nexus_toast.dart';
import '../layout/page_scaffold.dart';
import '../states/rss_state.dart';

class RssReaderPage extends StatefulWidget {
  const RssReaderPage({super.key});

  @override
  State<RssReaderPage> createState() => _RssReaderPageState();
}

class _RssReaderPageState extends State<RssReaderPage> {
  final _state = RssState();
  final _query = signal<String>('');

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  List<RssArticleModel> _visibleArticles(List<RssArticleModel> all) {
    final query = _query.value.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all
        .where((a) =>
            a.title.toLowerCase().contains(query) ||
            a.summary.toLowerCase().contains(query))
        .toList();
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
              Text('RSS Reader', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Stay updated with your favorite sources',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Watch((context) => NexusButton(
                    label: 'Refresh',
                    icon: RadixIcons.update,
                    isLoading: _state.isRefreshing.value,
                    onPressed: _state.isRefreshing.value
                        ? null
                        : () => _state.refresh(),
                  )),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: 'Add Feed',
                icon: RadixIcons.plus,
                onPressed: () => _showAddFeedDialog(context),
              ),
            ],
          ),
        ],
      ),
      child: Watch((context) {
        final error = _state.error.value;
        final feeds = _state.feeds.value;
        final articles = _visibleArticles(_state.articles.value);
        final isLoading = _state.isLoading.value;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(
                hintText: 'Search articles...',
                prefixIcon: const Icon(RadixIcons.magnifyingGlass, size: 20),
                onChanged: (value) => _query.value = value,
              ),
              if (error != null) ...[
                const SizedBox(height: NexusSpacing.sm),
                Text(
                  error,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.destructive,
                  ),
                ),
              ],
              if (feeds.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.md),
                Wrap(
                  spacing: NexusSpacing.sm,
                  runSpacing: NexusSpacing.sm,
                  children: [
                    for (final feed in feeds) _FeedChip(feed: feed, state: _state),
                  ],
                ),
              ],
              const SizedBox(height: NexusSpacing.md),
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (articles.isEmpty)
                NexusEmptyState(
                  icon: LucideIcons.rss,
                  title: 'No articles yet',
                  subtitle: feeds.isEmpty
                      ? 'Add a feed to start following your sources.'
                      : 'Try a different search or refresh your feeds.',
                )
              else
                ...articles.map(
                  (article) => Padding(
                    padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
                    child: _FeedCard(
                      article: article,
                      feedTitle: _feedTitle(feeds, article.feedId),
                      onOpen: () => _openArticle(article),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _feedTitle(List<RssFeedModel> feeds, int? feedId) {
    for (final feed in feeds) {
      if (feed.id == feedId) return feed.title;
    }
    return 'RSS';
  }

  Future<void> _openArticle(RssArticleModel article) async {
    final id = article.id;
    if (id != null && !article.isRead) {
      await _state.markRead(id);
    }
    final uri = Uri.tryParse(article.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAddFeedDialog(BuildContext context) {
    final urlController = TextEditingController();
    final titleController = TextEditingController();
    final categoryController = TextEditingController();

    showOverlay<void>(
      context,
      DialogConfiguration<void>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => AlertDialog(
          title: const Text('Add RSS Feed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(
                controller: urlController,
                hintText: 'Feed URL (required)',
              ),
              const SizedBox(height: NexusSpacing.sm),
              NexusInput(
                controller: titleController,
                hintText: 'Title (optional)',
              ),
              const SizedBox(height: NexusSpacing.sm),
              NexusInput(
                controller: categoryController,
                hintText: 'Category (optional)',
              ),
            ],
          ),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<void>(ctx),
              child: const Text('Cancel'),
            ),
            NexusButton(
              label: 'Subscribe',
              onPressed: () async {
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  if (ctx.mounted) {
                    nexusToast(ctx, 'Feed URL is required', isError: true);
                  }
                  return;
                }
                await _state.addFeed(
                  title: titleController.text.trim(),
                  url: url,
                  category: categoryController.text.trim(),
                );
                if (ctx.mounted) closeOverlay<void>(ctx);
                if (mounted) {
                  final error = _state.error.value;
                  if (error != null) {
                    nexusToast(context, error, isError: true);
                  } else {
                    nexusToast(context, 'Feed added');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedChip extends StatelessWidget {
  const _FeedChip({required this.feed, required this.state});

  final RssFeedModel feed;
  final RssState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(feed.title, style: NexusTypography.labelMd),
          const SizedBox(width: NexusSpacing.xs),
          GestureDetector(
            onTap: () {
              final id = feed.id;
              if (id != null) state.deleteFeed(id);
            },
            child: Icon(
              RadixIcons.cross2,
              size: 14,
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.article,
    required this.feedTitle,
    required this.onOpen,
  });

  final RssArticleModel article;
  final String feedTitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: GestureDetector(
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: article.isRead
                    ? colorScheme.border
                    : colorScheme.secondary,
                borderRadius: NexusRadii.fullRadius,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight:
                          article.isRead ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: NexusSpacing.xs),
                    Text(
                      article.summary,
                      style: NexusTypography.labelMd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: NexusSpacing.sm),
                  Row(
                    children: [
                      NexusBadge(label: feedTitle),
                      const SizedBox(width: NexusSpacing.sm),
                      Text(_formatTime(article.publishedAt),
                          style: NexusTypography.labelSm),
                    ],
                  ),
                ],
              ),
            ),
            IconButton.ghost(
              onPressed: onOpen,
              icon: const Icon(RadixIcons.externalLink, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hour ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}
