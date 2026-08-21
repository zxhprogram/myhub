import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/zhihu_detail_pane.dart';
import '../../components/zhihu_ui.dart';

/// Question detail: the hot-list entry as header, followed by its answers
/// loaded page by page.
///
/// Answer bodies are Zhihu rich text (HTML) and are rendered natively with
/// `flutter_widget_from_html` — no WebView is involved, per the sub-app's
/// requirement. Links inside the content open in the system browser.
///
/// [featuredAnswer] pins one answer above the loaded list — used when the
/// page is opened from a recommend-feed entry, whose answer shows first
/// while the rest of the question's answers load below it; answers with
/// the same id arriving from the API are skipped so it never shows twice.
///
/// With [pane] the page renders inside a [ZhihuDetailPane] without its own
/// page chrome, so it can be embedded as the right-hand content of the
/// sub-app's wide two-column layout; standalone (narrow) mode wraps the
/// same pane in a [ZhihuShadcnHost] with a back affordance.
class ZhihuQuestionPage extends StatefulWidget {
  const ZhihuQuestionPage({
    super.key,
    required this.item,
    this.featuredAnswer,
    this.pane = false,
    this.onBack,
  });

  /// The hot-list entry this page was opened from; provides the title and
  /// stats while the answers download.
  final ZhihuHotItem item;

  /// Answer to pin above the loaded list, e.g. the recommend-feed entry
  /// the user tapped; null for the plain hot-list flow.
  final ZhihuAnswer? featuredAnswer;

  /// Renders as an embedded pane when true.
  final bool pane;

  /// Shown in the pane header's back button in pane mode (e.g. clearing the
  /// wide layout's selection). Null hides the back affordance.
  final VoidCallback? onBack;

  @override
  State<ZhihuQuestionPage> createState() => _ZhihuQuestionPageState();
}

class _ZhihuQuestionPageState extends State<ZhihuQuestionPage> {
  final ZhihuService _service = ZhihuService();
  final ScrollController _scrollController = ScrollController();

  final List<ZhihuAnswer> _answers = [];
  bool _loadingFirst = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// Monotonic request counter; completions of superseded loads (pull to
  /// refresh while a page is in flight) never update the state.
  int _requestSeq = 0;

  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Auto-loads the next page when the viewport approaches the end.
  void _onScroll() {
    if (!_hasMore || _loadingMore || _loadingFirst || _error != null) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    final seq = ++_requestSeq;
    setState(() {
      _loadingFirst = true;
      _error = null;
    });
    try {
      final page = await _service.fetchQuestionAnswers(widget.item.id);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _answers
          ..clear()
          ..addAll(page.answers);
        _hasMore = page.hasMore;
        _offset = page.answers.length;
        _loadingFirst = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e.toString();
        _loadingFirst = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchQuestionAnswers(
        widget.item.id,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _answers.addAll(page.answers);
        _hasMore = page.hasMore;
        _offset += page.answers.length;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _answers.isEmpty ? e.toString() : _error;
        _loadingMore = false;
      });
      // A failed append keeps earlier answers visible; surface the error
      // as a transient toast instead of replacing the page.
      if (mounted && _answers.isNotEmpty) {
        zhihuShowToast(context, '加载更多失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pane) {
      return _buildPane(context);
    }
    return ZhihuShadcnHost(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: theme.colorScheme.background,
          child: SafeArea(child: _buildPane(context)),
        );
      },
    );
  }

  Widget _buildPane(BuildContext context) {
    return ZhihuDetailPane(
      title: widget.item.title,
      subtitle: widget.item.answerCount > 0
          ? '${widget.item.answerCount} 回答'
          : null,
      onBack: widget.pane
          ? widget.onBack
          : () => Navigator.of(context).maybePop(),
      // The body is a self-scrolling answer list; the pane header stays
      // pinned while the list scrolls underneath it. Expand it to the
      // remaining pane height so the ListView gets a finite viewport.
      enableScroll: false,
      expandChild: true,
      actions: [
        IconButton.ghost(
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          size: ButtonSize.small,
          onPressed: _loadingFirst ? null : _loadFirst,
        ),
        IconButton.ghost(
          icon: const Icon(LucideIcons.externalLink, size: 15),
          size: ButtonSize.small,
          onPressed: () => zhihuOpenInBrowser(widget.item.webUrl),
        ),
      ],
      child: _buildBody(context),
    );
  }

  /// Answers in display order: the pinned featured answer first, then the
  /// loaded ones minus any duplicate of the featured answer.
  List<ZhihuAnswer> get _displayAnswers {
    final featured = widget.featuredAnswer;
    return [
      ?featured,
      for (final answer in _answers)
        if (answer.id != featured?.id) answer,
    ];
  }

  Widget _buildBody(BuildContext context) {
    final hasFeatured = widget.featuredAnswer != null;
    // Without a pinned answer the pane shows a full-area loading/error
    // state; with one it renders immediately and the remaining answers
    // surface through the list footer instead.
    if (_loadingFirst && !hasFeatured) {
      return const Center(child: CircularProgressIndicator(size: 18));
    }
    if (_error != null && _answers.isEmpty && !hasFeatured) {
      return ZhihuEmptyState(
        icon: LucideIcons.cloudOff,
        title: '加载失败',
        subtitle: _error,
        action: Button.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 14),
          style: const ButtonStyle.outline(
            size: ButtonSize.small,
            density: ButtonDensity.dense,
          ),
          onPressed: _loadFirst,
          child: const Text('重试'),
        ),
      );
    }
    final answers = _displayAnswers;
    return ListView.builder(
      controller: _scrollController,
      padding: ZhihuDense.pagePadding,
      itemCount: answers.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: ZhihuDense.listGap),
            child: _buildQuestionHeader(context),
          );
        }
        if (index <= answers.length) {
          return Padding(
            padding: const EdgeInsets.only(top: ZhihuDense.listGap),
            child: _AnswerCard(
              answer: answers[index - 1],
              featured: widget.featuredAnswer != null && index == 1,
            ),
          );
        }
        return _buildFooter(context);
      },
    );
  }

  Widget _buildQuestionHeader(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return OutlinedContainer(
      borderRadius: theme.borderRadiusMd,
      padding: ZhihuDense.readingPadding,
      backgroundColor: theme.colorScheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: theme.typography.base.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const Gap(6),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.detailText.isNotEmpty)
                ZhihuMetric(
                  icon: LucideIcons.flame,
                  label: item.detailText,
                  color: const Color(0xFFF56A00),
                ),
              if (item.answerCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.messageSquare,
                  label: '${item.answerCount} 回答',
                ),
              if (item.followerCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.eye,
                  label: '${item.followerCount} 关注',
                ),
              if (item.commentCount > 0)
                ZhihuMetric(
                  icon: LucideIcons.messageCircle,
                  label: '${item.commentCount} 评论',
                ),
            ],
          ),
          if (item.excerpt.isNotEmpty && item.excerpt != '[视频]') ...[
            const Gap(4),
            Text(
              item.excerpt,
              style: theme.typography.xSmall.copyWith(
                color: theme.colorScheme.mutedForeground,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingFirst) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(size: 16)),
      );
    }
    if (_error != null && _answers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Button.outline(
            leading: const Icon(LucideIcons.refreshCw, size: 14),
            style: const ButtonStyle.outline(
              size: ButtonSize.small,
              density: ButtonDensity.dense,
            ),
            onPressed: _loadFirst,
            child: Text('其他回答加载失败，重试'),
          ),
        ),
      );
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(size: 16)),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Button.outline(
            leading: const Icon(LucideIcons.chevronDown, size: 14),
            style: const ButtonStyle.outline(
              size: ButtonSize.small,
              density: ButtonDensity.dense,
            ),
            onPressed: _loadMore,
            child: const Text('加载更多回答'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '— 已经到底了 —',
          style: theme.typography.xSmall.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// A single answer card: author line, the rich-text body rendered natively
/// with [HtmlWidget], and a compact metrics footer. [featured] marks the
/// recommend-feed answer the page was opened from.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, this.featured = false});

  final ZhihuAnswer answer;

  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OutlinedContainer(
      borderRadius: theme.borderRadiusMd,
      padding: ZhihuDense.readingPadding,
      backgroundColor: scheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ZhihuAvatar(
                imageUrl: answer.authorAvatarUrl,
                name: answer.authorName,
                size: 22,
              ),
              const Gap(6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            answer.authorName.isEmpty
                                ? '匿名用户'
                                : answer.authorName,
                            style: theme.typography.small.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (answer.authorHeadline.isNotEmpty) ...[
                          const Gap(6),
                          Expanded(
                            child: Text(
                              answer.authorHeadline,
                              style: theme.typography.xSmall.copyWith(
                                color: scheme.mutedForeground,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (answer.updatedAtMs > 0) ...[
                      const Gap(1),
                      Text(
                        '发布于 ${DateFormat('yyyy-MM-dd HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(
                            answer.updatedAtMs,
                          ),
                        )}',
                        style: theme.typography.xSmall.copyWith(
                          color: scheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(8),
              if (featured) ...[
                ZhihuTag(
                  '推荐',
                  foreground: scheme.primary,
                  background: scheme.primary.withValues(alpha: 0.1),
                ),
                const Gap(4),
              ],
              SecondaryBadge(
                child: Text(
                  '${answer.voteupCount} 赞同',
                  style: theme.typography.xSmall,
                ),
              ),
            ],
          ),
          if (answer.contentHtml.isNotEmpty) ...[
            const Gap(8),
            HtmlWidget(
              answer.contentHtml,
              textStyle: theme.typography.small.copyWith(height: 1.65),
              onTapUrl: zhihuOpenInBrowser,
            ),
          ] else ...[
            const Gap(6),
            Text(
              '（该回答没有文本内容，可能在浏览器中查看）',
              style: theme.typography.xSmall.copyWith(
                color: scheme.mutedForeground,
              ),
            ),
          ],
          if (answer.commentCount > 0) ...[
            const Gap(6),
            ZhihuMetric(
              icon: LucideIcons.messageCircle,
              label: '${answer.commentCount} 条评论',
            ),
          ],
        ],
      ),
    );
  }
}
