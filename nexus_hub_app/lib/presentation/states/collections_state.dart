import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/collection_model.dart';
import '../../data/repositories/collection_repository.dart';

/// Signals-backed state for collections.
class CollectionsState {
  CollectionsState({CollectionRepository? repository})
    : _repository = repository ?? CollectionRepository();

  final CollectionRepository _repository;

  final Signal<List<CollectionModel>> collections =
      signal<List<CollectionModel>>([]);
  final Signal<String?> error = signal<String?>(null);
  final Signal<bool> isLoading = signal<bool>(false);
  final Signal<String> sort = signal<String>('name_asc');

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      collections.value = await _repository.fetchCollections(sort: sort.value);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> create(String name) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _repository.createCollection(name);
      collections.value = await _repository.fetchCollections(sort: sort.value);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> rename(int id, String name) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _repository.updateCollection(id, name);
      collections.value = await _repository.fetchCollections(sort: sort.value);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> delete(int id) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _repository.deleteCollection(id);
      collections.value = await _repository.fetchCollections(sort: sort.value);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void setSort(String value) {
    sort.value = value;
    load();
  }

  Future<void> addBookmarks(int collectionId, List<int> bookmarkIds) async {
    error.value = null;
    try {
      await _repository.addBookmarksToCollection(collectionId, bookmarkIds);
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> removeBookmarks(int collectionId, List<int> bookmarkIds) async {
    error.value = null;
    try {
      await _repository.removeBookmarksFromCollection(
        collectionId,
        bookmarkIds,
      );
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<int> countBookmarks(int collectionId) async {
    return _repository.countBookmarks(collectionId);
  }
}
