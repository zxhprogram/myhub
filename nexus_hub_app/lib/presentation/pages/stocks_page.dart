import 'package:flutter/material.dart';

import '../../data/models/global_index_model.dart';
import '../../data/services/global_index_service.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/global_index_carousel.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

class StocksPage extends StatefulWidget {
  const StocksPage({super.key});

  @override
  State<StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<StocksPage> {
  final _globalIndexService = GlobalIndexService();
  List<GlobalIndex> _globalIndices = [];
  bool _isLoadingIndices = true;
  String? _indexError;

  @override
  void initState() {
    super.initState();
    _loadIndices();
  }

  Future<void> _loadIndices() async {
    setState(() {
      _isLoadingIndices = true;
      _indexError = null;
    });
    try {
      final indices = await _globalIndexService.fetchIndices();
      if (mounted) {
        setState(() {
          _globalIndices = indices;
          _isLoadingIndices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _indexError = 'Failed to load global indices.';
          _isLoadingIndices = false;
        });
      }
    }
  }

  Future<void> _refreshIndices() async {
    setState(() {
      _isLoadingIndices = true;
      _indexError = null;
    });
    try {
      final indices = await _globalIndexService.refreshIndices();
      if (mounted) {
        setState(() {
          _globalIndices = indices;
          _isLoadingIndices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _indexError = 'Failed to refresh global indices.';
          _isLoadingIndices = false;
        });
      }
    }
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
              Text('Stocks & Markets', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Real-time portfolio and market tracking',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 1000;
            return Column(
              children: [
                // Global indices carousel
                if (_isLoadingIndices)
                  NexusCard(
                    child: SizedBox(
                      height: 200,
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
                  )
                else if (_indexError != null)
                  NexusCard(
                    child: SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 32,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(height: NexusSpacing.sm),
                            Text(
                              _indexError!,
                              style: NexusTypography.bodyMd.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: NexusSpacing.sm),
                            TextButton.icon(
                              onPressed: _loadIndices,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  GlobalIndexCarousel(
                    indices: _globalIndices,
                    onRefresh: _refreshIndices,
                  ),
                const SizedBox(height: NexusSpacing.md),

                // Market cards
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(flex: 8, child: _WatchlistCard()),
                      const SizedBox(width: NexusSpacing.md),
                      const Expanded(flex: 4, child: _MarketOverviewCard()),
                    ],
                  )
                else
                  const Column(
                    children: [
                      _WatchlistCard(),
                      SizedBox(height: NexusSpacing.md),
                      _MarketOverviewCard(),
                    ],
                  ),
                const SizedBox(height: NexusSpacing.md),
                const _HoldingsCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                  color: colorScheme.onSurfaceVariant,
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
    final colorScheme = Theme.of(context).colorScheme;
    final color = isUp ? NexusColors.stockUp : NexusColors.stockDown;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
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

class _MarketOverviewCard extends StatelessWidget {
  const _MarketOverviewCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Market Overview', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          _OverviewRow(
            label: 'VIX',
            value: '14.32',
            change: '-0.45',
            isUp: false,
          ),
          const SizedBox(height: NexusSpacing.sm),
          _OverviewRow(
            label: '10Y Yield',
            value: '4.28%',
            change: '+0.02',
            isUp: true,
          ),
          const SizedBox(height: NexusSpacing.sm),
          _OverviewRow(
            label: 'DXY',
            value: '104.12',
            change: '+0.18',
            isUp: true,
          ),
          const SizedBox(height: NexusSpacing.sm),
          _OverviewRow(
            label: 'BTC/USD',
            value: '67,890',
            change: '+1.2%',
            isUp: true,
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.label,
    required this.value,
    required this.change,
    required this.isUp,
  });

  final String label;
  final String value;
  final String change;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isUp ? NexusColors.stockUp : NexusColors.stockDown;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: NexusTypography.bodyMd),
        Row(
          children: [
            Text(
              value,
              style: NexusTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(change, style: NexusTypography.labelSm.copyWith(color: color)),
          ],
        ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;
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
                    color: colorScheme.secondary,
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
                              color: colorScheme.surfaceContainerHighest,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: Text(label.toUpperCase(), style: NexusTypography.labelSm),
    );
  }
}
