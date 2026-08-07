import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../states/desktop_state.dart';

/// Preview of up to 4 mini app icons displayed inside a folder's squircle.
class DesktopFolderPreview extends StatelessWidget {
  const DesktopFolderPreview({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final folderItems = DesktopState.instance.getFolderItems(folderId);
      if (folderItems.isEmpty) {
        return const Icon(Icons.folder, size: 26, color: Colors.white70);
      }

      final visible = folderItems.take(4).toList();
      final cols = visible.length > 1 ? 2 : 1;

      return Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = 2.0;
            final totalSpacing = spacing * (cols - 1);
            final size = (constraints.maxWidth - totalSpacing) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: visible.map((item) {
                return _MiniIcon(size: size, item: item);
              }).toList(),
            );
          },
        ),
      );
    });
  }
}

/// A single mini icon (16-20px) shown inside the folder preview.
class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.size, required this.item});

  final double size;
  final dynamic item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(size * 0.23),
      ),
      child: const Icon(Icons.insert_drive_file_outlined,
          size: 10, color: Colors.white70),
    );
  }
}

/// Dialog showing the contents of a folder.
class DesktopFolderContent extends StatelessWidget {
  const DesktopFolderContent({super.key, required this.folderId});

  final String folderId;

  static void show(BuildContext context, String folderId) {
    showDialog(
      context: context,
      builder: (_) => DesktopFolderContent(folderId: folderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = DesktopState.instance;
      final allItems = state.items.value;
      final folder = allItems.firstWhere(
        (item) => item.id == folderId,
      );
      final folderItems = state.getFolderItems(folderId);

      return AlertDialog(
        title: Text(folder.folderName ?? '文件夹'),
        content: SizedBox(
          width: 300,
          child: folderItems.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('文件夹为空',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: folderItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = folderItems[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(item.label ?? item.folderName ?? ''),
                      dense: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    });
  }
}
