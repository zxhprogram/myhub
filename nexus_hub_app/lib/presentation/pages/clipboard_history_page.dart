import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../components/nexus_toast.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/clipboard_item_model.dart';
import '../../data/services/api_client.dart';
import '../../presentation/states/clipboard_state.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_empty_state.dart';
import '../components/nexus_input.dart';

enum ClipboardView { grid, list }

class ClipboardHistoryPage extends StatefulWidget {
  const ClipboardHistoryPage({super.key});

  @override
  State<ClipboardHistoryPage> createState() => _ClipboardHistoryPageState();
}

class _ClipboardHistoryPageState extends State<ClipboardHistoryPage> {
  final _state = ClipboardState.instance;
  final _query = signal<String>('');
  final _view = signal<ClipboardView>(ClipboardView.grid);

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  List<ClipboardItemModel> _visibleItems(List<ClipboardItemModel> all) {
    final query = _query.value.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all
        .where((item) => item.content.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.background,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            count: _state.items.value.length,
            view: _view.value,
            onViewChanged: (view) => _view.value = view,
            onClear: () => _showClearConfirmation(context),
          ),
          const SizedBox(height: NexusSpacing.md),
          NexusInput(
            hintText: 'Search clipboard...',
            prefixIcon: const Icon(RadixIcons.magnifyingGlass, size: 20),
            onChanged: (value) => _query.value = value,
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: Watch((_) {
              if (_state.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_state.error.value != null) {
                return Center(
                  child: Text(
                    'Error: ${_state.error.value}',
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.destructive,
                    ),
                  ),
                );
              }
              final visible = _visibleItems(_state.items.value);
              if (visible.isEmpty) {
                return const NexusEmptyState(
                  icon: RadixIcons.clipboard,
                  title: 'No clipboard items yet',
                  subtitle: 'Copy text, images, or files to see them here.',
                );
              }
              return switch (_view.value) {
                ClipboardView.grid => _ClipboardGrid(
                  items: visible,
                  onCopy: _copyToClipboard,
                  onDelete: _deleteItem,
                  onOpen: _openFile,
                ),
                ClipboardView.list => _ClipboardList(
                  items: visible,
                  onCopy: _copyToClipboard,
                  onDelete: _deleteItem,
                  onOpen: _openFile,
                ),
              };
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(ClipboardItemModel item) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final writerItem = DataWriterItem();
    final text = item.hasFile ? (item.filePath ?? item.content) : item.content;
    writerItem.add(Formats.plainText(text));
    await clipboard.write([writerItem]);

    if (mounted) {
      nexusToast(context, 'Copied to clipboard');
    }
  }

  Future<void> _openFile(ClipboardItemModel item) async {
    final path = item.filePath;
    if (path == null || path.isEmpty) return;

    final uri = _isRemotePath(path)
        ? Uri.parse(
            '${ApiClient.defaultBaseUrl}/clipboard/files/${p.basename(path)}',
          )
        : File(path).uri;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _deleteItem(ClipboardItemModel item) async {
    final id = item.id;
    if (id == null) return;
    await _state.delete(id);
  }

  void _showClearConfirmation(BuildContext context) {
    showOverlay<void>(
      context,
      DialogConfiguration<void>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => AlertDialog(
          title: const Text('Clear clipboard history?'),
          content: const Text(
            'This will remove all items. This action cannot be undone.',
          ),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<void>(ctx),
              child: const Text('Cancel'),
            ),
            Button.destructive(
              onPressed: () {
                _state.clear();
                closeOverlay<void>(ctx);
              },
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.view,
    required this.onViewChanged,
    required this.onClear,
  });

  final int count;
  final ClipboardView view;
  final ValueChanged<ClipboardView> onViewChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Clipboard History', style: NexusTypography.headlineXl),
                const SizedBox(width: NexusSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.muted,
                    borderRadius: NexusRadii.fullRadius,
                  ),
                  child: Text(
                    '$count',
                    style: NexusTypography.labelSm.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              'Recent copied text, images, and files.',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _ViewToggle(view: view, onChanged: onViewChanged),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(
              label: 'Clear History',
              icon: LucideIcons.trash2,
              variant: NexusButtonVariant.outlined,
              onPressed: onClear,
            ),
          ],
        ),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final ClipboardView view;
  final ValueChanged<ClipboardView> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border.all(color: colorScheme.border),
        borderRadius: NexusRadii.lgRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(
            icon: RadixIcons.grid,
            active: view == ClipboardView.grid,
            colorScheme: colorScheme,
            onTap: () => onChanged(ClipboardView.grid),
          ),
          _toggleButton(
            icon: LucideIcons.list,
            active: view == ClipboardView.list,
            colorScheme: colorScheme,
            onTap: () => onChanged(ClipboardView.list),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required bool active,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
  onTap: onTap,
  child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: active
                ? colorScheme.foreground
                : colorScheme.mutedForeground,
          ),
        ),
);
  }
}

class _ClipboardGrid extends StatelessWidget {
  const _ClipboardGrid({
    required this.items,
    required this.onCopy,
    required this.onDelete,
    required this.onOpen,
  });

  final List<ClipboardItemModel> items;
  final ValueChanged<ClipboardItemModel> onCopy;
  final ValueChanged<ClipboardItemModel> onDelete;
  final ValueChanged<ClipboardItemModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 560
            ? 1
            : width < 960
            ? 2
            : 3;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: NexusSpacing.md,
            mainAxisSpacing: NexusSpacing.md,
            childAspectRatio: 1.05,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _ClipboardGridCard(
              key: ValueKey('clipboard-grid-${item.id}'),
              item: item,
              onCopy: () => onCopy(item),
              onDelete: () => onDelete(item),
              onOpen: () => onOpen(item),
            );
          },
        );
      },
    );
  }
}

class _ClipboardList extends StatelessWidget {
  const _ClipboardList({
    required this.items,
    required this.onCopy,
    required this.onDelete,
    required this.onOpen,
  });

  final List<ClipboardItemModel> items;
  final ValueChanged<ClipboardItemModel> onCopy;
  final ValueChanged<ClipboardItemModel> onDelete;
  final ValueChanged<ClipboardItemModel> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
          child: _ClipboardListCard(
            key: ValueKey('clipboard-list-${item.id}'),
            item: item,
            onCopy: () => onCopy(item),
            onDelete: () => onDelete(item),
            onOpen: () => onOpen(item),
          ),
        );
      },
    );
  }
}

class _ClipboardGridCard extends StatefulWidget {
  const _ClipboardGridCard({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDelete,
    required this.onOpen,
  });

  final ClipboardItemModel item;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  State<_ClipboardGridCard> createState() => _ClipboardGridCardState();
}

class _ClipboardGridCardState extends State<_ClipboardGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colorScheme.card,
          borderRadius: NexusRadii.xxlRadius,
          border: Border.all(
            color: _hovered
                ? colorScheme.border
                : colorScheme.border.withValues(alpha: 0.5),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: colorScheme.foreground.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: colorScheme.foreground.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: NexusRadii.xxlRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.accent,
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.border.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ),
                      child: _ItemPreview(
                        item: widget.item,
                        fit: BoxFit.cover,
                        onTap: widget.item.hasFile ? widget.onOpen : null,
                      ),
                    ),
                    if (_hovered)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          children: [
                            _HoverAction(
                              icon: RadixIcons.copy,
                              onTap: widget.onCopy,
                            ),
                            if (widget.item.hasFile) ...[
                              const SizedBox(width: 4),
                              _HoverAction(
                                icon: RadixIcons.externalLink,
                                onTap: widget.onOpen,
                              ),
                            ],
                            const SizedBox(width: 4),
                            _HoverAction(
                              icon: LucideIcons.trash2,
                              danger: true,
                              onTap: widget.onDelete,
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
                    _TypeBadge(type: widget.item.type),
                    const SizedBox(height: NexusSpacing.sm),
                    Text(
                      widget.item.content,
                      style: NexusTypography.bodyMd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: NexusSpacing.xs),
                    Text(
                      _formatTime(widget.item.createdAt),
                      style: NexusTypography.labelSm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipboardListCard extends StatelessWidget {
  const _ClipboardListCard({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDelete,
    required this.onOpen,
  });

  final ClipboardItemModel item;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: _ItemPreview(
              item: item,
              fit: BoxFit.cover,
              borderRadius: NexusRadii.mdRadius,
              onTap: item.hasFile ? onOpen : null,
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeBadge(type: item.type),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  item.content,
                  style: NexusTypography.bodyMd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  _formatTime(item.createdAt),
                  style: NexusTypography.labelSm,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton.ghost(
  onPressed: onCopy,
  icon: const Icon(RadixIcons.copy, size: 18),
),
              if (item.hasFile)
                IconButton.ghost(
  onPressed: onOpen,
  icon: const Icon(RadixIcons.externalLink, size: 18),
),
              IconButton.ghost(
  onPressed: onDelete,
  icon: const Icon(LucideIcons.trash2, size: 18),
),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemPreview extends StatelessWidget {
  const _ItemPreview({
    required this.item,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.onTap,
  });

  final ClipboardItemModel item;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final child = switch (item.type) {
      'image' => _buildImage(),
      'file' => _FileIcon(name: item.content, mimeType: item.mimeType),
      _ => _TextPreview(content: item.content),
    };

    if (onTap == null) return child;

    return GestureDetector(
  onTap: onTap,
  child: child,
);
  }

  Widget _buildImage() {
    final path = item.filePath;
    if (path == null || path.isEmpty) {
      return const _Placeholder(icon: LucideIcons.image);
    }

    if (_isRemotePath(path)) {
      return Image.network(
        '${ApiClient.defaultBaseUrl}/clipboard/files/${p.basename(path)}',
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, _) => const _Placeholder(icon: LucideIcons.image),
      );
    }

    return Image.file(
      File(path),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, _, _) => const _Placeholder(icon: LucideIcons.image),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.muted,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Center(
        child: Text(
          content,
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.name, this.mimeType});

  final String name;
  final String? mimeType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final extension = p.extension(name).toUpperCase().replaceAll('.', '');
    final icon = _iconForMimeType(mimeType);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.muted,
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: colorScheme.mutedForeground),
          const SizedBox(height: NexusSpacing.sm),
          if (extension.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colorScheme.accent,
                borderRadius: NexusRadii.smRadius,
              ),
              child: Text(
                extension,
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.foreground,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForMimeType(String? mimeType) {
    if (mimeType == null) return LucideIcons.file;
    if (mimeType.startsWith('image/')) return LucideIcons.image;
    if (mimeType.startsWith('video/')) return LucideIcons.film;
    if (mimeType.startsWith('audio/')) return LucideIcons.music;
    if (mimeType == 'application/pdf') return LucideIcons.fileText;
    if (mimeType.contains('zip') ||
        mimeType.contains('compressed') ||
        mimeType.contains('archive')) {
      return LucideIcons.folderArchive;
    }
    return LucideIcons.file;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.muted,
      child: Icon(icon, size: 40, color: colorScheme.mutedForeground),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (type) {
      'text' => ('TEXT', colorScheme.primary),
      'image' => ('IMAGE', colorScheme.secondary),
      'file' => ('FILE', colorScheme.accent),
      _ => (type.toUpperCase(), colorScheme.accent),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: NexusRadii.smRadius,
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(color: colorScheme.foreground),
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
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onTap,
  child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.fullRadius,
            border: Border.all(color: colorScheme.border),
          ),
          child: Icon(
            icon,
            size: 16,
            color: danger ? colorScheme.destructive : colorScheme.foreground,
          ),
        ),
);
  }
}

bool _isRemotePath(String path) {
  return path.startsWith('temp/') || path.startsWith('temp\\');
}

String _formatTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hour ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
