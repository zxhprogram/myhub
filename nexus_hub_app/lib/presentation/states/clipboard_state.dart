import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/clipboard_item_model.dart';
import '../../data/repositories/clipboard_repository.dart';

/// Signals-based state for the clipboard history page.
class ClipboardState {
  ClipboardState({ClipboardRepository? repository})
    : _repository = repository ?? ClipboardRepository();

  final ClipboardRepository _repository;

  final items = signal<List<ClipboardItemModel>>([]);
  final isLoading = signal<bool>(false);
  final error = signal<String?>(null);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      items.value = await _repository.fetchItems();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> add(ClipboardItemModel item) async {
    error.value = null;
    try {
      final created = item.hasFile
          ? await _repository.uploadFile(
              filePath: item.filePath!,
              type: item.type,
              mimeType: item.mimeType,
              content: item.content,
            )
          : await _repository.createItem(item);
      items.value = [created, ...items.value];
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> addFile({
    required String filePath,
    required String type,
    String? mimeType,
    String? content,
  }) async {
    error.value = null;
    try {
      final created = await _repository.uploadFile(
        filePath: filePath,
        type: type,
        mimeType: mimeType,
        content: content,
      );
      items.value = [created, ...items.value];
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> delete(int id) async {
    error.value = null;
    try {
      await _repository.deleteItem(id);
      items.value = items.value.where((i) => i.id != id).toList();
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> clear() async {
    error.value = null;
    try {
      await _repository.clear();
      items.value = [];
    } catch (e) {
      error.value = e.toString();
    }
  }
}
