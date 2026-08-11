import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/trending_repo_model.dart';
import '../../data/services/trending_service.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

/// GitHub Trending — shows trending repositories for today/weekly/monthly.
class TrendingPage extends StatefulWidget {
  const TrendingPage({super.key});

  @override
  State<TrendingPage> createState() => _TrendingPageState();
}

enum _TrendingSince { daily, weekly, monthly }

class _TrendingPageState extends State<TrendingPage> {
  final TrendingService _service = TrendingService();

  _TrendingSince _since = _TrendingSince.daily;
  List<TrendingRepo> _repos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    final repos = await _service.fetchTrending();
    if (!mounted) return;
    setState(() {
      _repos = repos;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
    });
    final repos = await _service.refreshTrending();
    if (!mounted) return;
    setState(() {
      _repos = repos;
      _isLoading = false;
    });
  }

  void _selectSince(_TrendingSince since) {
    if (_since == since) return;
    setState(() => _since = since);
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
              Text('GitHub Trending', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Discover popular open-source repositories',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          _buildSinceSelector(),
        ],
      ),
      child: _isLoading ? _buildLoading() : _buildList(),
    );
  }

  Widget _buildSinceSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: NexusSpacing.xs),
        for (final (since, label) in [
          (_TrendingSince.daily, 'Today'),
          (_TrendingSince.weekly, 'This Week'),
          (_TrendingSince.monthly, 'This Month'),
        ]) ...[
          const SizedBox(width: NexusSpacing.xs),
          _SelectableChip(
            label: label,
            isSelected: _since == since,
            onTap: () => _selectSince(since),
          ),
        ],
      ],
    );
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

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _repos.length,
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
        itemBuilder: (context, index) {
          return TrendingRepoCard(repo: _repos[index]);
        },
      ),
    );
  }
}

/// A single trending repository row card.
class TrendingRepoCard extends StatelessWidget {
  const TrendingRepoCard({super.key, required this.repo});

  final TrendingRepo repo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: () => _openRepo(context),
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo.fullName,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (repo.hasDescription) ...[
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    repo.description,
                    style: NexusTypography.bodyMd,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: NexusSpacing.sm),
                _buildMetadataRow(context),
                if (repo.builtBy.isNotEmpty) ...[
                  const SizedBox(height: NexusSpacing.sm),
                  _buildBuiltByRow(),
                ],
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          _buildStarsColumn(),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Transparent placeholder keeps the row height consistent between
    // leading-icon and no-leading-icon languages.
    final languageColor =
        repo.languageColor.isNotEmpty
            ? Color(int.parse('FF${repo.languageColor.substring(1)}',
                radix: 16))
            : Colors.transparent;

    return Wrap(
      spacing: NexusSpacing.md,
      runSpacing: NexusSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (repo.language != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: languageColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(repo.language!, style: NexusTypography.labelSm),
            ],
          ),
        _IconStat(
          icon: Icons.star_border,
          text: repo.formattedStars,
        ),
        _IconStat(
          icon: Icons.call_split_outlined,
          text: repo.formattedForks,
        ),
        Text('•', style: NexusTypography.labelSm),
        Text('Built by', style: NexusTypography.labelSm),
      ],
    );
  }

  Widget _buildBuiltByRow() {
    return Row(
      children: [
        for (final contributor in repo.builtBy)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ClipOval(
              child: SizedBox(
                width: 20,
                height: 20,
                child: contributor.avatar.isNotEmpty
                    ? Image.network(
                        contributor.avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _ContributorPlaceholder(text: contributor.username),
                      )
                    : _ContributorPlaceholder(text: contributor.username),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStarsColumn() {
    final upColor = NexusColors.stockUp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up, size: 14, color: upColor),
            const SizedBox(width: 2),
            Text(
              repo.formattedPeriodStars,
              style: NexusTypography.labelMd.copyWith(
                color: upColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.xs),
        Text('today', style: NexusTypography.labelSm),
      ],
    );
  }

  Future<void> _openRepo(BuildContext context) async {
    final uri = Uri.tryParse(repo.url);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _IconStat extends StatelessWidget {
  const _IconStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: NexusTypography.labelSm),
      ],
    );
  }
}

class _ContributorPlaceholder extends StatelessWidget {
  const _ContributorPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      color: colorScheme.surfaceContainerHigh,
      child: Text(
        text.isEmpty ? '?' : text.characters.first.toUpperCase(),
        style: NexusTypography.labelSm.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A pill-style selectable filter chip used for the since (Today/Week/Month)
/// selector in the trending page header.
class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
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