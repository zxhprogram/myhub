import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/desktop_item.dart';

/// Signals-based state for desktop items (app shortcuts and folders).
///
/// Manages the ordered list of items on the desktop, folder contents, and
/// persists the state across restarts via [SharedPreferences].
class DesktopState {
  DesktopState._();

  /// The singleton instance used across the app.
  static final DesktopState instance = DesktopState._();

  static const _storageKey = 'nexus_desktop_items_v1';

  /// All items currently on the desktop (apps + folders), in display order.
  final items = signal<List<DesktopItem>>(const []);

  bool _initialized = false;

  /// Loads persisted state, or seeds [defaults] on first launch.
  ///
  /// When persisted state exists, it is authoritative for order/folders, but
  /// any app shortcuts present in [defaults] that are missing from the
  /// persisted list are appended — so newly-added desktop apps (e.g. Terminal)
  /// appear for existing users without discarding their layout. Persisted app
  /// shortcuts whose route is no longer part of [defaults] (removed or
  /// renamed apps) are pruned: they can never resolve to an icon and would
  /// render as zero-height slots that misalign the desktop icon grid.
  Future<void> init({List<DesktopItem>? defaults}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final loaded = await _loadPersisted();
    if (loaded != null) {
      final persisted = List<DesktopItem>.from(loaded);
      if (defaults != null) {
        final availableRoutes = defaults
            .where((d) => d.appRoute != null)
            .map((d) => d.appRoute!)
            .toSet();
        persisted.removeWhere(
          (item) =>
              item.type == DesktopItemType.app &&
              (item.appRoute == null ||
                  !availableRoutes.contains(item.appRoute)),
        );
        final knownRoutes = persisted
            .where((i) => i.appRoute != null)
            .map((i) => i.appRoute!)
            .toSet();
        for (final d in defaults) {
          final appRoute = d.appRoute;
          if (appRoute != null && !knownRoutes.contains(appRoute)) {
            persisted.add(d);
            knownRoutes.add(appRoute);
          }
        }
        if (persisted.length != loaded.length) {
          items.value = persisted;
          _persist();
        } else {
          items.value = persisted;
        }
      } else {
        items.value = persisted;
      }
    } else if (defaults != null) {
      items.value = List<DesktopItem>.from(defaults);
    }
  }

  // ── Reorder ──────────────────────────────────────────────────────────────

  /// Items currently visible on the desktop (items inside folders are hidden).
  List<DesktopItem> get visibleItems {
    final inFolder = _idsInsideFolders();
    return items.value.where((item) => !inFolder.contains(item.id)).toList();
  }

  /// Reorders the desktop-visible items while keeping items that live inside
  /// folders pinned to their current slot in the underlying list.
  ///
  /// [oldIndex]/[newIndex] refer to positions within [visibleItems].
  void reorderVisible(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final inFolder = _idsInsideFolders();

    final visible = visibleItems;
    final reordered = List<DesktopItem>.from(visible);
    final dragged = reordered.removeAt(oldIndex);
    // ReorderableBuilder's newIndex accounts for the removed item when
    // newIndex > oldIndex.
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    reordered.insert(targetIndex, dragged);

    // Rebuild the full list: in-folder items keep their slot, visible slots
    // are filled with the reordered sequence.
    var visibleIndex = 0;
    items.value = items.value.map((item) {
      if (inFolder.contains(item.id)) return item;
      return reordered[visibleIndex++];
    }).toList();
    _persist();
  }

  /// Ids of all items that are inside any folder.
  Set<String> _idsInsideFolders() {
    return {
      for (final item in items.value)
        if (item.type == DesktopItemType.folder) ...item.folderItemIds,
    };
  }

  // ── Folder CRUD ──────────────────────────────────────────────────────────

  /// Creates a new empty folder with [name] and appends it to the desktop.
  Future<void> createFolder(String name) async {
    final folder = DesktopItem(
      id: _generateId(),
      type: DesktopItemType.folder,
      label: name,
      folderName: name,
    );
    items.value = [...items.value, folder];
    _persist();
  }

  /// Renames the folder identified by [folderId].
  void renameFolder(String folderId, String newName) {
    items.value = items.value.map((item) {
      if (item.id == folderId && item.type == DesktopItemType.folder) {
        return item.copyWith(label: newName, folderName: newName);
      }
      return item;
    }).toList();
    _persist();
  }

  /// Deletes the folder identified by [folderId] (contained items are NOT
  /// removed from the desktop — only the folder reference is dropped).
  void deleteFolder(String folderId) {
    items.value = items.value.where((item) => item.id != folderId).toList();
    _persist();
  }

  // ── Drag into folder ─────────────────────────────────────────────────────

  /// Adds [itemId] to the folder identified by [folderId].
  void moveItemToFolder(String itemId, String folderId) {
    items.value = items.value.map((item) {
      if (item.id == folderId && item.type == DesktopItemType.folder) {
        if (!item.folderItemIds.contains(itemId)) {
          return item.copyWith(folderItemIds: [...item.folderItemIds, itemId]);
        }
      }
      return item;
    }).toList();
    _persist();
  }

  /// Removes [itemId] from the folder identified by [folderId].
  void removeItemFromFolder(String itemId, String folderId) {
    items.value = items.value.map((item) {
      if (item.id == folderId && item.type == DesktopItemType.folder) {
        return item.copyWith(
          folderItemIds: item.folderItemIds
              .where((id) => id != itemId)
              .toList(),
        );
      }
      return item;
    }).toList();
    _persist();
  }

  /// Returns the list of [DesktopItem]s whose IDs are in [folderItemIds].
  List<DesktopItem> getFolderItems(String folderId) {
    final folder = items.value.firstWhere(
      (item) => item.id == folderId && item.type == DesktopItemType.folder,
    );
    return items.value
        .where((item) => folder.folderItemIds.contains(item.id))
        .toList();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(items.value.map((i) => i.toJson()).toList());
      await prefs.setString(_storageKey, json);
    } catch (_) {
      // Persistence failure is non-fatal — state is still valid in memory.
    }
  }

  Future<List<DesktopItem>?> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((j) => DesktopItem.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static int _idCounter = 0;

  /// Generates a unique ID string for new desktop items.
  static String _generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }
}
