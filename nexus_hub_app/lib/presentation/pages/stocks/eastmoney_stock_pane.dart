import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/eastmoney_stock_model.dart';
import '../../../data/services/eastmoney_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_input.dart';
import 'stock_charts.dart';

/// Chart period selector values.
enum _ChartRange { intraday, fiveDay, dailyK, weeklyK, monthlyK }

/// Eastmoney-backed trading view: watchlist on the left, chart in the middle,
/// quote details on the right (东方财富数据源).
class EastmoneyStockPane extends StatefulWidget {
  const EastmoneyStockPane({super.key});

  @override
  State<EastmoneyStockPane> createState() => _EastmoneyStockPaneState();
}

class _EastmoneyStockPaneState extends State<EastmoneyStockPane> {
  final _service = EastmoneyService();

  List<String> _secids = [];
  Map<String, StockQuote> _quotes = {};
  String? _selectedSecid;

  StockCategory _category = StockCategory.all;
  _ChartRange _range = _ChartRange.intraday;

  TrendData? _trend;
  List<KlineBar> _klines = [];
  bool _loadingChart = false;
  String? _listError;
  String? _chartError;

  Timer? _quoteTimer;
  Timer? _chartTimer;
  bool _disposed = false;

  bool get _rangeIsIntraday =>
      _range == _ChartRange.intraday || _range == _ChartRange.fiveDay;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _secids = await _service.loadWatchlist();
    if (_disposed) return;
    setState(() {});
    await _refreshQuotes(selectFirst: true);
    _startTimers();
    await _loadChart();
  }

  void _startTimers() {
    _quoteTimer?.cancel();
    _quoteTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshQuotes(),
    );
    _chartTimer?.cancel();
    _chartTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_rangeIsIntraday) _loadChart(silent: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQuotes({bool selectFirst = false}) async {
    try {
      final quotes = await _service.fetchQuotes(_secids);
      if (_disposed || !mounted) return;
      setState(() {
        _quotes = quotes;
        _listError = null;
        if (selectFirst) {
          _selectedSecid ??= _secids
              .where((s) => quotes.containsKey(s))
              .firstOrNull;
        }
      });
    } catch (_) {
      if (_disposed || !mounted) return;
      setState(() => _listError = '行情加载失败，请检查网络');
    }
  }

  Future<void> _loadChart({bool silent = false}) async {
    final secid = _selectedSecid;
    if (secid == null) return;

    if (!silent) setState(() => _loadingChart = true);
    try {
      if (_rangeIsIntraday) {
        final trend = await _service.fetchTrends(
          secid,
          ndays: _range == _ChartRange.intraday ? 1 : 5,
        );
        if (_disposed || secid != _selectedSecid) return;
        if (!mounted) return;
        setState(() {
          _trend = trend;
          _klines = [];
          _chartError = null;
          _loadingChart = false;
        });
      } else {
        final klt = switch (_range) {
          _ChartRange.dailyK => 101,
          _ChartRange.weeklyK => 102,
          _ => 103,
        };
        final klines = await _service.fetchKlines(secid, klt: klt);
        if (_disposed || secid != _selectedSecid) return;
        if (!mounted) return;
        setState(() {
          _klines = klines;
          _trend = null;
          _chartError = null;
          _loadingChart = false;
        });
      }
    } catch (_) {
      if (_disposed || !mounted) return;
      setState(() {
        _chartError = '图表数据加载失败';
        _loadingChart = false;
      });
    }
  }

  void _select(String secid) {
    if (secid == _selectedSecid) return;
    setState(() {
      _selectedSecid = secid;
      _trend = null;
      _klines = [];
      _loadingChart = true;
    });
    _loadChart();
  }

  Future<void> _addSecid(String secid) async {
    if (_secids.contains(secid)) return;
    setState(() => _secids = [..._secids, secid]);
    await _service.saveWatchlist(_secids);
    await _refreshQuotes();
  }

  Future<void> _removeSecid(String secid) async {
    setState(() {
      _secids = _secids.where((s) => s != secid).toList();
      if (_selectedSecid == secid) _selectedSecid = _secids.firstOrNull;
    });
    await _service.saveWatchlist(_secids);
    await _refreshQuotes();
    if (_selectedSecid != null) await _loadChart();
  }

  void _openSearchDialog() {
    showOverlay<void>(
      context,
      DialogConfiguration<void>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => _StockSearchDialog(
          service: _service,
          existing: _secids,
          onAdd: (secid) {
            closeOverlay<void>(ctx);
            _addSecid(secid);
          },
        ),
      ),
    );
  }

  List<_WatchlistRowData> _filteredSecids() {
    final visible = _category == StockCategory.all
        ? _secids
        : _secids
              .where((s) => categoryOfSecid(s) == _category)
              .toList(growable: false);
    return visible
        .map(
          (s) => _WatchlistRowData(
            secid: s,
            quote: _quotes[s] ?? StockQuote.fromSecid(s),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedQuote = _selectedSecid != null
        ? _quotes[_selectedSecid]
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showDetail = width >= 1080;
        final showWatchlist = width >= 760;

        final chartPanel = _ChartPanel(
          secid: _selectedSecid,
          quote: selectedQuote,
          range: _range,
          trend: _trend,
          klines: _klines,
          isLoading: _loadingChart,
          error: _chartError,
          colorScheme: colorScheme,
          onRangeChanged: (range) {
            setState(() => _range = range);
            _loadChart();
          },
        );

        final watchlistPanel = _WatchlistPanel(
          secids: _filteredSecids(),
          selectedSecid: _selectedSecid,
          category: _category,
          isLoading: _quotes.isEmpty && _listError == null,
          error: _listError,
          colorScheme: colorScheme,
          onCategoryChanged: (c) => setState(() => _category = c),
          onSelect: _select,
          onRemove: _removeSecid,
          onAdd: _openSearchDialog,
        );

        final detailPanel = _DetailPanel(
          secid: _selectedSecid,
          quote: selectedQuote,
          colorScheme: colorScheme,
        );

        if (!showWatchlist) {
          return chartPanel;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 280, child: watchlistPanel),
            _verticalDivider(colorScheme),
            Expanded(child: chartPanel),
            if (showDetail) ...[
              _verticalDivider(colorScheme),
              SizedBox(width: 300, child: detailPanel),
            ],
          ],
        );
      },
    );
  }

  Widget _verticalDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: NexusSpacing.sm),
      color: colorScheme.border.withValues(alpha: 0.5),
    );
  }
}

// ---------------------------------------------------------------- watchlist

class _WatchlistRowData {
  const _WatchlistRowData({required this.secid, required this.quote});

  final String secid;
  final StockQuote quote;
}

class _WatchlistPanel extends StatelessWidget {
  const _WatchlistPanel({
    required this.secids,
    required this.selectedSecid,
    required this.category,
    required this.isLoading,
    required this.error,
    required this.colorScheme,
    required this.onCategoryChanged,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
  });

  final List<_WatchlistRowData> secids;
  final String? selectedSecid;
  final StockCategory category;
  final bool isLoading;
  final String? error;
  final ColorScheme colorScheme;
  final ValueChanged<StockCategory> onCategoryChanged;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorScheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: NexusSpacing.sm),
          _buildCategoryChips(),
          const SizedBox(height: NexusSpacing.xs),
          _buildColumnHeader(),
          Expanded(child: _buildList(secids)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.md,
        NexusSpacing.md,
        NexusSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Text('自选列表', style: NexusTypography.headlineSm),
          const Spacer(),
          IconButton.ghost(
            onPressed: onAdd,
            icon: Icon(
              LucideIcons.plus,
              size: 18,
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final chips = {
      StockCategory.all: '全部',
      StockCategory.us: '美股',
      StockCategory.cn: '沪深',
      StockCategory.indices: '指数',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      child: Wrap(
        spacing: NexusSpacing.xs,
        children: chips.entries
            .map(
              (entry) => _CategoryChip(
                label: entry.value,
                isSelected: category == entry.key,
                colorScheme: colorScheme,
                onTap: () => onCategoryChanged(entry.key),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildColumnHeader() {
    final style = NexusTypography.labelSm.copyWith(
      color: colorScheme.mutedForeground,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('名称/代码', style: style, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '最新价',
              style: style,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '涨跌幅',
              style: style,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<_WatchlistRowData> rows) {
    if (isLoading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Text(
          error!,
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '暂无自选，点击 + 添加',
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final isSelected = row.secid == selectedSecid;
        return GestureDetector(
          onTap: () => onSelect(row.secid),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.sm + 2,
            ),
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              row.quote.name,
                              style: NexusTypography.labelMd.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: NexusSpacing.xs),
                            GestureDetector(
                              onTap: () => onRemove(row.secid),
                              child: Icon(
                                LucideIcons.x,
                                size: 12,
                                color: colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        row.quote.code,
                        style: NexusTypography.labelSm.copyWith(
                          color: colorScheme.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _formatPrice(row.quote.latestPrice),
                    style: NexusTypography.labelMd,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _formatPercent(row.quote.changePercent),
                    style: NexusTypography.labelMd.copyWith(
                      color: _changeColor(row.quote),
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _changeColor(StockQuote quote) {
    if (quote.isUp) return NexusColors.stockUp;
    if (quote.isDown) return NexusColors.stockDown;
    return colorScheme.mutedForeground;
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm + 2,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.mutedForeground,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- chart

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.secid,
    required this.quote,
    required this.range,
    required this.trend,
    required this.klines,
    required this.isLoading,
    required this.error,
    required this.colorScheme,
    required this.onRangeChanged,
  });

  final String? secid;
  final StockQuote? quote;
  final _ChartRange range;
  final TrendData? trend;
  final List<KlineBar> klines;
  final bool isLoading;
  final String? error;
  final ColorScheme colorScheme;
  final ValueChanged<_ChartRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorScheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: NexusSpacing.xs),
          _buildRangeSelector(),
          const SizedBox(height: NexusSpacing.sm),
          Expanded(child: _buildChartArea()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final changeColor = _quoteColor(quote);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.md,
        NexusSpacing.md,
        NexusSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (quote != null) ...[
            Text(
              quote!.name,
              style: NexusTypography.headlineSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              quote!.code,
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(width: NexusSpacing.lg),
            Text(
              _formatPrice(quote!.latestPrice),
              style: NexusTypography.headlineLg.copyWith(
                color: changeColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _signed(quote!.change),
                  style: NexusTypography.labelMd.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatPercent(quote!.changePercent),
                  style: NexusTypography.labelMd.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else
            Text(secid ?? '请选择自选', style: NexusTypography.headlineSm),
          const Spacer(),
          if (quote != null && quote!.updateTimeMs > 0)
            Text(
              _formatUpdateTime(quote!.updateTimeMs),
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    const labels = {
      _ChartRange.intraday: '分时',
      _ChartRange.fiveDay: '5日',
      _ChartRange.dailyK: '日K',
      _ChartRange.weeklyK: '周K',
      _ChartRange.monthlyK: '月K',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      child: Wrap(
        spacing: NexusSpacing.xs,
        children: labels.entries
            .map(
              (entry) => _CategoryChip(
                label: entry.value,
                isSelected: range == entry.key,
                colorScheme: colorScheme,
                onTap: () => onRangeChanged(entry.key),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildChartArea() {
    if (secid == null) {
      return Center(
        child: Text(
          '在左侧自选列表中选择一只标的',
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }
    if (isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Text(
          error!,
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }

    final intraday =
        range == _ChartRange.intraday || range == _ChartRange.fiveDay;
    final chartColors = StockChartColors(
      label: colorScheme.mutedForeground,
      grid: colorScheme.border.withValues(alpha: 0.35),
      priceLine: const Color(0xFF3B82F6),
      avgLine: const Color(0xFFF59E0B),
      fill: const Color(0xFF3B82F6).withValues(alpha: 0.12),
    );

    Widget chart;
    if (intraday && trend != null && trend!.points.isNotEmpty) {
      chart = CustomPaint(
        size: Size.infinite,
        painter: IntradayTrendPainter(
          points: trend!.points,
          preClose: trend!.preClose,
          colors: chartColors,
        ),
      );
    } else if (!intraday && klines.isNotEmpty) {
      chart = CustomPaint(
        size: Size.infinite,
        painter: CandlestickPainter(bars: klines, colors: chartColors),
      );
    } else {
      return Center(
        child: Text(
          '暂无图表数据',
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, NexusSpacing.sm),
      child: chart,
    );
  }

  Color _quoteColor(StockQuote? quote) {
    if (quote == null) return colorScheme.mutedForeground;
    if (quote.isUp) return NexusColors.stockUp;
    if (quote.isDown) return NexusColors.stockDown;
    return colorScheme.mutedForeground;
  }
}

// ------------------------------------------------------------------ detail

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.secid,
    required this.quote,
    required this.colorScheme,
  });

  final String? secid;
  final StockQuote? quote;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (quote == null) {
      return Container(
        color: colorScheme.card,
        padding: const EdgeInsets.all(NexusSpacing.md),
        child: Text(
          '暂无行情数据',
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }

    final q = quote!;
    return Container(
      color: colorScheme.card,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.name,
              style: NexusTypography.headlineSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              '${q.code} · 东方财富',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            _fieldGrid([
              ('今开', _priceOrDash(q.open)),
              ('最高', _priceOrDash(q.high)),
              ('最低', _priceOrDash(q.low)),
              ('昨收', _priceOrDash(q.prevClose)),
              ('成交量', formatCompactNumber(q.volume)),
              ('成交额', formatCompactNumber(q.amount)),
              ('振幅', q.amplitude == null ? '-' : '${q.amplitude}%'),
              ('换手率', q.turnoverRate == null ? '-' : '${q.turnoverRate}%'),
              ('量比', q.volumeRatio?.toString() ?? '-'),
              ('市盈率(动)', q.peRatio?.toString() ?? '-'),
              ('流通市值', formatCompactNumber(q.floatMarketCap)),
              ('总市值', formatCompactNumber(q.totalMarketCap)),
            ]),
            const SizedBox(height: NexusSpacing.md),
            if (q.updateTimeMs > 0)
              Text(
                '更新于 ${_formatUpdateTime(q.updateTimeMs)}',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _priceOrDash(double? v) => v == null ? '-' : _formatPrice(v);

  Widget _fieldGrid(List<(String, String)> fields) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
          child: Row(
            children: [
              Expanded(child: _fieldCell(left.$1, left.$2)),
              Expanded(child: _fieldCell(right?.$1 ?? '', right?.$2 ?? '')),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _fieldCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.mutedForeground,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ dialog

class _StockSearchDialog extends StatefulWidget {
  const _StockSearchDialog({
    required this.service,
    required this.existing,
    required this.onAdd,
  });

  final EastmoneyService service;
  final List<String> existing;
  final ValueChanged<String> onAdd;

  @override
  State<_StockSearchDialog> createState() => _StockSearchDialogState();
}

class _StockSearchDialogState extends State<_StockSearchDialog> {
  final _controller = TextEditingController();
  List<StockSuggest> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.service.search(input);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败，请重试';
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('添加自选', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NexusInput(
              controller: _controller,
              hintText: '输入代码 / 名称 / 拼音，如 600519、NVDA',
              autofocus: true,
              onSubmitted: (_) => _search(),
              suffixIcon: IconButton.ghost(
                onPressed: _search,
                icon: const Icon(LucideIcons.search, size: 16),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(NexusSpacing.md),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_error != null)
              Text(
                _error!,
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.stockDown,
                ),
              )
            else if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(NexusSpacing.md),
                child: Text(
                  '输入关键词后回车搜索',
                  style: NexusTypography.bodyMd.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final added = widget.existing.contains(item.secid);
                    return GestureDetector(
                      onTap: added ? null : () => widget.onAdd(item.secid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexusSpacing.sm,
                          vertical: NexusSpacing.sm,
                        ),
                        color: added
                            ? Theme.of(
                                context,
                              ).colorScheme.muted.withValues(alpha: 0.3)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: NexusTypography.labelMd.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${item.code} · ${item.marketName}',
                              style: NexusTypography.labelSm.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.mutedForeground,
                              ),
                            ),
                            const SizedBox(width: NexusSpacing.sm),
                            Icon(
                              added ? LucideIcons.check : LucideIcons.plus,
                              size: 14,
                              color: added
                                  ? NexusColors.stockUp
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        Button.text(
          onPressed: () => closeOverlay<void>(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- helpers

String _formatPrice(double v) {
  if (v == 0) return '-';
  if (v.abs() >= 10000) {
    final parts = v.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buf.write(',');
      buf.write(parts[i]);
    }
    return buf.toString();
  }
  if (v.abs() >= 100) return v.toStringAsFixed(2);
  return v.toStringAsFixed(v % 1 == 0 ? 2 : 3);
}

String _formatPercent(double pct) {
  final prefix = pct > 0 ? '+' : '';
  return '$prefix${pct.toStringAsFixed(2)}%';
}

String _signed(double v) {
  final prefix = v > 0 ? '+' : '';
  return '$prefix${v.toStringAsFixed(2)}';
}

String _formatUpdateTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.month.toString().padLeft(2, '0')}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}
