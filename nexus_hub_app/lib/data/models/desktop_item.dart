/// Types of items that can appear on the desktop.
enum DesktopItemType { app, folder }

/// A single item on the desktop — either an application shortcut or a folder.
class DesktopItem {
  const DesktopItem({
    required this.id,
    required this.type,
    this.label,
    this.appRoute,
    this.folderName,
    this.folderItemIds = const [],
  });

  /// Unique identifier (milliseconds-since-epoch string, generated locally).
  final String id;

  /// Whether this item is an app shortcut or a folder.
  final DesktopItemType type;

  /// Display label shown on the desktop (app name or folder name).
  final String? label;

  /// For [DesktopItemType.app]: the [route] of the matching [DesktopAppItem].
  final String? appRoute;

  /// For [DesktopItemType.folder]: the display name shown on the desktop.
  final String? folderName;

  /// For [DesktopItemType.folder]: IDs of [DesktopItem]s contained in this folder.
  final List<String> folderItemIds;

  factory DesktopItem.fromJson(Map<String, dynamic> json) {
    return DesktopItem(
      id: json['id'] as String,
      type: DesktopItemType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      label: json['label'] as String?,
      appRoute: json['appRoute'] as String?,
      folderName: json['folderName'] as String?,
      folderItemIds: (json['folderItemIds'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (label != null) 'label': label,
    if (appRoute != null) 'appRoute': appRoute,
    if (folderName != null) 'folderName': folderName,
    'folderItemIds': folderItemIds,
  };

  DesktopItem copyWith({
    String? id,
    DesktopItemType? type,
    String? label,
    String? appRoute,
    String? folderName,
    List<String>? folderItemIds,
    bool clearLabel = false,
    bool clearAppRoute = false,
    bool clearFolderName = false,
  }) {
    return DesktopItem(
      id: id ?? this.id,
      type: type ?? this.type,
      label: clearLabel ? null : (label ?? this.label),
      appRoute: clearAppRoute ? null : (appRoute ?? this.appRoute),
      folderName: clearFolderName ? null : (folderName ?? this.folderName),
      folderItemIds: folderItemIds ?? this.folderItemIds,
    );
  }
}
