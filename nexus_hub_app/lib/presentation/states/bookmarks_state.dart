import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/bookmark_model.dart';
import '../../data/repositories/bookmark_repository.dart';

/// Signals-backed state for bookmarks.
class BookmarksState {
  BookmarksState({BookmarkRepository? repository})
    : _repository = repository ?? BookmarkRepository();

  final BookmarkRepository _repository;

  final Signal<List<BookmarkModel>> bookmarks = signal<List<BookmarkModel>>([]);
  final Signal<String?> error = signal<String?>(null);
  final Signal<bool> isLoading = signal<bool>(false);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      bookmarks.value = await _repository.fetchBookmarks();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> search(String query) async {
    isLoading.value = true;
    error.value = null;
    try {
      bookmarks.value = await _repository.fetchBookmarks(query: query);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> add(BookmarkModel bookmark) async {
    try {
      final created = await _repository.createBookmark(bookmark);
      bookmarks.value = [...bookmarks.value, created];
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final list = List<BookmarkModel>.from(bookmarks.value);
    final item = list.removeAt(oldIndex);
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(targetIndex, item);
    bookmarks.value = list;

    try {
      final ids = list.map((b) => b.id!).toList();
      final reordered = await _repository.reorder(ids);
      bookmarks.value = reordered;
    } catch (e) {
      error.value = e.toString();
    }
  }
}
