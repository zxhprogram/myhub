import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

class MyComputerPage extends StatelessWidget {
  const MyComputerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Computer', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            'System health, storage and running applications',
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
              if (isWide)
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _CpuCard()),
                    SizedBox(width: NexusSpacing.md),
                    Expanded(child: _MemoryCard()),
                    SizedBox(width: NexusSpacing.md),
                    Expanded(child: _StorageCard()),
                  ],
                )
              else
                const Column(
                  children: [
                    _CpuCard(),
                    SizedBox(height: NexusSpacing.md),
                    _MemoryCard(),
                    SizedBox(height: NexusSpacing.md),
                    _StorageCard(),
                  ],
                ),
              const SizedBox(height: NexusSpacing.md),
              const _NetworkCard(),
              const SizedBox(height: NexusSpacing.md),
              const _AppUsageCard(),
            ],
          );
        },
      ),
    );
  }
}

class _CpuCard extends StatelessWidget {
  const _CpuCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CPU', style: NexusTypography.headlineSm),
              Text('42%', style: NexusTypography.bodyLg),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          SizedBox(
            height: 80,
            child: CustomPaint(
              size: const Size.fromHeight(80),
              painter: _SparklinePainter(color: NexusColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Memory', style: NexusTypography.headlineSm),
              Text('12.4 / 32 GB', style: NexusTypography.bodyLg),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          ClipRRect(
            borderRadius: NexusRadii.fullRadius,
            child: LinearProgressIndicator(
              value: 0.39,
              minHeight: 12,
              backgroundColor: NexusColors.surfaceContainer,
              valueColor: const AlwaysStoppedAnimation(NexusColors.secondary),
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Text('38.8% used', style: NexusTypography.labelMd),
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Storage', style: NexusTypography.headlineSm),
              Text('512 / 1 TB', style: NexusTypography.bodyLg),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          ClipRRect(
            borderRadius: NexusRadii.fullRadius,
            child: LinearProgressIndicator(
              value: 0.5,
              minHeight: 12,
              backgroundColor: NexusColors.surfaceContainer,
              valueColor: const AlwaysStoppedAnimation(NexusColors.tertiary),
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Text('50% used', style: NexusTypography.labelMd),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Network Activity', style: NexusTypography.headlineSm),
              Row(
                children: [
                  _LegendDot(color: NexusColors.secondary, label: 'Download'),
                  const SizedBox(width: NexusSpacing.md),
                  _LegendDot(color: NexusColors.tertiary, label: 'Upload'),
                ],
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerLow,
              borderRadius: NexusRadii.mdRadius,
              border: Border.all(
                color: NexusColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: CustomPaint(
              size: const Size.fromHeight(180),
              painter: _NetworkChartPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: NexusRadii.fullRadius,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: NexusTypography.labelMd),
      ],
    );
  }
}

class _NetworkChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = NexusColors.outlineVariant.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;

    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final downloadPaint = Paint()
      ..color = NexusColors.secondary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final uploadPaint = Paint()
      ..color = NexusColors.tertiary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    Path buildPath(int seed) {
      final path = Path();
      final r = Random(seed);
      path.moveTo(0, size.height * (0.3 + r.nextDouble() * 0.4));
      for (var i = 1; i <= 20; i++) {
        path.lineTo(
          size.width * i / 20,
          size.height * (0.2 + r.nextDouble() * 0.6),
        );
      }
      return path;
    }

    canvas.drawPath(buildPath(1), downloadPaint);
    canvas.drawPath(buildPath(2), uploadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.8)
      ..lineTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.4, size.height * 0.7)
      ..lineTo(size.width * 0.6, size.height * 0.3)
      ..lineTo(size.width * 0.8, size.height * 0.6)
      ..lineTo(size.width, size.height * 0.2);

    canvas.drawPath(path, paint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AppUsageCard extends StatelessWidget {
  const _AppUsageCard();

  @override
  Widget build(BuildContext context) {
    final apps = [
      ('Flutter', '3.2 h', 0.65),
      ('VS Code', '2.8 h', 0.55),
      ('Chrome', '1.9 h', 0.40),
      ('Terminal', '0.8 h', 0.18),
    ];

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('App Usage', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          ...apps.map(
            (app) => Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: NexusColors.surfaceContainer,
                      borderRadius: NexusRadii.mdRadius,
                      border: Border.all(
                        color: NexusColors.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      app.$1[0],
                      style: NexusTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(app.$1, style: NexusTypography.bodyMd),
                            Text(app.$2, style: NexusTypography.labelMd),
                          ],
                        ),
                        const SizedBox(height: NexusSpacing.xs),
                        ClipRRect(
                          borderRadius: NexusRadii.fullRadius,
                          child: LinearProgressIndicator(
                            value: app.$3,
                            minHeight: 6,
                            backgroundColor: NexusColors.surfaceContainer,
                            valueColor: AlwaysStoppedAnimation(
                              NexusColors.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
