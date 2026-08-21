import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/zhihu_models.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/zhihu_ui.dart';

/// Opens the answer-comments browser as a modal overlay (shadcn dialog
/// layer, same pattern as the AI-chat settings dialog).
///
/// [commentCount] is the count the answer card carried; it heads the
/// dialog until the first page reports the server-side total.
void zhihuShowCommentsDialog(
  BuildContext context, {
  required String answerId,
  required int commentCount,
}) {
  showOverlay(
    context,
    DialogConfiguration(
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
      builder: (context) => ZhihuCommentsDialog(
        answerId: answerId,
        commentCount: commentCount,
      ),
    ),
  );
}

/// Modal browser for the comments below one answer: top-level comments
/// page by page (auto-load near the end plus a manual button), each
/// comment's replies expand in place with their own pagination.
///
/// The first page of a comment's replies usually arrives embedded in the
/// `root_comments` payload and renders without a request; further pages
/// load from the replies endpoint.
class ZhihuCommentsDialog extends StatefulWidget {
  const ZhihuCommentsDialog({
    super.key,
    required this.answerId,
    required this.commentCount,
  });

  final String answerId;
  final int commentCount;

  @override
  State<ZhihuCommentsDialog> createState() => _ZhihuCommentsDialogState();
}

class _ZhihuCommentsDialogState extends State<ZhihuCommentsDialog> {
  final ZhihuService _service = ZhihuService();
  final ScrollController _scrollController = ScrollController();

  final List<ZhihuComment> _comments = [];
  bool _loadingFirst = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// Server-reported total, shown in the header once the first page lands.
  int _total = 0;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state (mirrors the question page's guard).
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
    if (position.maxScrollExtent - position.pixels < 200) {
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
      final page = await _service.fetchAnswerComments(widget.answerId);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.comments);
        _hasMore = page.hasMore;
        if (page.total > 0) _total = page.total;
        _offset = page.comments.length;
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
      final page = await _service.fetchAnswerComments(
        widget.answerId,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.comments);
        _hasMore = page.hasMore;
        _offset += page.comments.length;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      zhihuShowToast(context, '加载更多评论失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModalContainer(
      filled: true,
      borderRadius: theme.borderRadiusLg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Container(height: 1, color: theme.colorScheme.border),
            Flexible(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total > 0 ? _total : widget.commentCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            LucideIcons.messageCircle,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const Gap(6),
          Text(
            total > 0 ? '评论 $total' : '评论',
            style: theme.typography.small.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 15),
            size: ButtonSize.small,
            onPressed: () => closeOverlay(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingFirst) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(size: 18)),
      );
    }
    if (_error != null && _comments.isEmpty) {
      return SizedBox(
        height: 220,
        child: ZhihuEmptyState(
          icon: LucideIcons.cloudOff,
          title: '评论加载失败',
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
        ),
      );
    }
    if (_comments.isEmpty) {
      return const SizedBox(
        height: 180,
        child: ZhihuEmptyState(
          icon: LucideIcons.messageSquare,
          title: '暂无评论',
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _comments.length + 1,
      itemBuilder: (context, index) {
        if (index < _comments.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CommentTile(comment: _comments[index]),
          );
        }
        return _buildFooter(context);
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(size: 14)),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Button.outline(
            leading: const Icon(LucideIcons.chevronDown, size: 14),
            style: const ButtonStyle.outline(
              size: ButtonSize.small,
              density: ButtonDensity.dense,
            ),
            onPressed: _loadMore,
            child: const Text('加载更多评论'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

/// One top-level comment with an inline, lazily-loaded replies section.
class _CommentTile extends StatefulWidget {
  const _CommentTile({required this.comment});

  final ZhihuComment comment;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  final ZhihuService _service = ZhihuService();

  late final List<ZhihuComment> _replies;
  bool _expanded = false;
  bool _loadingReplies = false;
  late bool _hasMoreReplies;
  String? _repliesError;
  late int _offset;

  @override
  void initState() {
    super.initState();
    _replies = List.of(widget.comment.replies);
    _hasMoreReplies =
        widget.comment.replyCount > widget.comment.replies.length;
    _offset = widget.comment.replies.length;
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded &&
        _replies.isEmpty &&
        widget.comment.replyCount > 0 &&
        _repliesError == null) {
      _loadReplies();
    }
  }

  Future<void> _loadReplies() async {
    if (_loadingReplies) return;
    setState(() {
      _loadingReplies = true;
      _repliesError = null;
    });
    try {
      final page = await _service.fetchCommentReplies(
        widget.comment.id,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _replies.addAll(page.comments);
        _hasMoreReplies = page.hasMore;
        _offset += page.comments.length;
        _loadingReplies = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _repliesError = e.toString();
        _loadingReplies = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ZhihuAvatar(
          imageUrl: comment.authorAvatarUrl,
          name: comment.authorName,
          size: 22,
        ),
        const Gap(8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuthorRow(context, comment),
              // Rich text (image stickers, pasted HTML) renders natively,
              // same pipeline as answer bodies.
              if (comment.contentHtml.isNotEmpty) ...[
                const Gap(2),
                HtmlWidget(
                  comment.contentHtml,
                  textStyle: theme.typography.small.copyWith(height: 1.5),
                  onTapUrl: zhihuOpenInBrowser,
                ),
              ],
              const Gap(4),
              _buildActionRow(context, comment),
              if (_expanded) _buildReplies(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthorRow(BuildContext context, ZhihuComment comment) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            comment.authorName.isEmpty ? '匿名用户' : comment.authorName,
            style: theme.typography.small.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (comment.isContentAuthor) ...[
          const Gap(4),
          ZhihuTag(
            '作者',
            foreground: theme.colorScheme.primary,
            background: theme.colorScheme.primary.withValues(alpha: 0.1),
          ),
        ],
        if (comment.createdAtMs > 0) ...[
          const Gap(8),
          Text(
            DateFormat('yyyy-MM-dd HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(comment.createdAtMs),
            ),
            style: theme.typography.xSmall.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow(BuildContext context, ZhihuComment comment) {
    return Row(
      children: [
        if (comment.voteCount > 0) ...[
          ZhihuMetric(
            icon: LucideIcons.thumbsUp,
            label: '${comment.voteCount}',
          ),
          const Gap(10),
        ],
        if (comment.replyCount > 0)
          Button.ghost(
            leading: Icon(
              _expanded
                  ? LucideIcons.chevronUp
                  : LucideIcons.cornerDownRight,
              size: 12,
            ),
            style: const ButtonStyle.ghost(
              size: ButtonSize.small,
              density: ButtonDensity.dense,
            ),
            onPressed: _toggleExpanded,
            child: Text(
              _expanded ? '收起回复' : '查看 ${comment.replyCount} 条回复',
              style: Theme.of(
                context,
              ).typography.xSmall.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  Widget _buildReplies(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in _replies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReplyTile(reply: reply),
            ),
          if (_loadingReplies)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(child: CircularProgressIndicator(size: 14)),
            )
          else if (_repliesError != null)
            Row(
              children: [
                Flexible(
                  child: Text(
                    '回复加载失败：$_repliesError',
                    style: theme.typography.xSmall.copyWith(
                      color: theme.colorScheme.destructive,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Button.ghost(
                  leading: const Icon(LucideIcons.refreshCw, size: 12),
                  style: const ButtonStyle.ghost(
                    size: ButtonSize.small,
                    density: ButtonDensity.dense,
                  ),
                  onPressed: _loadReplies,
                  child: Text(
                    '重试',
                    style: theme.typography.xSmall,
                  ),
                ),
              ],
            )
          else if (_hasMoreReplies)
            Button.ghost(
              leading: const Icon(LucideIcons.chevronDown, size: 12),
              style: const ButtonStyle.ghost(
                size: ButtonSize.small,
                density: ButtonDensity.dense,
              ),
              onPressed: _loadReplies,
              child: Text(
                '加载更多回复',
                style: theme.typography.xSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// One reply below a comment; renders the「回复 @作者」chain when the
/// payload carried a [ZhihuComment.replyTo] target.
class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply});

  final ZhihuComment reply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ZhihuAvatar(
          imageUrl: reply.authorAvatarUrl,
          name: reply.authorName,
          size: 16,
        ),
        const Gap(6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      reply.authorName.isEmpty
                          ? '匿名用户'
                          : reply.authorName,
                      style: theme.typography.xSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (reply.isContentAuthor) ...[
                    const Gap(4),
                    ZhihuTag(
                      '作者',
                      foreground: theme.colorScheme.primary,
                      background: theme.colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                    ),
                  ],
                  if (reply.replyTo != null &&
                      reply.replyTo!.authorName.isNotEmpty) ...[
                    const Gap(4),
                    Flexible(
                      child: Text(
                        '回复 ${reply.replyTo!.authorName}',
                        style: theme.typography.xSmall.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const Gap(1),
              if (reply.contentHtml.isNotEmpty)
                HtmlWidget(
                  reply.contentHtml,
                  textStyle: theme.typography.xSmall.copyWith(height: 1.5),
                  onTapUrl: zhihuOpenInBrowser,
                ),
              if (reply.voteCount > 0) ...[
                const Gap(2),
                ZhihuMetric(
                  icon: LucideIcons.thumbsUp,
                  label: '${reply.voteCount}',
                  iconSize: 11,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
