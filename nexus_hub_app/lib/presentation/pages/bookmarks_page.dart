import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/entities/reorder_update_entity.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/bookmark_model.dart';
import '../../data/models/collection_model.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_button.dart';
import '../components/nexus_category_select.dart';
import '../components/nexus_chip_input.dart';
import '../components/nexus_input.dart';
import '../states/bookmarks_state.dart';
import '../states/collections_state.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

enum BookmarkView { grid, list, icons }

class _BookmarksPageState extends State<BookmarksPage> {
  final _state = BookmarksState();
  final _collectionsState = CollectionsState();
  final _filter = signal<String>('All');
  final _view = signal<BookmarkView>(BookmarkView.grid);
  late final void Function() _disposeBookmarksErrorEffect;
  late final void Function() _disposeCollectionsErrorEffect;

  static const _categories = [
    'All',
    'Design',
    'Dev',
    'Articles',
    'Tools',
    'Inspiration',
  ];

  @override
  void initState() {
    super.initState();
    _state.load();
    _collectionsState.load();
    _disposeBookmarksErrorEffect = effect(() {
      final message = _state.error.value;
      if (message != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
    _disposeCollectionsErrorEffect = effect(() {
      final message = _collectionsState.error.value;
      if (message != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  void dispose() {
    _disposeBookmarksErrorEffect();
    _disposeCollectionsErrorEffect();
    super.dispose();
  }

  List<BookmarkModel> _visibleBookmarks(List<BookmarkModel> all) {
    if (_filter.value == 'All') return all;
    final lower = _filter.value.toLowerCase();
    return all
        .where(
          (b) =>
              b.category.toLowerCase() == lower ||
              b.tags.any((t) => t.toLowerCase() == lower),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.background,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            count: _state.bookmarks.value.length,
            view: _view.value,
            onViewChanged: (v) => _view.value = v,
            onAdd: () => _showAddDialog(context),
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FilterBar(
                        categories: _categories,
                        selected: _filter.value,
                        onSelect: (c) => _filter.value = c,
                      ),
                      const SizedBox(height: NexusSpacing.md),
                      Expanded(
                        child: Watch((_) {
                          if (_state.isLoading.value) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (_state.error.value != null) {
                            return Center(
                              child: Text(
                                'Error: ${_state.error.value}',
                                style: NexusTypography.bodyMd.copyWith(
                                  color: NexusColors.error,
                                ),
                              ),
                            );
                          }
                          final visible = _visibleBookmarks(
                            _state.bookmarks.value,
                          );
                          if (visible.isEmpty) {
                            return const _EmptyState();
                          }
                          return switch (_view.value) {
                            BookmarkView.grid => _BookmarkGrid(
                              bookmarks: visible,
                              onReorder: _reorderFromEntities,
                              collectionsState: _collectionsState,
                              bookmarksState: _state,
                              onEdit: (b) =>
                                  _showAddDialog(context, bookmark: b),
                              onDelete: (b) =>
                                  _confirmDeleteBookmark(context, b),
                            ),
                            BookmarkView.list => _BookmarkList(
                              bookmarks: visible,
                              onReorder: _onListReorder,
                              collectionsState: _collectionsState,
                              bookmarksState: _state,
                              onEdit: (b) =>
                                  _showAddDialog(context, bookmark: b),
                              onDelete: (b) =>
                                  _confirmDeleteBookmark(context, b),
                            ),
                            BookmarkView.icons => _BookmarkIconGrid(
                              bookmarks: visible,
                              onReorder: _reorderFromEntities,
                            ),
                          };
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NexusSpacing.xl),
                SizedBox(
                  width: 256,
                  child: _SecondaryPanel(
                    collectionsState: _collectionsState,
                    bookmarksState: _state,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _reorderFromEntities(List<ReorderUpdateEntity> updates) {
    for (final update in updates) {
      final visible = _visibleBookmarks(_state.bookmarks.value);
      final full = _state.bookmarks.value;
      final oldFiltered = update.oldIndex;
      final newFiltered = update.newIndex;
      if (oldFiltered < 0 ||
          oldFiltered >= visible.length ||
          newFiltered < 0 ||
          newFiltered >= visible.length) {
        continue;
      }
      final oldFull = full.indexOf(visible[oldFiltered]);
      var newFull = full.indexOf(visible[newFiltered]);
      if (oldFull == -1 || newFull == -1) continue;
      // Grid views report the final position; convert to ReorderableListView
      // insertion-index semantics expected by the state layer.
      if (newFiltered > oldFiltered) newFull++;
      _state.reorder(oldFull, newFull);
    }
  }

  void _onListReorder(int oldIndex, int newIndex) {
    final visible = _visibleBookmarks(_state.bookmarks.value);
    final full = _state.bookmarks.value;
    if (oldIndex < 0 ||
        oldIndex >= visible.length ||
        newIndex < 0 ||
        newIndex > visible.length) {
      return;
    }
    final oldFull = full.indexOf(visible[oldIndex]);
    final newFull = newIndex < visible.length
        ? full.indexOf(visible[newIndex])
        : full.length;
    if (oldFull == -1 || newFull == -1) return;
    _state.reorder(oldFull, newFull);
  }

  Future<void> _confirmDeleteBookmark(
    BuildContext context,
    BookmarkModel bookmark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
        title: Text('Delete Bookmark?', style: NexusTypography.headlineSm),
        content: Text(
          'Are you sure you want to delete "${bookmark.title}"?',
          style: NexusTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: NexusColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && bookmark.id != null) {
      await _state.delete(bookmark.id!);
    }
  }

  void _showAddDialog(BuildContext context, {BookmarkModel? bookmark}) {
    final categories = _state.bookmarks.value
        .map((b) => b.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    showDialog(
      context: context,
      builder: (context) => _AddBookmarkDialog(
        bookmark: bookmark,
        categories: categories,
        collectionsState: _collectionsState,
        bookmarksState: _state,
        onSave: (updated) async {
          if (bookmark == null) {
            await _state.add(updated);
          } else {
            await _state.update(updated);
          }
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.view,
    required this.onViewChanged,
    required this.onAdd,
  });

  final int count;
  final BookmarkView view;
  final ValueChanged<BookmarkView> onViewChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Bookmarks', style: NexusTypography.headlineXl),
                const SizedBox(width: NexusSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NexusColors.surfaceContainer,
                    borderRadius: NexusRadii.fullRadius,
                  ),
                  child: Text(
                    '$count',
                    style: NexusTypography.labelSm.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              'Manage and organize your saved links.',
              style: NexusTypography.bodyMd.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _ViewToggle(view: view, onChanged: onViewChanged),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(
              label: 'New Bookmark',
              icon: Icons.add,
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final BookmarkView view;
  final ValueChanged<BookmarkView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLowest,
        border: Border.all(color: NexusColors.outlineVariant),
        borderRadius: NexusRadii.lgRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(
            icon: Icons.grid_view,
            active: view == BookmarkView.grid,
            onTap: () => onChanged(BookmarkView.grid),
          ),
          _toggleButton(
            icon: Icons.view_list,
            active: view == BookmarkView.list,
            onTap: () => onChanged(BookmarkView.list),
          ),
          _toggleButton(
            icon: Icons.apps,
            active: view == BookmarkView.icons,
            onTap: () => onChanged(BookmarkView.icons),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? NexusColors.surfaceVariant : Colors.transparent,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.mdRadius,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: active
                ? NexusColors.onSurface
                : NexusColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: NexusSpacing.sm),
        itemBuilder: (context, index) {
          final category = categories[index];
          final active = category == selected;
          return Material(
            color: active
                ? NexusColors.primary
                : NexusColors.surfaceContainerLowest,
            borderRadius: NexusRadii.fullRadius,
            child: InkWell(
              onTap: () => onSelect(category),
              borderRadius: NexusRadii.fullRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: NexusRadii.fullRadius,
                  border: Border.all(
                    color: active
                        ? NexusColors.primary
                        : NexusColors.outlineVariant,
                  ),
                ),
                child: Text(
                  category,
                  style: NexusTypography.labelMd.copyWith(
                    color: active
                        ? NexusColors.onPrimary
                        : NexusColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BookmarkGrid extends StatefulWidget {
  const _BookmarkGrid({
    required this.bookmarks,
    required this.onReorder,
    required this.collectionsState,
    required this.bookmarksState,
    required this.onEdit,
    required this.onDelete,
  });

  final List<BookmarkModel> bookmarks;
  final void Function(List<ReorderUpdateEntity>) onReorder;
  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;
  final ValueChanged<BookmarkModel> onEdit;
  final ValueChanged<BookmarkModel> onDelete;

  @override
  State<_BookmarkGrid> createState() => _BookmarkGridState();
}

class _BookmarkGridState extends State<_BookmarkGrid> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        if (width < 560) {
          crossAxisCount = 1;
        } else if (width < 960) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 3;
        }
        return ReorderableBuilder(
          scrollController: _scrollController,
          onReorderPositions: widget.onReorder,
          builder: (children) {
            return GridView(
              controller: _scrollController,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: NexusSpacing.lg,
                mainAxisSpacing: NexusSpacing.lg,
                childAspectRatio: 0.82,
              ),
              children: children,
            );
          },
          children: widget.bookmarks
              .map(
                (b) => _BookmarkGridCard(
                  key: ValueKey('grid-${b.id}'),
                  bookmark: b,
                  collectionsState: widget.collectionsState,
                  bookmarksState: widget.bookmarksState,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _BookmarkGridCard extends StatefulWidget {
  const _BookmarkGridCard({
    super.key,
    required this.bookmark,
    required this.collectionsState,
    required this.bookmarksState,
    required this.onEdit,
    required this.onDelete,
  });

  final BookmarkModel bookmark;
  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;
  final ValueChanged<BookmarkModel> onEdit;
  final ValueChanged<BookmarkModel> onDelete;

  @override
  State<_BookmarkGridCard> createState() => _BookmarkGridCardState();
}

class _BookmarkGridCardState extends State<_BookmarkGridCard> {
  bool _hovered = false;
  bool _favorite = false;

  String get _domain {
    final uri = Uri.tryParse(widget.bookmark.url);
    return uri?.host ?? widget.bookmark.url;
  }

  String get _firstLetter =>
      widget.bookmark.title.isEmpty ? '?' : widget.bookmark.title[0];

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: NexusColors.surfaceContainerLowest,
          borderRadius: NexusRadii.xxlRadius,
          border: Border.all(
            color: _hovered
                ? NexusColors.outline
                : NexusColors.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: NexusColors.onSurface.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: NexusColors.onSurface.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: NexusColors.surfaceVariant,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(NexusRadii.xxl),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: NexusColors.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(NexusRadii.xxl),
                      ),
                      child: widget.bookmark.image.isNotEmpty
                          ? Image.network(
                              widget.bookmark.image,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) =>
                                  const _ImagePlaceholder(),
                            )
                          : const _ImagePlaceholder(),
                    ),
                  ),
                  if (_hovered)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        children: [
                          _HoverAction(
                            icon: Icons.folder_outlined,
                            onTap: () => _showAddToCollectionDialog(context),
                          ),
                          const SizedBox(width: 4),
                          _HoverAction(
                            icon: Icons.edit,
                            onTap: () => widget.onEdit(widget.bookmark),
                          ),
                          const SizedBox(width: 4),
                          _HoverAction(
                            icon: Icons.delete,
                            danger: true,
                            onTap: () => widget.onDelete(widget.bookmark),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NexusSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: NexusColors.surfaceContainer,
                          borderRadius: NexusRadii.smRadius,
                          border: Border.all(
                            color: NexusColors.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _firstLetter.toUpperCase(),
                          style: NexusTypography.labelSm.copyWith(
                            fontSize: 10,
                            color: NexusColors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bookmark.title,
                              style: NexusTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _domain,
                              style: NexusTypography.labelMd,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _favorite = !_favorite),
                        icon: Icon(
                          _favorite ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: _favorite
                              ? NexusColors.secondary
                              : NexusColors.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexusSpacing.xs),
                  Watch((_) {
                    final collections =
                        widget.collectionsState.collections.value;
                    final names = collections
                        .where(
                          (c) => widget.bookmark.collectionIds.contains(c.id),
                        )
                        .map((c) => c.name)
                        .toList();
                    if (names.isEmpty) return const SizedBox.shrink();
                    return Wrap(
                      spacing: NexusSpacing.xs,
                      runSpacing: NexusSpacing.xs,
                      children: names
                          .map((name) => NexusBadge(label: name))
                          .toList(),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToCollectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddToCollectionDialog(
        collectionsState: widget.collectionsState,
        bookmarksState: widget.bookmarksState,
        bookmark: widget.bookmark,
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language,
            size: 40,
            color: NexusColors.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 4),
          Text(
            'No preview',
            style: NexusTypography.labelSm.copyWith(
              color: NexusColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverAction extends StatelessWidget {
  const _HoverAction({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexusColors.surfaceContainerLowest.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: danger ? NexusColors.error : NexusColors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.onReorder,
    required this.collectionsState,
    required this.bookmarksState,
    required this.onEdit,
    required this.onDelete,
  });

  final List<BookmarkModel> bookmarks;
  final ReorderCallback onReorder;
  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;
  final ValueChanged<BookmarkModel> onEdit;
  final ValueChanged<BookmarkModel> onDelete;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: bookmarks.length,
      onReorder: onReorder,
      itemBuilder: (context, index) => _BookmarkListRow(
        key: ValueKey('list-${bookmarks[index].id}'),
        bookmark: bookmarks[index],
        collectionsState: collectionsState,
        bookmarksState: bookmarksState,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
  }
}

class _BookmarkListRow extends StatelessWidget {
  const _BookmarkListRow({
    super.key,
    required this.bookmark,
    required this.collectionsState,
    required this.bookmarksState,
    required this.onEdit,
    required this.onDelete,
  });

  final BookmarkModel bookmark;
  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;
  final ValueChanged<BookmarkModel> onEdit;
  final ValueChanged<BookmarkModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final domain = Uri.tryParse(bookmark.url)?.host ?? bookmark.url;
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLowest,
        borderRadius: NexusRadii.lgRadius,
        border: Border.all(
          color: NexusColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainer,
              borderRadius: NexusRadii.mdRadius,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.language, size: 20),
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookmark.title,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  domain,
                  style: NexusTypography.labelMd,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NexusSpacing.xs),
                Wrap(
                  spacing: NexusSpacing.xs,
                  runSpacing: NexusSpacing.xs,
                  children: [
                    NexusBadge(label: bookmark.category),
                    ..._collectionBadges(),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showAddToCollectionDialog(context),
            icon: const Icon(Icons.folder_outlined, size: 18),
          ),
          IconButton(
            onPressed: () => onEdit(bookmark),
            icon: const Icon(Icons.edit, size: 18),
          ),
          IconButton(
            onPressed: () => onDelete(bookmark),
            icon: Icon(Icons.delete, size: 18, color: NexusColors.error),
          ),
        ],
      ),
    );
  }

  List<Widget> _collectionBadges() {
    final names = collectionsState.collections.value
        .where((c) => bookmark.collectionIds.contains(c.id))
        .map((c) => c.name)
        .toList();
    return names.map((name) => NexusBadge(label: name)).toList();
  }

  void _showAddToCollectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddToCollectionDialog(
        collectionsState: collectionsState,
        bookmarksState: bookmarksState,
        bookmark: bookmark,
      ),
    );
  }
}

class _BookmarkIconGrid extends StatefulWidget {
  const _BookmarkIconGrid({required this.bookmarks, required this.onReorder});

  final List<BookmarkModel> bookmarks;
  final void Function(List<ReorderUpdateEntity>) onReorder;

  @override
  State<_BookmarkIconGrid> createState() => _BookmarkIconGridState();
}

class _BookmarkIconGridState extends State<_BookmarkIconGrid> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 400
            ? 3
            : width < 640
            ? 4
            : width < 900
            ? 5
            : 6;
        return ReorderableBuilder(
          scrollController: _scrollController,
          onReorderPositions: widget.onReorder,
          builder: (children) {
            return GridView(
              controller: _scrollController,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: NexusSpacing.sm,
                mainAxisSpacing: NexusSpacing.sm,
              ),
              children: children,
            );
          },
          children: widget.bookmarks
              .map(
                (b) => _BookmarkIconItem(
                  key: ValueKey('icon-${b.id}'),
                  bookmark: b,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _BookmarkIconItem extends StatefulWidget {
  const _BookmarkIconItem({super.key, required this.bookmark});

  final BookmarkModel bookmark;

  @override
  State<_BookmarkIconItem> createState() => _BookmarkIconItemState();
}

class _BookmarkIconItemState extends State<_BookmarkIconItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? NexusColors.surfaceContainerHighest
            : NexusColors.surfaceContainerLowest,
        borderRadius: NexusRadii.xlRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {},
          borderRadius: NexusRadii.xlRadius,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _hovered
                    ? NexusColors.outline
                    : NexusColors.outlineVariant.withValues(alpha: 0.4),
              ),
              borderRadius: NexusRadii.xlRadius,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FaviconAvatar(bookmark: widget.bookmark, size: 40),
                const SizedBox(height: NexusSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.bookmark.title,
                    style: NexusTypography.labelMd.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _domainOf(widget.bookmark.url),
                    style: NexusTypography.labelSm.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _domainOf(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host ?? url;
}

class _FaviconAvatar extends StatelessWidget {
  const _FaviconAvatar({required this.bookmark, required this.size});

  final BookmarkModel bookmark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final faviconUrl = bookmark.image.isNotEmpty
        ? _faviconFromImage(bookmark.image)
        : '';

    if (faviconUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: NexusRadii.mdRadius,
        child: Image.network(
          faviconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _FallbackAvatar(bookmark: bookmark, size: size),
        ),
      );
    }
    return _FallbackAvatar(bookmark: bookmark, size: size);
  }

  String _faviconFromImage(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return '';
    return uri.resolve('/favicon.ico').toString();
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar({required this.bookmark, required this.size});

  final BookmarkModel bookmark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = bookmark.title.isEmpty
        ? '?'
        : bookmark.title[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NexusColors.primaryContainer,
        borderRadius: NexusRadii.mdRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: NexusTypography.headlineSm.copyWith(
          color: NexusColors.onPrimaryContainer,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 64,
              color: NexusColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: NexusSpacing.md),
            Text('No bookmarks found', style: NexusTypography.headlineSm),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              'Try adjusting your filters or add a new bookmark.',
              style: NexusTypography.bodyMd.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryPanel extends StatelessWidget {
  const _SecondaryPanel({
    required this.collectionsState,
    required this.bookmarksState,
  });

  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LibrarySection(),
          const SizedBox(height: NexusSpacing.lg),
          _CollectionsSection(
            collectionsState: collectionsState,
            bookmarksState: bookmarksState,
          ),
          const SizedBox(height: NexusSpacing.lg),
          const _TagsSection(),
        ],
      ),
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection();

  static const _items = [
    (icon: Icons.grid_view, label: 'All Bookmarks', count: '128'),
    (icon: Icons.favorite, label: 'Favorites', count: '12'),
    (icon: Icons.history, label: 'Recent', count: '37'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('LIBRARY', style: NexusTypography.labelSm),
        ),
        const SizedBox(height: NexusSpacing.sm),
        ..._items.map(
          (item) => _SidebarItem(
            icon: item.icon,
            label: item.label,
            trailing: item.count,
            selected: item.label == 'All Bookmarks',
          ),
        ),
      ],
    );
  }
}

class _CollectionsSection extends StatelessWidget {
  const _CollectionsSection({
    required this.collectionsState,
    required this.bookmarksState,
  });

  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('COLLECTIONS', style: NexusTypography.labelSm),
              IconButton(
                icon: Icon(
                  Icons.add,
                  size: 16,
                  color: NexusColors.onSurfaceVariant,
                ),
                onPressed: () => _showManageCollectionsDialog(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: NexusSpacing.sm),
        Watch((_) {
          final selectedId = bookmarksState.selectedCollectionId.value;
          final collections = collectionsState.collections.value;
          return Column(
            children: [
              _SidebarItem(
                icon: Icons.folder_outlined,
                label: 'All Bookmarks',
                trailing: bookmarksState.bookmarks.value.length.toString(),
                selected: selectedId == null,
                onTap: () => bookmarksState.filterByCollection(null),
              ),
              ...collections.map((collection) {
                return FutureBuilder<int>(
                  key: ValueKey('collection-${collection.id}'),
                  future: collectionsState.countBookmarks(collection.id!),
                  builder: (context, snapshot) {
                    return _SidebarItem(
                      icon: Icons.folder_outlined,
                      label: collection.name,
                      trailing: (snapshot.data ?? 0).toString(),
                      selected: selectedId == collection.id,
                      onTap: () =>
                          bookmarksState.filterByCollection(collection.id),
                    );
                  },
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  void _showManageCollectionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          _ManageCollectionsDialog(collectionsState: collectionsState),
    );
  }
}

class _TagsSection extends StatelessWidget {
  const _TagsSection();

  static const _tags = [
    '#ui',
    '#ux',
    '#development',
    '#react',
    '#typography',
    '#architecture',
    '#news',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('TAGS', style: NexusTypography.labelSm),
        ),
        const SizedBox(height: NexusSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NexusColors.surfaceContainer,
                      borderRadius: NexusRadii.mdRadius,
                    ),
                    child: Text(
                      tag,
                      style: NexusTypography.labelSm.copyWith(
                        color: NexusColors.onSurface,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.trailing,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NexusColors.surfaceVariant : Colors.transparent,
      borderRadius: NexusRadii.lgRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.lgRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? NexusColors.onSurface
                    : NexusColors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected
                        ? NexusColors.onSurface
                        : NexusColors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(trailing, style: NexusTypography.labelSm),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageCollectionsDialog extends StatefulWidget {
  const _ManageCollectionsDialog({required this.collectionsState});

  final CollectionsState collectionsState;

  @override
  State<_ManageCollectionsDialog> createState() =>
      _ManageCollectionsDialogState();
}

class _ManageCollectionsDialogState extends State<_ManageCollectionsDialog> {
  final _name = TextEditingController();
  final _editingName = TextEditingController();
  int? _editingId;

  @override
  void dispose() {
    _name.dispose();
    _editingName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexusColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Text('Manage Collections', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 420,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NexusInput(
                        labelText: 'New collection',
                        controller: _name,
                        onSubmitted: (_) => _create(),
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    NexusButton(
                      label: 'Create',
                      icon: Icons.add,
                      onPressed: _create,
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.md),
                Watch((_) {
                  final sort = widget.collectionsState.sort.value;
                  return Wrap(
                    spacing: NexusSpacing.sm,
                    children: [
                      _SortChip(
                        label: 'Name A-Z',
                        active: sort == 'name_asc',
                        onTap: () =>
                            widget.collectionsState.setSort('name_asc'),
                      ),
                      _SortChip(
                        label: 'Name Z-A',
                        active: sort == 'name_desc',
                        onTap: () =>
                            widget.collectionsState.setSort('name_desc'),
                      ),
                      _SortChip(
                        label: 'Newest',
                        active: sort == 'created_desc',
                        onTap: () =>
                            widget.collectionsState.setSort('created_desc'),
                      ),
                      _SortChip(
                        label: 'Oldest',
                        active: sort == 'created_asc',
                        onTap: () =>
                            widget.collectionsState.setSort('created_asc'),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: NexusSpacing.md),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: Watch((_) {
                      final collections =
                          widget.collectionsState.collections.value;
                      if (collections.isEmpty) {
                        return Center(
                          child: Text(
                            'No collections yet',
                            style: NexusTypography.bodyMd.copyWith(
                              color: NexusColors.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: collections.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final collection = collections[index];
                          final isEditing = _editingId == collection.id;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: isEditing
                                ? NexusInput(
                                    labelText: 'Name',
                                    controller: _editingName,
                                    onSubmitted: (_) =>
                                        _saveEdit(collection.id!),
                                  )
                                : Text(
                                    collection.name,
                                    style: NexusTypography.bodyMd,
                                  ),
                            trailing: isEditing
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check, size: 18),
                                        onPressed: () =>
                                            _saveEdit(collection.id!),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () =>
                                            setState(() => _editingId = null),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: NexusColors.onSurfaceVariant,
                                        ),
                                        onPressed: () => _startEdit(collection),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          size: 18,
                                          color: NexusColors.error,
                                        ),
                                        onPressed: () =>
                                            _confirmDelete(context, collection),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
            Watch((_) {
              if (!widget.collectionsState.isLoading.value) {
                return const SizedBox.shrink();
              }
              return Container(
                color: NexusColors.background.withValues(alpha: 0.7),
                child: const Center(child: CircularProgressIndicator()),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _name.clear();
    await widget.collectionsState.create(name);
  }

  void _startEdit(CollectionModel collection) {
    setState(() {
      _editingId = collection.id;
      _editingName.text = collection.name;
    });
  }

  Future<void> _saveEdit(int id) async {
    final name = _editingName.text.trim();
    if (name.isEmpty) return;
    setState(() => _editingId = null);
    await widget.collectionsState.rename(id, name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CollectionModel collection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
        title: Text('Delete Collection?', style: NexusTypography.headlineSm),
        content: Text(
          'Are you sure you want to delete "${collection.name}"? Bookmarks will not be deleted.',
          style: NexusTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: NexusColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && collection.id != null) {
      await widget.collectionsState.delete(collection.id!);
    }
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? NexusColors.primaryContainer
          : NexusColors.surfaceContainer,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: active
                  ? NexusColors.onPrimaryContainer
                  : NexusColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddToCollectionDialog extends StatefulWidget {
  const _AddToCollectionDialog({
    required this.collectionsState,
    required this.bookmarksState,
    required this.bookmark,
  });

  final CollectionsState collectionsState;
  final BookmarksState bookmarksState;
  final BookmarkModel bookmark;

  @override
  State<_AddToCollectionDialog> createState() => _AddToCollectionDialogState();
}

class _AddToCollectionDialogState extends State<_AddToCollectionDialog> {
  late Set<int> _selectedIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<int>.from(widget.bookmark.collectionIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexusColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Text('Add to Collection', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 360,
        child: Watch((_) {
          final collections = widget.collectionsState.collections.value;
          if (collections.isEmpty) {
            return Center(
              child: Text(
                'No collections yet',
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final collection = collections[index];
              final selected = _selectedIds.contains(collection.id);
              return CheckboxListTile(
                value: selected,
                onChanged: _saving ? null : (_) => _toggle(collection.id!),
                title: Text(collection.name, style: NexusTypography.bodyMd),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: NexusColors.primary,
              );
            },
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        NexusButton(
          label: _saving ? 'Saving...' : 'Save',
          onPressed: _saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  final bookmarkId = widget.bookmark.id;
                  if (bookmarkId == null) {
                    navigator.pop();
                    return;
                  }
                  setState(() => _saving = true);
                  final original = Set<int>.from(widget.bookmark.collectionIds);
                  final toAdd = _selectedIds.difference(original).toList();
                  final toRemove = original.difference(_selectedIds).toList();

                  for (final collectionId in toAdd) {
                    await widget.collectionsState.addBookmarks(collectionId, [
                      bookmarkId,
                    ]);
                  }
                  for (final collectionId in toRemove) {
                    await widget.collectionsState.removeBookmarks(
                      collectionId,
                      [bookmarkId],
                    );
                  }
                  await widget.bookmarksState.load();
                  if (mounted) navigator.pop();
                },
        ),
      ],
    );
  }

  void _toggle(int collectionId) {
    setState(() {
      if (_selectedIds.contains(collectionId)) {
        _selectedIds.remove(collectionId);
      } else {
        _selectedIds.add(collectionId);
      }
    });
  }
}

class _AddBookmarkDialog extends StatefulWidget {
  const _AddBookmarkDialog({
    this.bookmark,
    required this.onSave,
    required this.categories,
    this.collectionsState,
    this.bookmarksState,
  });

  final BookmarkModel? bookmark;
  final ValueChanged<BookmarkModel> onSave;
  final List<String> categories;
  final CollectionsState? collectionsState;
  final BookmarksState? bookmarksState;

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _repo = BookmarkRepository();

  List<String> _tags = [];
  String _category = '';
  String _image = '';
  bool _fetching = false;
  bool _titleEdited = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final bookmark = widget.bookmark;
    if (bookmark != null) {
      _title.text = bookmark.title;
      _url.text = bookmark.url;
      _tags = List<String>.from(bookmark.tags);
      _category = bookmark.category;
      _image = bookmark.image;
      _titleEdited = true;
    }
    _title.addListener(() {
      if (_title.text.isNotEmpty) _titleEdited = true;
    });
    _url.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final url = _url.text.trim();
    _debounce?.cancel();
    final parsed = Uri.tryParse(url);
    if (url.isEmpty || parsed == null || !parsed.hasAbsolutePath) {
      setState(() {
        _fetching = false;
        _image = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _fetchPreview);
  }

  Future<void> _fetchPreview() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() => _fetching = true);
    try {
      final preview = await _repo.fetchPreview(url);
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _image = preview.image;
        if (!_titleEdited && preview.title.isNotEmpty) {
          _title.text = preview.title;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexusColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Text(
        widget.bookmark == null ? 'Add Bookmark' : 'Edit Bookmark',
        style: NexusTypography.headlineSm,
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(
                labelText: 'URL',
                controller: _url,
                suffixIcon: _fetching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: NexusSpacing.md),
              NexusInput(labelText: 'Title', controller: _title),
              const SizedBox(height: NexusSpacing.md),
              NexusChipInput(
                labelText: 'Tags',
                values: _tags,
                onChanged: (tags) => setState(() => _tags = tags),
              ),
              const SizedBox(height: NexusSpacing.md),
              NexusCategorySelect(
                labelText: 'Category',
                categories: widget.categories,
                onChanged: (value) => _category = value,
              ),
              if (_image.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.md),
                ClipRRect(
                  borderRadius: NexusRadii.mdRadius,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: Image.network(
                      _image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
              if (widget.bookmark != null &&
                  widget.collectionsState != null) ...[
                const SizedBox(height: NexusSpacing.md),
                Text('Collections', style: NexusTypography.labelMd),
                const SizedBox(height: NexusSpacing.xs),
                Watch((_) {
                  final collections =
                      widget.collectionsState!.collections.value;
                  final names = collections
                      .where(
                        (c) => widget.bookmark!.collectionIds.contains(c.id),
                      )
                      .map((c) => c.name)
                      .toList();
                  if (names.isEmpty) {
                    return Text(
                      'Not in any collection',
                      style: NexusTypography.bodyMd.copyWith(
                        color: NexusColors.onSurfaceVariant,
                      ),
                    );
                  }
                  return Wrap(
                    spacing: NexusSpacing.xs,
                    runSpacing: NexusSpacing.xs,
                    children: names
                        .map((name) => NexusBadge(label: name))
                        .toList(),
                  );
                }),
                const SizedBox(height: NexusSpacing.xs),
                NexusButton(
                  label: 'Manage Collections',
                  icon: Icons.folder_outlined,
                  onPressed: () => _showAddToCollectionDialog(context),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        NexusButton(
          label: 'Save',
          onPressed: () {
            final existing = widget.bookmark;
            final now = DateTime.now();
            widget.onSave(
              BookmarkModel(
                id: existing?.id,
                title: _title.text,
                url: _url.text,
                tags: _tags,
                category: _category,
                image: _image,
                collectionIds: existing?.collectionIds ?? const [],
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
              ),
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _showAddToCollectionDialog(BuildContext context) {
    final bookmark = widget.bookmark;
    final collectionsState = widget.collectionsState;
    final bookmarksState = widget.bookmarksState;
    if (bookmark == null ||
        collectionsState == null ||
        bookmarksState == null) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _AddToCollectionDialog(
        collectionsState: collectionsState,
        bookmarksState: bookmarksState,
        bookmark: bookmark,
      ),
    );
  }
}
