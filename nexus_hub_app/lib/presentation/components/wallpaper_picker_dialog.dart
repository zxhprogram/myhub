import 'dart:math';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/wallpaper_item.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../states/wallpaper_state.dart';
import 'nexus_button.dart';

/// Modal dialog showing the recent Bing wallpapers in a grid.
///
/// Tapping a thumbnail applies it as the desktop wallpaper and closes the
/// dialog. Also offers "random", "restore default" and "refresh".
class WallpaperPickerDialog extends StatelessWidget {
  const WallpaperPickerDialog({super.key});

  /// Shows the wallpaper picker as a modal dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const WallpaperPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NexusColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.lg,
        NexusSpacing.md,
        NexusSpacing.md,
        NexusSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.wallpaper, size: 20, color: NexusColors.onSurface),
          const SizedBox(width: NexusSpacing.sm),
          Text('壁纸库', style: NexusTypography.headlineSm),
          const Spacer(),
          Watch((_) {
            final loading = WallpaperState.instance.isLoading.value;
            return IconButton(
              tooltip: '刷新',
              onPressed: loading
                  ? null
                  : () => WallpaperState.instance.refresh(),
              icon: const Icon(Icons.refresh),
            );
          }),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Watch((_) {
      final state = WallpaperState.instance;
      if (state.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      final error = state.error.value;
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off,
                size: 40,
                color: NexusColors.onSurfaceVariant,
              ),
              const SizedBox(height: NexusSpacing.md),
              Text('壁纸加载失败', style: NexusTypography.bodyMd),
              const SizedBox(height: NexusSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.lg,
                ),
                child: Text(
                  error,
                  style: NexusTypography.labelMd,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: NexusSpacing.md),
              TextButton(
                onPressed: () => state.refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      final wallpapers = state.wallpapers.value;
      if (wallpapers.isEmpty) {
        return const Center(child: Text('暂无壁纸'));
      }
      final current = state.currentWallpaper.value;
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: NexusSpacing.md,
          mainAxisSpacing: NexusSpacing.md,
          childAspectRatio: 16 / 9,
        ),
        itemCount: wallpapers.length,
        itemBuilder: (context, index) {
          final item = wallpapers[index];
          return _WallpaperThumb(
            item: item,
            selected: current?.url == item.url,
            onTap: () {
              WallpaperState.instance.setWallpaper(item);
              Navigator.of(context).pop();
            },
          );
        },
      );
    });
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        children: [
          Watch((_) {
            final current = WallpaperState.instance.currentWallpaper.value;
            return NexusButton(
              label: '恢复默认',
              variant: NexusButtonVariant.outlined,
              icon: Icons.restart_alt,
              onPressed: current == null
                  ? null
                  : () {
                      WallpaperState.instance.clearWallpaper();
                      Navigator.of(context).pop();
                    },
            );
          }),
          const Spacer(),
          NexusButton(
            label: '随机换一张',
            variant: NexusButtonVariant.outlined,
            icon: Icons.shuffle,
            onPressed: () {
              final wallpapers = WallpaperState.instance.wallpapers.value;
              if (wallpapers.isEmpty) {
                return;
              }
              final item = wallpapers[Random().nextInt(wallpapers.length)];
              WallpaperState.instance.setWallpaper(item);
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: NexusSpacing.sm),
          NexusButton(
            label: '完成',
            variant: NexusButtonVariant.filled,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A single wallpaper thumbnail in the picker grid.
class _WallpaperThumb extends StatelessWidget {
  const _WallpaperThumb({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final WallpaperItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? NexusColors.secondary : NexusColors.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: NexusRadii.mdRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: NexusRadii.mdRadius,
            child: Image.network(
              item.thumbnailUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  return child;
                }
                return Container(
                  color: NexusColors.surfaceContainer,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: NexusColors.surfaceContainer,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Text(
                item.date,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 2),
                borderRadius: NexusRadii.mdRadius,
              ),
            ),
        ],
      ),
    );
  }
}
