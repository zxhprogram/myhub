import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';

class RssReaderPage extends StatelessWidget {
  const RssReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final feeds = [
      _FeedItem(
        title: 'Flutter 3.41 stable release',
        source: 'Flutter Blog',
        summary: 'New rendering improvements and performance updates.',
        publishedAt: '2 hours ago',
        isRead: false,
      ),
      _FeedItem(
        title: 'Dart 3.11 language features',
        source: 'Dart Announcements',
        summary: 'Records, patterns, and enhanced switch expressions.',
        publishedAt: '5 hours ago',
        isRead: false,
      ),
      _FeedItem(
        title: 'Understanding SQLite in Flutter',
        source: 'Mobile Dev Weekly',
        summary: 'Best practices for local data persistence.',
        publishedAt: '1 day ago',
        isRead: true,
      ),
    ];

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
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          NexusButton(label: 'Add Feed', icon: Icons.add, onPressed: () {}),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const NexusInput(
              hintText: 'Search articles...',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            const SizedBox(height: NexusSpacing.md),
            ...feeds.map(
              (feed) => Padding(
                padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
                child: _FeedCard(feed: feed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedItem {
  const _FeedItem({
    required this.title,
    required this.source,
    required this.summary,
    required this.publishedAt,
    required this.isRead,
  });

  final String title;
  final String source;
  final String summary;
  final String publishedAt;
  final bool isRead;
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.feed});

  final _FeedItem feed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: feed.isRead
                  ? colorScheme.outlineVariant
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
                  feed.title,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: feed.isRead ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  feed.summary,
                  style: NexusTypography.labelMd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NexusSpacing.sm),
                Row(
                  children: [
                    NexusBadge(label: feed.source),
                    const SizedBox(width: NexusSpacing.sm),
                    Text(feed.publishedAt, style: NexusTypography.labelSm),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
        ],
      ),
    );
  }
}
