import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

class StocksPage extends StatelessWidget {
  const StocksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stocks & Markets', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Real-time portfolio and market tracking',
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          NexusCard(
            padding: const EdgeInsets.all(NexusSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('TOTAL PORTFOLIO VALUE', style: NexusTypography.labelSm),
                const SizedBox(height: NexusSpacing.xs),
                Row(
                  children: [
                    Text('\$124,592.45', style: NexusTypography.headlineLg),
                    const SizedBox(width: NexusSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexusSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: NexusColors.stockUp.withValues(alpha: 0.1),
                        borderRadius: NexusRadii.mdRadius,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.trending_up,
                            size: 16,
                            color: NexusColors.stockUp,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '+2.4%',
                            style: NexusTypography.bodyMd.copyWith(
                              color: NexusColors.stockUp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(flex: 8, child: _IndexChartCard()),
                    const SizedBox(width: NexusSpacing.md),
                    const Expanded(flex: 4, child: _WatchlistCard()),
                  ],
                )
              else
                const Column(
                  children: [
                    _IndexChartCard(),
                    SizedBox(height: NexusSpacing.md),
                    _WatchlistCard(),
                  ],
                ),
              const SizedBox(height: NexusSpacing.md),
              const _HoldingsCard(),
            ],
          );
        },
      ),
    );
  }
}

class _IndexChartCard extends StatelessWidget {
  const _IndexChartCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('S&P 500 Index', style: NexusTypography.headlineSm),
                      const SizedBox(width: NexusSpacing.sm),
                      const NexusBadge(label: 'SPX'),
                    ],
                  ),
                  const SizedBox(height: NexusSpacing.xs),
                  Row(
                    children: [
                      Text('5,088.80', style: NexusTypography.headlineSm),
                      const SizedBox(width: NexusSpacing.sm),
                      Text(
                        '+0.82% (+41.40)',
                        style: NexusTypography.bodyMd.copyWith(
                          color: NexusColors.stockUp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _TimeButton(label: '1D'),
                  const SizedBox(width: NexusSpacing.xs),
                  _TimeButton(label: '1W', isActive: true),
                  const SizedBox(width: NexusSpacing.xs),
                  _TimeButton(label: '1M'),
                  const SizedBox(width: NexusSpacing.xs),
                  _TimeButton(label: 'YTD'),
                ],
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.lg),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerLow.withValues(alpha: 0.3),
              borderRadius: NexusRadii.mdRadius,
              border: Border.all(
                color: NexusColors.outlineVariant.withValues(alpha: 0.1),
              ),
            ),
            child: CustomPaint(
              size: const Size.fromHeight(280),
              painter: _StockChartPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, this.isActive = false});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? NexusColors.primary : Colors.transparent,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: () {},
        borderRadius: NexusRadii.mdRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive
                  ? NexusColors.primary
                  : NexusColors.outlineVariant.withValues(alpha: 0.3),
            ),
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Text(
            label,
            style: NexusTypography.labelMd.copyWith(
              color: isActive
                  ? NexusColors.onPrimary
                  : NexusColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _StockChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = NexusColors.outlineVariant.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;

    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = NexusColors.stockUp
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.8)
      ..quadraticBezierTo(
        size.width * 0.1,
        size.height * 0.75,
        size.width * 0.2,
        size.height * 0.6,
      )
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.55,
        size.width * 0.6,
        size.height * 0.3,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.4,
        size.width,
        size.height * 0.2,
      );

    canvas.drawPath(path, linePaint);

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
            NexusColors.stockUp.withValues(alpha: 0.1),
            NexusColors.stockUp.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard();

  @override
  Widget build(BuildContext context) {
    final stocks = [
      ('AAPL', 'Apple Inc.', 'Tech', 182.52, 1.2, true),
      ('TSLA', 'Tesla', 'Auto', 199.40, -0.8, false),
      ('GOOG', 'Alphabet', 'Tech', 144.85, 2.1, true),
      ('MSFT', 'Microsoft', 'Tech', 410.34, 0.5, true),
    ];

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Watchlist', style: NexusTypography.headlineSm),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.add,
                  size: 20,
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          ...stocks.map(
            (stock) => _WatchlistItem(
              symbol: stock.$1,
              name: stock.$2,
              sector: stock.$3,
              price: stock.$4,
              change: stock.$5,
              isUp: stock.$6,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchlistItem extends StatelessWidget {
  const _WatchlistItem({
    required this.symbol,
    required this.name,
    required this.sector,
    required this.price,
    required this.change,
    required this.isUp,
  });

  final String symbol;
  final String name;
  final String sector;
  final double price;
  final double change;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    final color = isUp ? NexusColors.stockUp : NexusColors.stockDown;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NexusColors.surfaceVariant,
              borderRadius: NexusRadii.mdRadius,
            ),
            alignment: Alignment.center,
            child: Text(
              symbol,
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
                Text(
                  name,
                  style: NexusTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(sector, style: NexusTypography.labelSm),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            height: 32,
            child: CustomPaint(
              size: const Size(64, 32),
              painter: _SparklinePainter(isUp: isUp),
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${isUp ? '+' : ''}${change.toStringAsFixed(1)}%',
                style: NexusTypography.labelSm.copyWith(color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.isUp});

  final bool isUp;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isUp ? NexusColors.stockUp : NexusColors.stockDown
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = isUp
        ? (Path()
            ..moveTo(0, size.height * 0.8)
            ..lineTo(size.width * 0.2, size.height * 0.6)
            ..lineTo(size.width * 0.4, size.height * 0.7)
            ..lineTo(size.width * 0.6, size.height * 0.4)
            ..lineTo(size.width * 0.8, size.height * 0.5)
            ..lineTo(size.width, size.height * 0.1))
        : (Path()
            ..moveTo(0, size.height * 0.2)
            ..lineTo(size.width * 0.2, size.height * 0.4)
            ..lineTo(size.width * 0.4, size.height * 0.3)
            ..lineTo(size.width * 0.6, size.height * 0.6)
            ..lineTo(size.width * 0.8, size.height * 0.5)
            ..lineTo(size.width, size.height * 0.9));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HoldingsCard extends StatelessWidget {
  const _HoldingsCard();

  @override
  Widget build(BuildContext context) {
    final holdings = [
      ('AAPL', 'Apple Inc.', 50, 175.30, 182.52),
      ('MSFT', 'Microsoft', 30, 380.00, 410.34),
      ('GOOG', 'Alphabet', 20, 135.20, 144.85),
      ('TSLA', 'Tesla', 15, 210.00, 199.40),
    ];

    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Holdings', style: NexusTypography.headlineSm),
              TextButton(
                onPressed: () {},
                child: Text(
                  'View All',
                  style: NexusTypography.labelSm.copyWith(
                    color: NexusColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                children: [
                  _TableHeader('Asset'),
                  _TableHeader('Qty'),
                  _TableHeader('Avg Cost'),
                  _TableHeader('Price'),
                  _TableHeader('P/L'),
                ],
              ),
              ...holdings.map((h) {
                final pl = (h.$5 - h.$4) * h.$3;
                final isUp = pl >= 0;
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: NexusSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: NexusColors.surfaceVariant,
                              borderRadius: NexusRadii.mdRadius,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              h.$1,
                              style: NexusTypography.labelSm.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: NexusSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.$2, style: NexusTypography.bodyMd),
                              Text(h.$1, style: NexusTypography.labelSm),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text('${h.$3}', style: NexusTypography.bodyMd),
                    Text(
                      '\$${h.$4.toStringAsFixed(2)}',
                      style: NexusTypography.bodyMd,
                    ),
                    Text(
                      '\$${h.$5.toStringAsFixed(2)}',
                      style: NexusTypography.bodyMd,
                    ),
                    Text(
                      '\$${pl.abs().toStringAsFixed(2)}',
                      style: NexusTypography.bodyMd.copyWith(
                        color: isUp
                            ? NexusColors.stockUp
                            : NexusColors.stockDown,
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: Text(label.toUpperCase(), style: NexusTypography.labelSm),
    );
  }
}
