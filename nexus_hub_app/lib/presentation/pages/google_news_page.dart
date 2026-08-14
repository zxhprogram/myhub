import 'package:flutter/material.dart';

import '../../data/models/google_news_item.dart';
import '../../data/services/google_news_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_empty_state.dart';
import '../layout/page_scaffold.dart';
import 'google_news_article_page.dart';

/// Google News — latest headlines fetched from Google News RSS, with an
/// in-app web reader for article details.
class GoogleNewsPage extends StatefulWidget {
  const GoogleNewsPage({super.key});

  @override
  State<GoogleNewsPage> createState() => _GoogleNewsPageState();
}

class _GoogleNewsPageState extends State<GoogleNewsPage> {
  final GoogleNewsService _service = GoogleNewsService();

  GoogleNewsTopic _topic = GoogleNewsTopic.topStories;
  List<GoogleNewsItem> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final items = await _service.fetchTopic(_topic);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final items = await _service.refreshTopic(_topic);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _selectTopic(GoogleNewsTopic topic) {
    if (_topic == topic) return;
    setState(() {
      _topic = topic;
      _isLoading = true;
      _hasError = false;
    });
    _load();
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
              Text('Google News', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Latest headlines from Google News',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          NexusButton(
            label: 'Refresh',
            icon: Icons.refresh,
            variant: NexusButtonVariant.outlined,
            onPressed: _refresh,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopicSelector(),
          const SizedBox(height: NexusSpacing.md),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTopicSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final topic in GoogleNewsTopic.values)
            Padding(
              padding: const EdgeInsets.only(right: NexusSpacing.sm),
              child: _TopicChip(
                label: topic.label,
                isSelected: _topic == topic,
                onTap: () => _selectTopic(topic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return _buildLoading();
    if (_hasError) return _buildError();
    if (_items.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoading() {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: SizedBox(
        height: 320,
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
      ),
    );
  }

  Widget _buildError() {
    return NexusEmptyState(
      icon: Icons.cloud_off,
      title: 'Could not load news',
      subtitle: 'Check your connection and try again.',
      action: NexusButton(label: 'Retry', icon: Icons.refresh, onPressed: _load),
    );
  }

  Widget _buildEmpty() {
    return NexusEmptyState(
      icon: Icons.newspaper,
      title: 'No news yet',
      subtitle: 'Refresh to load the latest headlines.',
      action: NexusButton(
        label: 'Refresh',
        icon: Icons.refresh,
        variant: NexusButtonVariant.outlined,
        onPressed: _refresh,
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
          return _NewsCard(item: item, onTap: () => _openArticle(item));
        },
      ),
    );
  }

  void _openArticle(GoogleNewsItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GoogleNewsArticlePage(item: item),
      ),
    );
  }
}

/// A single headline card: title, snippet, source badge, timestamp and an
/// optional thumbnail. Tapping it opens the in-app web reader.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});

  final GoogleNewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      onTap: onTap,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.hasSnippet) ...[
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    item.snippet,
                    style: NexusTypography.labelMd,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: NexusSpacing.sm),
                Row(
                  children: [
                    if (item.source.isNotEmpty) ...[
                      NexusBadge(label: item.source),
                      const SizedBox(width: NexusSpacing.sm),
                    ],
                    Text(item.timeAgo, style: NexusTypography.labelSm),
                  ],
                ),
              ],
            ),
          ),
          if (item.hasImage) ...[
            const SizedBox(width: NexusSpacing.md),
            _NewsThumbnail(imageUrl: item.imageUrl),
          ],
        ],
      ),
    );
  }
}

/// Optional 96x72 thumbnail with a graceful placeholder on load errors.
class _NewsThumbnail extends StatelessWidget {
  const _NewsThumbnail({required this.imageUrl});

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
              Icons.newspaper,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-style selectable chip used for the news topic selector.
class _TopicChip extends StatelessWidget {
  const _TopicChip({
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
