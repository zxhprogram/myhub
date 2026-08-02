import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/global_index_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'global_index_detail_page.dart';

/// A carousel widget that displays global index cards with auto-scroll and
/// manual navigation.
class GlobalIndexCarousel extends StatefulWidget {
  const GlobalIndexCarousel({
    super.key,
    required this.indices,
    this.onRefresh,
  });

  final List<GlobalIndex> indices;
  final VoidCallback? onRefresh;

  @override
  State<GlobalIndexCarousel> createState() => _GlobalIndexCarouselState();
}

class _GlobalIndexCarouselState extends State<GlobalIndexCarousel> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  bool _isPaused = false;

  int get _itemCount => widget.indices.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction());
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(GlobalIndexCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If items changed, reset position.
    if (oldWidget.indices != widget.indices && _itemCount > 0) {
      _currentPage = 0;
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  double _viewportFraction() {
    // Use LayoutBuilder to be responsive.
    // Default is 0.9 for single item, 0.45 for two, 0.3 for three.
    // We set this in the build method based on actual constraints.
    return 0.85;
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isPaused && _itemCount > 1 && mounted) {
        final next = (_currentPage + 1) % _itemCount;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _goToPage(int index) {
    _autoScrollTimer?.cancel();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _startAutoScroll();
  }

  void _navigateToDetail(GlobalIndex index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GlobalIndexDetailPage(index: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.indices.isEmpty) {
      return const SizedBox.shrink();
    }

    // Determine how many items to show per page based on width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final isMedium = constraints.maxWidth > 600;
        final itemsPerPage = isWide ? 3 : (isMedium ? 2 : 1);
        final viewportFraction = 1.0 / itemsPerPage - 0.02;

        // Update viewport fraction after first build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            // viewportFraction is set at init, we can't change it easily.
            // Instead, we use a different approach: group items into pages.
          }
        });

        // Group items into pages.
        final pages = <List<GlobalIndex>>[];
        for (var i = 0; i < widget.indices.length; i += itemsPerPage) {
          final end = (i + itemsPerPage > widget.indices.length)
              ? widget.indices.length
              : i + itemsPerPage;
          pages.add(widget.indices.sublist(i, end));
        }

        final totalPages = pages.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Global Indices', style: NexusTypography.headlineSm),
                  if (widget.onRefresh != null)
                    SizedBox(
                      height: 32,
                      child: IconButton(
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        color: NexusColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // Carousel area
            SizedBox(
              height: 160,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isPaused = true),
                onExit: (_) => setState(() => _isPaused = false),
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                  },
                  itemCount: totalPages,
                  itemBuilder: (context, pageIndex) {
                    final items = pages[pageIndex];
                    return Row(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(width: NexusSpacing.sm),
                          Expanded(
                            child: _IndexCard(
                              index: items[i],
                              onTap: () => _navigateToDetail(items[i]),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            // Dots indicator
            if (totalPages > 1)
              Padding(
                padding: const EdgeInsets.only(top: NexusSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(totalPages, (i) {
                    final isActive = i == _currentPage;
                    return GestureDetector(
                      onTap: () => _goToPage(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? NexusColors.primary
                              : NexusColors.outlineVariant.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IndexCard extends StatelessWidget {
  const _IndexCard({required this.index, required this.onTap});

  final GlobalIndex index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = index.isUp ? NexusColors.stockUp : NexusColors.stockDown;

    return Material(
      color: NexusColors.surfaceContainerLow,
      borderRadius: NexusRadii.lgRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.lgRadius,
        child: Container(
          padding: const EdgeInsets.all(NexusSpacing.md),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.lgRadius,
            border: Border.all(
              color: NexusColors.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: symbol badge + name
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: NexusRadii.smRadius,
                    ),
                    child: Text(
                      index.symbol,
                      style: NexusTypography.labelSm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  Expanded(
                    child: Text(
                      index.name,
                      style: NexusTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              // Price
              Text(
                index.formattedPrice,
                style: NexusTypography.headlineSm.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: NexusSpacing.xs),
              // Change row
              Row(
                children: [
                  Icon(
                    index.isUp ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    index.formattedChange,
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: NexusRadii.smRadius,
                    ),
                    child: Text(
                      index.formattedChangePercent,
                      style: NexusTypography.labelSm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Update time
              if (index.updateTime.isNotEmpty)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    index.updateTime,
                    style: NexusTypography.labelSm.copyWith(
                      color: NexusColors.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}