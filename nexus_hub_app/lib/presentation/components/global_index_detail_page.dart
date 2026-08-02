import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/global_index_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';

/// Detail page for a single global index, showing its data, a sparkline-style
/// chart, and a link to the fx678 detail page.
class GlobalIndexDetailPage extends StatelessWidget {
  const GlobalIndexDetailPage({super.key, required this.index});

  final GlobalIndex index;

  @override
  Widget build(BuildContext context) {
    final color = index.isUp ? NexusColors.stockUp : NexusColors.stockDown;

    return Scaffold(
      backgroundColor: NexusColors.surface,
      appBar: AppBar(
        backgroundColor: NexusColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: NexusColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(index.name, style: NexusTypography.headlineSm),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.open_in_new,
              color: NexusColors.onSurfaceVariant,
            ),
            tooltip: 'Open in browser',
            onPressed: () => _openFx678(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Price header
            NexusCard(
              child: Padding(
                padding: const EdgeInsets.all(NexusSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: NexusRadii.smRadius,
                          ),
                          child: Text(
                            index.symbol,
                            style: NexusTypography.labelMd.copyWith(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (index.updateTime.isNotEmpty)
                          Text(
                            'Updated: ${index.updateTime}',
                            style: NexusTypography.labelSm.copyWith(
                              color: NexusColors.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: NexusSpacing.lg),
                    Text(
                      index.formattedPrice,
                      style: NexusTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: NexusColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          index.isUp
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 20,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${index.formattedChange} (${index.formattedChangePercent})',
                          style: NexusTypography.headlineSm.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),

            // Chart area
            NexusCard(
              child: Padding(
                padding: const EdgeInsets.all(NexusSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time-sharing Chart',
                      style: NexusTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.md),
                    SizedBox(
                      height: 240,
                      child: CustomPaint(
                        size: const Size.fromHeight(240),
                        painter: _IndexChartPainter(index: index),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),

            // Data grid
            NexusCard(
              child: Padding(
                padding: const EdgeInsets.all(NexusSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Key Data',
                      style: NexusTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.md),
                    _DataRow(label: 'Open', value: index.prevClose.toStringAsFixed(2)),
                    const SizedBox(height: NexusSpacing.sm),
                    _DataRow(
                      label: 'High',
                      value: index.high.toStringAsFixed(2),
                      valueColor: NexusColors.stockUp,
                    ),
                    const SizedBox(height: NexusSpacing.sm),
                    _DataRow(
                      label: 'Low',
                      value: index.low.toStringAsFixed(2),
                      valueColor: NexusColors.stockDown,
                    ),
                    const SizedBox(height: NexusSpacing.sm),
                    _DataRow(
                      label: 'Previous Close',
                      value: index.prevClose.toStringAsFixed(2),
                    ),
                    const SizedBox(height: NexusSpacing.sm),
                    _DataRow(
                      label: 'Change',
                      value: '${index.formattedChange} (${index.formattedChangePercent})',
                      valueColor: color,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),

            // View on fx678 button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openFx678,
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexusColors.primary,
                  side: BorderSide(
                    color: NexusColors.primary.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: NexusRadii.mdRadius,
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  'View Full Details on fx678',
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFx678() async {
    final uri = Uri.parse(index.detailUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: NexusTypography.bodyMd.copyWith(
            color: NexusColors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: NexusTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? NexusColors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// A simple chart painter that draws a stylized time-sharing curve.
class _IndexChartPainter extends CustomPainter {
  _IndexChartPainter({required this.index});

  final GlobalIndex index;

  @override
  void paint(Canvas canvas, Size size) {
    final color = index.isUp ? NexusColors.stockUp : NexusColors.stockDown;

    // Grid lines
    final gridPaint = Paint()
      ..color = NexusColors.outlineVariant.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;

    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Generate a realistic-looking curve using the index data.
    // The curve goes from prevClose to latestPrice over the day.
    final startY = _mapPrice(index.prevClose, size.height);
    final endY = _mapPrice(index.latestPrice, size.height);
    final midY = (startY + endY) / 2;

    // Add some noise to simulate real market movement.
    final path = Path()..moveTo(0, startY);

    final segments = 20;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      final x = size.width * t;
      // Bezier-like interpolation with slight random variation.
      final progress = 1 - (1 - t) * (1 - t); // ease-out
      final baseY = startY + (endY - startY) * progress;
      final noise = (i % 3 - 1) * size.height * 0.01;
      path.lineTo(x, baseY + noise);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Fill area under the curve.
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
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Draw current price label at the end.
    final textPainter = TextPainter(
      text: TextSpan(
        text: index.formattedPrice,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'SF Mono, Consolas, monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(size.width - textPainter.width - 4, endY - 18),
    );
  }

  double _mapPrice(double price, double height) {
    // Map the price range to the chart height. Use a range around the data.
    final range = (index.high - index.low) * 1.3;
    final mid = (index.high + index.low) / 2;
    final top = mid + range / 2;
    final bottom = mid - range / 2;
    return (top - price) / (top - bottom) * height;
  }

  @override
  bool shouldRepaint(covariant _IndexChartPainter oldDelegate) {
    return oldDelegate.index.latestPrice != index.latestPrice;
  }
}