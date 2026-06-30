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
    final db = await LocalDatabase.instance;
    await db.delete('clipboard');
    for (final item in items) {
      await _insertLocal(item);
    }
  }

  Future<int> _insertLocal(ClipboardItemModel item) async {
    final db = await LocalDatabase.instance;
    return db.insert('clipboard', item.toDb());
  }

  Future<List<ClipboardItemModel>> _loadCachedItems({String? query}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'clipboard',
      where: query != null ? 'content LIKE ?' : null,
      whereArgs: query != null ? ['%$query%'] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(ClipboardItemModel.fromDb).toList();
  }

  Future<void> _deleteLocal(int id) async {
    final db = await LocalDatabase.instance;
    await db.delete('clipboard', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _clearLocal() async {
    final db = await LocalDatabase.instance;
    await db.delete('clipboard');
  }
}
