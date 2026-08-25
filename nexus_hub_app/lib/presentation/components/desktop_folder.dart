import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/desktop_item.dart';
import '../../theme/typography.dart';
import '../layout/desktop_environment.dart';
import '../states/desktop_state.dart';
import 'app_squircle_icon.dart';

/// Windows 11 style folder flyout: a rounded panel titled with the folder
/// name, showing the contained apps as a 4-column icon grid. Clicking an
/// icon opens the app; right-click offers removing it from the folder.
/// The flyout closes when clicking outside or pressing Esc.
class DesktopFolderContent {
  DesktopFolderContent._();

  static void show(
    BuildContext context,
    String folderId, {
    DesktopAppItem? Function(String route)? resolveApp,
    void Function(String route)? onOpenApp,
  }) {
    showOverlay<void>(
      context,
      DialogConfiguration<void>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.30),
        builder: (_) => _FolderFlyout(
          folderId: folderId,
          resolveApp: resolveApp,
          onOpenApp: onOpenApp,
        ),
      ),
    );
  }
}

class _FolderFlyout extends StatelessWidget {
  const _FolderFlyout({
    required this.folderId,
    this.resolveApp,
    this.onOpenApp,
  });

  final String folderId;
  final DesktopAppItem? Function(String route)? resolveApp;
  final void Function(String route)? onOpenApp;

  void _openItem(BuildContext context, DesktopItem item) {
    final route = item.appRoute;
    if (route == null) return;
    onOpenApp?.call(route);
    closeOverlay<void>(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = DesktopState.instance;
      final allItems = state.items.value;
      final folder = allItems.firstWhere(
        (item) => item.id == folderId && item.type == DesktopItemType.folder,
      );
      final folderItems = state.getFolderItems(folderId);

      return Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(
          color: colorScheme.popover,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.border.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: centered folder name, close button on the right
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    folder.folderName ?? '文件夹',
                    style: NexusTypography.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton.ghost(
                      icon: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: colorScheme.mutedForeground,
                      ),
                      onPressed: () => closeOverlay<void>(context),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.border.withValues(alpha: 0.3),
            ),
            Flexible(
              child: folderItems.isEmpty
                  ? _buildEmptyState(colorScheme)
                  : GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 0.82,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: folderItems.length,
                      itemBuilder: (context, index) {
                        return _FolderGridItem(
                          item: folderItems[index],
                          resolveApp: resolveApp,
                          onOpen: () => _openItem(context, folderItems[index]),
                          onRemove: () => DesktopState.instance
                              .removeItemFromFolder(
                            folderItems[index].id,
                            folderId,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: colorScheme.muted.withValues(alpha: 0.5),
            ),
            child: Icon(
              LucideIcons.folderOpen,
              size: 26,
              color: colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '文件夹是空的',
            style: NexusTypography.bodyMd
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '将桌面上的应用图标拖到文件夹即可添加',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry in the folder flyout grid: app squircle + label, with hover
/// highlight, click-to-open and a right-click context menu.
class _FolderGridItem extends StatefulWidget {
  const _FolderGridItem({
    required this.item,
    required this.onOpen,
    required this.onRemove,
    this.resolveApp,
  });

  final DesktopItem item;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final DesktopAppItem? Function(String route)? resolveApp;

  @override
  State<_FolderGridItem> createState() => _FolderGridItemState();
}

class _FolderGridItemState extends State<_FolderGridItem> {
  bool _hovering = false;

  DesktopAppItem? get _appItem =>
      widget.resolveApp?.call(widget.item.appRoute ?? '');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appItem = _appItem;
    final label = widget.item.label ?? widget.item.folderName ?? '未命名';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ContextMenu(
        items: [
          MenuButton(
            leading: const Icon(LucideIcons.externalLink, size: 16),
            onPressed: (context) => widget.onOpen(),
            child: const Text('打开'),
          ),
          MenuButton(
            leading: const Icon(LucideIcons.folderMinus, size: 16),
            onPressed: (context) => widget.onRemove(),
            child: const Text('从文件夹移除'),
          ),
        ],
        child: GestureDetector(
          onTap: widget.onOpen,
          onDoubleTap: widget.onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _hovering
                  ? colorScheme.muted.withValues(alpha: 0.45)
                  : const Color(0x00000000),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: _hovering ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: AppSquircleIcon(
                    gradientStart:
                        appItem?.gradientStart ?? const Color(0xFFB9C0CB),
                    gradientEnd:
                        appItem?.gradientEnd ?? const Color(0xFF8A93A3),
                    size: 48,
                    child: Icon(appItem?.icon ?? LucideIcons.file, size: 24),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: NexusTypography.labelSm.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
