import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';

/// Question detail: the hot-list entry as header, followed by its answers
/// loaded page by page.
///
/// Answer bodies are Zhihu rich text (HTML) and are rendered natively with
/// `flutter_widget_from_html` — no WebView is involved, per the sub-app's
/// requirement. Links inside the content open in the system browser.
class ZhihuQuestionPage extends StatefulWidget {
  const ZhihuQuestionPage({super.key, required this.item});

  /// The hot-list entry this page was opened from; provides the title and
  /// stats while the answers download.
  final ZhihuHotItem item;

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
      // as a transient snack bar instead of replacing the page.
      if (mounted && _answers.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('加载更多失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loadingFirst ? null : _loadFirst,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: () => zhihuOpenInBrowser(widget.item.webUrl),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingFirst) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null && _answers.isEmpty) {
      return NexusEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: NexusButton(label: '重试', icon: Icons.refresh, onPressed: _loadFirst),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(NexusSpacing.md),
      itemCount: _answers.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _buildQuestionHeader(context);
        if (index <= _answers.length) {
          return Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.sm),
            child: _AnswerCard(answer: _answers[index - 1]),
          );
        }
        return _buildFooter(context);
      },
    );
  }

  Widget _buildQuestionHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: NexusTypography.bodyLg.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.xs,
            children: [
              if (item.detailText.isNotEmpty) Text('热度 ${item.detailText}'),
              if (item.answerCount > 0) Text('${item.answerCount} 回答'),
              if (item.followerCount > 0) Text('${item.followerCount} 关注'),
            ],
          ),
          if (item.excerpt.isNotEmpty &&
              item.excerpt != '[视频]') ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              item.excerpt,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: NexusSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
        child: Center(
          child: NexusButton(
            label: '加载更多回答',
            icon: Icons.expand_more,
            variant: NexusButtonVariant.outlined,
            onPressed: _loadMore,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
      child: Center(
        child: Text(
          '— 已经到底了 —',
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// A single answer card: author, engagement metrics and the rich-text body
/// rendered natively with [HtmlWidget].
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final ZhihuAnswer answer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ZhihuAuthorAvatar(imageUrl: answer.authorAvatarUrl),
              const SizedBox(width: NexusSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      answer.authorName.isEmpty ? '匿名用户' : answer.authorName,
                      style: NexusTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (answer.authorHeadline.isNotEmpty)
                      Text(
                        answer.authorHeadline,
                        style: NexusTypography.labelSm.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.xs,
            children: [
              if (answer.voteupCount > 0)
                ZhihuMetricRow(icon: Icons.thumb_up_outlined, label: '${answer.voteupCount} 赞同'),
              if (answer.commentCount > 0)
                ZhihuMetricRow(icon: Icons.mode_comment_outlined, label: '${answer.commentCount} 评论'),
              if (answer.updatedAtMs > 0)
                ZhihuMetricRow(
                  icon: Icons.schedule,
                  label: DateFormat('MM-dd HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(answer.updatedAtMs),
                  ),
                ),
            ],
          ),
          if (answer.contentHtml.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.md),
            HtmlWidget(
              answer.contentHtml,
              textStyle: NexusTypography.bodyMd.copyWith(height: 1.6),
              onTapUrl: zhihuOpenInBrowser,
            ),
          ] else ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              '（该回答没有文本内容，可能在浏览器中查看）',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular 32x32 author avatar with a person placeholder on load errors.
class ZhihuAuthorAvatar extends StatelessWidget {
  const ZhihuAuthorAvatar({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipOval(
      child: SizedBox(
        width: 32,
        height: 32,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: colorScheme.surfaceContainerHigh,
            child: Icon(
              Icons.person_outline,
              size: 18,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class ZhihuMetricRow extends StatelessWidget {
  const ZhihuMetricRow({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(width: NexusSpacing.xs),
        Text(label, style: NexusTypography.labelSm),
      ],
    );
  }
}

/// Opens [url] in the system browser; used for links inside answer bodies
/// and the app bar action. Always returns true so [HtmlWidget] does not
/// attempt its own navigation.
Future<bool> zhihuOpenInBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return true;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
  return true;
}
