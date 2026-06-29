import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back, Alex', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            'Here is everything happening today',
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1000;
          return Column(
            children: [
              Wrap(
                spacing: NexusSpacing.md,
                runSpacing: NexusSpacing.md,
                children: [
                  _MetricCard(
                    label: 'Tasks Done',
                    value: '12',
                    trend: '+3 today',
                    color: NexusColors.secondary,
                  ),
                  _MetricCard(
                    label: 'Unread Articles',
                    value: '8',
                    trend: '2 new',
                    color: NexusColors.tertiary,
                  ),
                  _MetricCard(
                    label: 'Bookmarks',
                    value: '142',
                    trend: '+5 this week',
                    color: NexusColors.primary,
                  ),
                  _MetricCard(
                    label: 'Portfolio',
                    value: '\$124,592',
                    trend: '+2.4%',
                    color: NexusColors.stockUp,
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              if (isWide)
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _RecentTasksCard()),
                    SizedBox(width: NexusSpacing.md),
                    Expanded(child: _FocusChartCard()),
                  ],
                )
              else
                const Column(
                  children: [
                    _RecentTasksCard(),
                    SizedBox(height: NexusSpacing.md),
                    _FocusChartCard(),
                  ],
                ),
              const SizedBox(height: NexusSpacing.md),
              const _QuickActionsCard(),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
  });

  final String label;
  final String value;
  final String trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NexusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: NexusRadii.fullRadius,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Text(value, style: NexusTypography.headlineLg),
            const SizedBox(height: NexusSpacing.xs),
            Text(label, style: NexusTypography.bodyMd),
            const SizedBox(height: NexusSpacing.xs),
            Text(trend, style: NexusTypography.labelMd.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _RecentTasksCard extends StatelessWidget {
  const _RecentTasksCard();

  @override
  Widget build(BuildContext context) {
    final tasks = [
      ('Review PR #402', 'Work', 'high'),
      ('Read AI paper', 'Learning', 'medium'),
      ('Buy groceries', 'Personal', 'low'),
      ('Plan sprint', 'Work', 'high'),
    ];

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Tasks', style: NexusTypography.headlineSm),
              TextButton(
                onPressed: () {},
                child: Text(
                  'See all',
                  style: NexusTypography.labelMd.copyWith(
                    color: NexusColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.circle_outlined,
                    size: 18,
                    color: NexusColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  Expanded(child: Text(task.$1, style: NexusTypography.bodyMd)),
                  NexusBadge(label: task.$2),
                  const SizedBox(width: NexusSpacing.sm),
                  _PriorityDot(priority: task.$3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' => NexusColors.error,
      'medium' => NexusColors.secondary,
      _ => NexusColors.outline,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: NexusRadii.fullRadius,
      ),
    );
  }
}

class _FocusChartCard extends StatelessWidget {
  const _FocusChartCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Focus Hours', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.sm),
          Text(
            'This week: 18h 20m',
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexusSpacing.md),
          SizedBox(
            height: 64,
            child: Row(
              children: List.generate(45, (index) {
                final opacity = Random().nextDouble();
                Color color;
                if (opacity < 0.2) {
                  color = NexusColors.surfaceVariant;
                } else if (opacity < 0.5) {
                  color = NexusColors.secondaryFixedDim.withValues(alpha: 0.4);
                } else if (opacity < 0.8) {
                  color = NexusColors.secondaryFixedDim.withValues(alpha: 0.7);
                } else {
                  color = NexusColors.secondaryContainer;
                }
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: NexusRadii.smRadius,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('New Task', Icons.add_task),
      ('Add Bookmark', Icons.bookmark_add_outlined),
      ('AI Ask', Icons.chat_bubble_outline),
      ('Copy Snippet', Icons.content_copy),
    ];

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.md,
            children: actions
                .map(
                  (action) => NexusButton(
                    label: action.$1,
                    icon: action.$2,
                    variant: NexusButtonVariant.outlined,
                    onPressed: () {},
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
