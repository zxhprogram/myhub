import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/models/bookmark_model.dart';
import 'package:nexus_hub_app/presentation/pages/bookmarks_page.dart';
import 'package:nexus_hub_app/presentation/states/bookmarks_state.dart';
import 'package:nexus_hub_app/presentation/states/collections_state.dart';

/// Guards the Signals `SignalEffectException` crash that fired when opening the
/// Bookmarks page in the desktop build.
///
/// Root cause (preact_signals 6.3.1, batches): a state's `load()` writes
/// `error.value` from an async continuation. If that write re-flushes an active
/// effect whose callback throws (e.g. `ScaffoldMessenger.of` invoked after the
/// window/page was deactivated), preact_signals stashes the throw in
/// `endBatch()` and re-throws it *after* returning — routing a raw
/// `SignalEffectException` to the zone and "Unhandled Exception"-crashing the
/// app.
///
/// The page must never throw out of the effects, whether the load fails while
/// open or completes after the page is disposed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester, {BookmarksState? state}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarksPage(
            state: state ??
                (BookmarksState()
                  ..bookmarks.value = [
                    BookmarkModel(
                      id: 1,
                      title: 'Sample',
                      url: 'https://example.com',
                      tags: const [],
                      category: 'Dev',
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                  ]),
            collectionsState: CollectionsState(),
          ),
        ),
      ),
    );
  }

  testWidgets('a load error renders inline through Watch', (tester) async {
    await pumpPage(tester, state: BookmarksState()..setErrorState('boom'));
    // Let initState's async load() settle (it wipes then re-publishes the
    // error, and drives isLoading through true → false).
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('boom'), findsWidgets);
  });

  testWidgets('an error completing after the page is disposed throws nothing',
      (tester) async {
    final state = BookmarksState();
    state.isLoading.value = true; // Represents an in-flight load().
    await pumpPage(tester, state: state);
    await tester.pump();

    // Tear the page down mid-load (like closing the desktop window).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // The load completes after disposal. Previously the error effect's snackbar
    // call (with the page's messengers torn down) threw inside the signals
    // batch, producing the uncaught SignalEffectException.
    state.isLoading.value = false;
    state.error.value = 'late boom';
    await tester.pump();

    // Nothing rendered, and — the real assertion — this test would have failed
    // on the zone exception above if the crash were still present.
    expect(find.textContaining('boom'), findsNothing);
  });
}

extension on BookmarksState {
  /// Publishes an error synchronously, mimicking a completed load() failure
  /// without hitting the network or Hive.
  void setErrorState(String message) {
    isLoading.value = true;
    error.value = message;
    isLoading.value = false;
  }
}