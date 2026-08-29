import 'dart:io';

import '../models/clipboard_item_model.dart';
import '../services/clipboard_file_store.dart';
import '../services/local_database.dart';

/// Repository for clipboard history backed by the local Hive store, with
/// file/image payloads kept on disk via [ClipboardFileStore].
class ClipboardRepository {
  ClipboardRepository({ClipboardFileStore? fileStore})
      : _fileStore = fileStore ?? ClipboardFileStore();

  final ClipboardFileStore _fileStore;

  Future<List<ClipboardItemModel>> fetchItems({String? query}) async {
    final rows = (await LocalDatabase.box('clipboard'))
        .values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
      if (query == null || query.isEmpty) return true;
      final content = (row['content'] as String?) ?? '';
      return content.toLowerCase().contains(query.toLowerCase());
    }).toList();
    rows.sort((a, b) {
      final aCreated = DateTime.parse(a['createdAt'] as String);
      final bCreated = DateTime.parse(b['createdAt'] as String);
      return bCreated.compareTo(aCreated);
    });
    return rows.map(ClipboardItemModel.fromJson).toList();
  }

  Future<ClipboardItemModel> createItem(ClipboardItemModel item) async {
    final created = item.copyWith(id: null, createdAt: DateTime.now());
    final id = await _insertLocal(created);
    return created.copyWith(id: id);
  }

  /// Imports a file/image from the system clipboard: the file is copied into
  /// the local clipboard file store and referenced from the stored item
  /// (previously the file was uploaded to the backend).
  Future<ClipboardItemModel> uploadFile({
    required String filePath,
    required String type,
    String? mimeType,
    String? content,
  }) async {
    final name = filePath.split(Platform.pathSeparator).last;
    final storedPath = await _fileStore.importFile(filePath);
    final local = ClipboardItemModel(
      content: content ?? name,
      type: type,
      filePath: storedPath,
      mimeType: mimeType,
      createdAt: DateTime.now(),
    );
    final id = await _insertLocal(local);
    final created = local.copyWith(id: id);
    // The store now owns the file; clean up the local temporary copy.
    await _deleteSourceFile(filePath);
    return created;
  }

  Future<void> deleteItem(int id) async {
    final box = await LocalDatabase.box('clipboard');
    final existing = box.get(id);
    if (existing != null) {
      final item = ClipboardItemModel.fromJson(
        Map<String, dynamic>.from(existing as Map),
      );
      final path = item.filePath;
      if (path != null && path.isNotEmpty) {
        await _fileStore.deleteFile(path);
      }
    }
    await box.delete(id);
  }

  Future<void> clear() async {
    await _fileStore.deleteAll();
    final box = await LocalDatabase.box('clipboard');
    await box.clear();
  }

  Future<int> _insertLocal(ClipboardItemModel item) async {
    final box = await LocalDatabase.box('clipboard');
    final id = item.id;
    if (id != null) {
      await box.put(id, item.toJson());
      return id;
    }
    final newId = await box.add(item.toJson());
    // Backfill the generated id into the stored record so later loads see it.
    await box.put(newId, item.copyWith(id: newId).toJson());
    return newId;
  }

  Future<void> _deleteSourceFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Ignore cleanup failures.
    }
  }
}
