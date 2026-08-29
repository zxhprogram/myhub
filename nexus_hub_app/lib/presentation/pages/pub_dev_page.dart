import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/pub_package_model.dart';
import '../../data/services/pub_dev_service.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_empty_state.dart';
import '../layout/page_scaffold.dart';

/// Pub Packages — newest packages published on pub.dev, in a master-detail
/// layout: package list on the left, natively-rendered package detail
/// (metadata, score, versions) on the right — no webview.
class PubDevPage extends StatefulWidget {
  const PubDevPage({super.key});

  @override
  State<PubDevPage> createState() => _PubDevPageState();
}

class _PubDevPageState extends State<PubDevPage> {
  final PubDevService _service = PubDevService();

  final List<PubPackage> _packages = [];
  int _nextPage = 1;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  PubPackage? _selectedPackage;
  PubPackageDetail? _detail;
  bool _isLoadingDetail = false;
  bool _detailFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _nextPage = 1;
      _hasMore = true;
    });
    final packages = await _service.fetchLatest(page: 1);
    if (!mounted) return;
    setState(() {
      _packages
        ..clear()
        ..addAll(packages);
      _hasMore = _service.hasMorePages(packages);
      _nextPage = 2;
      _isLoading = false;
      final keep = packages.any((p) => p == _selectedPackage);
      if (!keep) {
        _selectedPackage = packages.isEmpty ? null : packages.first;
        _detail = null;
        _detailFailed = false;
        if (_selectedPackage != null) _loadDetail();
      }
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _nextPage = 1;
      _hasMore = true;
    });
    final packages = await _service.refreshLatest();
    if (!mounted) return;
    setState(() {
      _packages
        ..clear()
        ..addAll(packages);
      _hasMore = _service.hasMorePages(packages);
      _nextPage = 2;
      _isLoading = false;
      final keep = packages.any((p) => p == _selectedPackage);
      if (!keep) {
        _selectedPackage = packages.isEmpty ? null : packages.first;
        _detail = null;
        _detailFailed = false;
        if (_selectedPackage != null) _loadDetail();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    final page = _nextPage;
    try {
      final packages = await _service.fetchLatest(page: page);
      if (!mounted) return;
      setState(() {
        _packages.addAll(packages);
        _hasMore = _service.hasMorePages(packages);
        _nextPage = page + 1;
      });
    } catch (_) {
      // Deeper pages fail hard (no mock fallback) — just stop paginating.
      if (!mounted) return;
      setState(() {
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _selectPackage(PubPackage package) {
    if (_selectedPackage == package) return;
    setState(() {
      _selectedPackage = package;
      _detail = null;
      _detailFailed = false;
    });
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final package = _selectedPackage;
    if (package == null) return;
    setState(() {
      _isLoadingDetail = true;
    });
    try {
      final detail = await _service.fetchPackageDetail(package.name);
      if (!mounted) return;
      if (_selectedPackage != package) return;
      setState(() {
        _detail = detail;
        _isLoadingDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_selectedPackage != package) return;
      setState(() {
        _detailFailed = true;
        _isLoadingDetail = false;
      });
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
              Text('Pub Packages', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Newest packages published on pub.dev',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          NexusButton(
            label: 'Refresh',
            icon: LucideIcons.refreshCw,
            variant: NexusButtonVariant.outlined,
            onPressed: _refresh,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 380, child: _buildListPane()),
          const SizedBox(width: NexusSpacing.md),
          Expanded(child: _buildDetailPane()),
        ],
      ),
    );
  }

  Widget _buildListPane() {
    if (_isLoading) return _buildLoading();
    return _buildList();
  }

  Widget _buildLoading() {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
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
    );
  }

  Widget _buildList() {
    final hasMore = _hasMore;
    return RefreshTrigger(
      onRefresh: () async {
        await _refresh();
      },
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _packages.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _packages.length) {
            return _buildLoadMoreTile();
          }
          final package = _packages[index];
          return _PackageListItem(
            package: package,
            isSelected: package == _selectedPackage,
            onTap: () => _selectPackage(package),
          );
        },
      ),
    );
  }

  Widget _buildLoadMoreTile() {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: _isLoadingMore ? null : _loadMore,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Center(
        child: _isLoadingMore
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary.withValues(alpha: 0.6),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.chevronDown,
                    size: 14,
                    color: colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text('Load More', style: NexusTypography.labelMd),
                ],
              ),
      ),
    );
  }

  Widget _buildDetailPane() {
    final package = _selectedPackage;
    if (package == null) {
      return NexusCard(
        child: NexusEmptyState(
          icon: LucideIcons.package,
          title: 'No package selected',
          subtitle: 'Pick a package on the left to see its details.',
        ),
      );
    }
    if (_isLoadingDetail && _detail == null) {
      return _buildLoading();
    }
    if (_detailFailed && _detail == null) {
      return NexusCard(
        child: NexusEmptyState(
          icon: LucideIcons.cloudOff,
          title: 'Could not load package',
          subtitle: 'Check your connection and try again.',
          action: NexusButton(
            label: 'Retry',
            icon: LucideIcons.refreshCw,
            onPressed: _loadDetail,
          ),
        ),
      );
    }
    return _PackageDetailView(
      detail: _detail,
      fallback: package,
      onRetry: _loadDetail,
    );
  }
}

/// Left-pane list item: package name, version badge and a short description.
class _PackageListItem extends StatelessWidget {
  const _PackageListItem({
    required this.package,
    required this.isSelected,
    required this.onTap,
  });

  final PubPackage package;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      onTap: onTap,
      highlight: isSelected,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  package.name,
                  style: NexusTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        isSelected ? colorScheme.primary : colorScheme.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusBadge(label: 'v${package.version}'),
            ],
          ),
          if (package.hasDescription) ...[
            const SizedBox(height: NexusSpacing.xs),
            Text(
              package.description,
              style: NexusTypography.labelMd,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Right-pane natively-rendered detail view for the selected package.
class _PackageDetailView extends StatelessWidget {
  const _PackageDetailView({
    required this.detail,
    required this.fallback,
    required this.onRetry,
  });

  /// Loaded detail; null while retrying after a failure.
  final PubPackageDetail? detail;

  /// Selected list item — still shows name/version while detail is reloading.
  final PubPackage fallback;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = detail?.name ?? fallback.name;
    final version = detail?.version ?? fallback.version;
    final description = detail?.description ?? fallback.description;
    final topics = detail?.topics ?? fallback.topics;

    return NexusCard(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(NexusSpacing.md),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: NexusTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.xs),
                    Row(
                      children: [
                        NexusBadge(label: 'v$version'),
                        if (detail?.published != null) ...[
                          const SizedBox(width: NexusSpacing.sm),
                          Text(
                            'Published '
                            '${DateFormat('yyyy-MM-dd').format(detail!.published!)}',
                            style: NexusTypography.labelSm.copyWith(
                              color: colorScheme.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.ghost(
                icon: const Icon(LucideIcons.refreshCw),
                onPressed: onRetry,
              ),
              IconButton.ghost(
                icon: const Icon(LucideIcons.compass),
                onPressed: () => _openUrl(context, detail?.url),
              ),
            ],
          ),
          if (detail?.score != null) ...[
            const SizedBox(height: NexusSpacing.md),
            _buildStatsRow(context, detail!.score!),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.md),
            Text(description, style: NexusTypography.bodyMd),
          ],
          if (topics.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.md),
            Wrap(
              spacing: NexusSpacing.xs,
              runSpacing: NexusSpacing.xs,
              children: [
                for (final topic in topics.take(8)) NexusChip(label: topic),
              ],
            ),
          ],
          if (detail case final d?) ...[
            if (d.hasHomepage || d.hasRepository) ...[
              const SizedBox(height: NexusSpacing.md),
              Wrap(
                spacing: NexusSpacing.md,
                runSpacing: NexusSpacing.xs,
                children: [
                  if (d.hasHomepage)
                    _LinkButton(
                      icon: LucideIcons.globe,
                      label: 'Homepage',
                      url: d.homepage,
                    ),
                  if (d.hasRepository)
                    _LinkButton(
                      icon: LucideIcons.github,
                      label: 'Repository',
                      url: d.repository,
                    ),
                ],
              ),
            ],
            if (d.versions.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.md),
              Text('Versions', style: NexusTypography.headlineSm.copyWith(
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: NexusSpacing.sm),
              for (final v in d.sortedVersions.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
                  child: Row(
                    children: [
                      NexusBadge(label: 'v${v.version}'),
                      const SizedBox(width: NexusSpacing.sm),
                      if (v.published != null)
                        Text(
                          DateFormat('yyyy-MM-dd').format(v.published!),
                          style: NexusTypography.labelSm.copyWith(
                            color: colorScheme.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            if (d.hasReadme) ...[
              const SizedBox(height: NexusSpacing.md),
              Text('README', style: NexusTypography.headlineSm.copyWith(
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: NexusSpacing.sm),
              _ReadmeView(html: d.readmeHtml),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, PubPackageScore score) {
    return Row(
      children: [
        _IconStat(
          icon: LucideIcons.award,
          text: '${score.grantedPoints}/${score.maxPoints} points',
        ),
        const SizedBox(width: NexusSpacing.md),
        _IconStat(
          icon: LucideIcons.heart,
          text: _formatCount(score.likeCount),
        ),
        const SizedBox(width: NexusSpacing.md),
        _IconStat(
          icon: LucideIcons.download,
          text:
              '${_formatCount(score.downloadCount30Days)} downloads / 30d',
        ),
      ],
    );
  }

  static String _formatCount(int count) {
    if (count < 1000) return '$count';
    if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '${(count / 1000).round()}k';
  }

  static Future<void> _openUrl(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Small icon + text stat used in the detail stats row.
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
        Icon(icon, size: 14, color: colorScheme.mutedForeground),
        const SizedBox(width: 4),
        Text(text, style: NexusTypography.labelSm),
      ],
    );
  }
}

/// Natively renders the README HTML scraped from pub.dev with
/// [HtmlWidget] — no webview. Links open in the external browser.
class _ReadmeView extends StatelessWidget {
  const _ReadmeView({required this.html});

  final String html;

  /// Cap mirroring [MailBodyView]: HtmlWidget parses synchronously on the
  /// UI thread, so oversized READMEs are truncated to avoid jank.
  static const int _maxHtmlBytes = 600 * 1024;

  @override
  Widget build(BuildContext context) {
    final border = '#C6C6CD';
    var body = html;
    if (body.length > _maxHtmlBytes) {
      body =
          '${body.substring(0, _maxHtmlBytes)}'
          '<p>… (README too large, truncated)</p>';
    }

    return HtmlWidget(
      '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    background: transparent;
    margin: 0;
    padding: 0;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }
  img { max-width: 100%; height: auto; }
  table { border-collapse: collapse; width: 100%; }
  td, th { padding: 6px; border: 1px solid $border; }
  pre, code {
    font-family: 'Cascadia Code', 'Consolas', monospace;
    font-size: 13px;
  }
  pre {
    background: rgba(127, 127, 127, 0.12);
    padding: 12px;
    border-radius: 6px;
    overflow-x: auto;
  }
  code { background: rgba(127, 127, 127, 0.12); padding: 2px 4px; border-radius: 4px; }
  pre code { background: none; padding: 0; }
  blockquote {
    margin: 12px 0;
    padding: 8px 16px;
    border-left: 3px solid $border;
    opacity: 0.8;
  }
  h1, h2, h3, h4, h5, h6 { margin: 16px 0 8px; }
  p { margin: 0 0 8px; }
  ul, ol { margin: 8px 0; padding-left: 24px; }
  hr { border: none; border-top: 1px solid $border; margin: 16px 0; }
</style>
</head>
<body>
$body
</body>
</html>
''',
      textStyle: NexusTypography.bodyMd.copyWith(height: 1.6),
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) return true;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      },
    );
  }
}

/// A text-style link with a leading icon that opens in the external browser.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
