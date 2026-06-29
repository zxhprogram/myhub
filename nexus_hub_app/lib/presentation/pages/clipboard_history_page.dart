import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';

class ClipboardHistoryPage extends StatelessWidget {
  const ClipboardHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ClipboardItem(
        content: 'flutter pub add go_router signals dio sqflite',
        type: 'code',
        copiedAt: '2 min ago',
      ),
      _ClipboardItem(
        content: 'meeting notes: finalize API contracts by Friday',
        type: 'text',
        copiedAt: '15 min ago',
      ),
      _ClipboardItem(
        content: 'https://dart.dev/guides',
        type: 'link',
        copiedAt: '1 hour ago',
      ),
      _ClipboardItem(
        content: 'export PATH=\$PATH:/usr/local/flutter/bin',
        type: 'code',
        copiedAt: '3 hours ago',
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
              Text('Clipboard History', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Recent copied items, searchable and reusable',
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          NexusButton(
            label: 'Clear History',
            icon: Icons.delete_outline,
            variant: NexusButtonVariant.outlined,
            onPressed: () {},
          ),
        ],
      ),
      child: Column(
        children: [
          const NexusInput(
            hintText: 'Search clipboard...',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
          const SizedBox(height: NexusSpacing.md),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
              child: _ClipboardCard(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipboardItem {
  const _ClipboardItem({
    required this.content,
    required this.type,
    required this.copiedAt,
  });

  final String content;
  final String type;
  final String copiedAt;
}

class _ClipboardCard extends StatelessWidget {
  const _ClipboardCard({required this.item});

  final _ClipboardItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      'code' => Icons.code,
      'link' => Icons.link,
      _ => Icons.text_fields,
    };

    return NexusCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainer,
              borderRadius: NexusRadii.mdRadius,
              border: Border.all(
                color: NexusColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.content,
                  style: NexusTypography.bodyMd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  '${item.type.toUpperCase()} • ${item.copiedAt}',
                  style: NexusTypography.labelSm,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.copy, size: 18),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
