import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/bookmark_model.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/collection_repository.dart';

/// Signals-backed state for bookmarks.
class BookmarksState {
  BookmarksState({
    BookmarkRepository? repository,
    CollectionRepository? collectionRepository,
  }) : _repository = repository ?? BookmarkRepository(),
       _collectionRepository = collectionRepository ?? CollectionRepository();

  final BookmarkRepository _repository;
  final CollectionRepository _collectionRepository;

  final Signal<List<BookmarkModel>> bookmarks = signal<List<BookmarkModel>>([]);
  final Signal<String?> error = signal<String?>(null);
  final Signal<bool> isLoading = signal<bool>(false);
  final Signal<int?> selectedCollectionId = signal<int?>(null);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      final collectionId = selectedCollectionId.value;
      if (collectionId != null) {
        bookmarks.value = await _collectionRepository.getBookmarksInCollection(
          collectionId,
        );
      } else {
        bookmarks.value = await _repository.fetchBookmarks();
      }
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
      final collectionId = selectedCollectionId.value;
      if (collectionId != null) {
        final all = await _collectionRepository.getBookmarksInCollection(
          collectionId,
        );
        bookmarks.value = all
            .where(
              (b) =>
                  b.title.toLowerCase().contains(query.toLowerCase()) ||
                  b.url.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      } else {
        bookmarks.value = await _repository.fetchBookmarks(query: query);
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> filterByCollection(int? collectionId) async {
    selectedCollectionId.value = collectionId;
    await load();
  }

  Future<void> add(BookmarkModel bookmark) async {
    try {
      final created = await _repository.createBookmark(bookmark);
      bookmarks.value = [...bookmarks.value, created];
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> update(BookmarkModel bookmark) async {
    try {
      final updated = await _repository.updateBookmark(bookmark);
      bookmarks.value = bookmarks.value
          .map((b) => b.id == updated.id ? updated : b)
          .toList();
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> delete(int id) async {
    try {
      await _repository.deleteBookmark(id);
      bookmarks.value = bookmarks.value.where((b) => b.id != id).toList();
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
