import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/rss_feed_model.dart';
import '../../data/repositories/rss_repository.dart';

/// Signals-based state for the RSS reader page.
class RssState {
  RssState({RssRepository? repository})
      : _repository = repository ?? RssRepository();

  final RssRepository _repository;

  final Signal<List<RssFeedModel>> feeds = signal<List<RssFeedModel>>([]);
  final Signal<List<RssArticleModel>> articles =
      signal<List<RssArticleModel>>([]);
  final Signal<bool> isLoading = signal<bool>(false);
  final Signal<bool> isRefreshing = signal<bool>(false);
  final Signal<String?> error = signal<String?>(null);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      feeds.value = await _repository.fetchFeeds();
      articles.value = await _repository.fetchArticles();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addFeed({
    String? title,
    required String url,
    String category = '',
  }) async {
    error.value = null;
    try {
      await _repository.addFeed(title: title, url: url, category: category);
      await load();
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> deleteFeed(int feedId) async {
    error.value = null;
    try {
      await _repository.deleteFeed(feedId);
      await load();
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> refresh() async {
    isRefreshing.value = true;
    error.value = null;
    try {
      await _repository.refreshAll();
      await load();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> markRead(int articleId) async {
    try {
      await _repository.markRead(articleId);
      articles.value = articles.value
          .map((a) => a.id == articleId ? a.copyWith(isRead: true) : a)
          .toList();
    } catch (e) {
      error.value = e.toString();
    }
  }
}
