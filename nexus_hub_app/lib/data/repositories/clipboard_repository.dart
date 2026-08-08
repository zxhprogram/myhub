import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/clipboard_item_model.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// Repository for clipboard history with offline fallback.
class ClipboardRepository {
  ClipboardRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<ClipboardItemModel>> fetchItems({String? query}) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/clipboard',
        queryParameters: query != null ? {'q': query} : null,
      );
      final data = response.data ?? [];
      final items = data
          .cast<Map<String, dynamic>>()
          .map(ClipboardItemModel.fromJson)
          .toList();
      await _cacheItems(items);
      return items;
    } catch (_) {
      return _loadCachedItems(query: query);
    }
  }

  Future<ClipboardItemModel> createItem(ClipboardItemModel item) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/clipboard',
        data: item.toJson(),
      );
      final created = ClipboardItemModel.fromJson(response.data!);
      await _insertLocal(created);
      return created;
    } catch (_) {
      final local = item.copyWith(id: null);
      final id = await _insertLocal(local);
      return local.copyWith(id: id);
    }
  }

  /// Uploads a file/image from the system clipboard and creates a clipboard
  /// item on the backend.
  Future<ClipboardItemModel> uploadFile({
    required String filePath,
    required String type,
    String? mimeType,
    String? content,
  }) async {
    final name = p.basename(filePath);
    final fields = <String, dynamic>{'type': type};
    if (mimeType != null) fields['mimeType'] = mimeType;
    if (content != null) fields['content'] = content;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: name),
      ...fields,
    });

    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/clipboard',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final created = ClipboardItemModel.fromJson(response.data!);
      await _insertLocal(created);
      // The backend now owns the file; clean up the local temporary copy.
      await _deleteSourceFile(filePath);
      return created;
    } catch (_) {
      // Fallback: keep the item locally with the local file path.
      final local = ClipboardItemModel(
        id: null,
        content: content ?? name,
        type: type,
        filePath: filePath,
        mimeType: mimeType,
        createdAt: DateTime.now(),
      );
      final id = await _insertLocal(local);
      return local.copyWith(id: id);
    }
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

  Future<void> deleteItem(int id) async {
    try {
      await _client.delete<void>('/clipboard/$id');
      await _deleteLocal(id);
    } catch (_) {
      await _deleteLocal(id);
    }
  }

  Future<void> clear() async {
    try {
      await _client.delete<void>('/clipboard');
      await _clearLocal();
    } catch (_) {
      await _clearLocal();
    }
  }

  Future<void> _cacheItems(List<ClipboardItemModel> items) async {
    final box = await LocalDatabase.box('clipboard');
    await box.clear();
    for (final item in items) {
      await _insertLocal(item);
    }
  }

  Future<int> _insertLocal(ClipboardItemModel item) async {
    final box = await LocalDatabase.box('clipboard');
    final id = item.id;
    if (id != null) {
      await box.put(id, item.toJson());
      return id;
    }
    return await box.add(item.toJson());
  }

  Future<List<ClipboardItemModel>> _loadCachedItems({String? query}) async {
    final box = await LocalDatabase.box('clipboard');
    final rows = box.values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
      if (query == null) return true;
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

  Future<void> _deleteLocal(int id) async {
    final box = await LocalDatabase.box('clipboard');
    await box.delete(id);
  }

  Future<void> _clearLocal() async {
    final box = await LocalDatabase.box('clipboard');
    await box.clear();
  }
}
