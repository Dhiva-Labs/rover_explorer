import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rover_explorer/screens/explorer_screen.dart';
import 'package:rover_explorer/services/search_index.dart';
import 'package:rover_explorer/widgets/file_list.dart';
import 'package:rover_explorer/widgets/search_pane.dart';

/// The search flow driven through the real explorer screen and a real
/// indexer isolate over a temporary tree.
void main() {
  late Directory root;
  late SearchIndexService index;

  String docs() => p.join(root.path, 'docs');

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('rover_ui_');
      for (final d in ['docs', 'photos', 'holiday']) {
        Directory(p.join(root.path, d)).createSync();
      }
      for (final f in [
        'docs/holiday.pdf',
        'docs/report.txt',
        'photos/holiday.png',
        'photos/holiday-2.jpg',
        'song.mp3',
      ]) {
        File(p.join(root.path, f)).writeAsStringSync('x');
      }
      index = SearchIndexService();
      await index.start(
        roots: [root.path],
        cacheFile: p.join(root.path, '.cache', 'index.txt'),
      );
      await index.status
          .firstWhere((s) => !s.scanning && s.count > 0)
          .timeout(const Duration(seconds: 20));
    });
    addTearDown(() {
      index.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorerScreen(index: index, initialPath: docs()),
        ),
      ),
    );
    await tester.pump();
  }

  TextEditingController address(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!;

  Finder queryBox() => find.descendant(
    of: find.byType(SearchPane),
    matching: find.byType(TextField),
  );

  TextEditingController query(WidgetTester tester) =>
      tester.widget<TextField>(queryBox()).controller!;

  bool queryFocused(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(of: queryBox(), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  Finder inList(String text) =>
      find.descendant(of: find.byType(FileListView), matching: find.text(text));

  bool showingResults() => find.text('In Folder').evaluate().isNotEmpty;

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    await tester.pump();
  }

  Future<void> openSearch(WidgetTester tester) => chord(
    tester,
    LogicalKeyboardKey.keyF,
    modifier: LogicalKeyboardKey.controlLeft,
  );

  /// Lets the debounce fire and the isolate answer, until [until] holds (or
  /// for a fixed stretch when it is null).
  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (until != null && until()) return;
    }
    if (until != null) fail('timed out waiting for the search to settle');
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(queryBox(), text);
    await settle(tester, until: showingResults);
  }

  testWidgets('Ctrl+F opens the pane with the query box focused', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byType(SearchPane), findsNothing);
    await openSearch(tester);
    expect(find.byType(SearchPane), findsOneWidget);
    expect(queryFocused(tester), isTrue);
  });

  testWidgets('Backspace in the query box deletes, it does not go up', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await tester.enterText(queryBox(), 'holiday');
    await chord(tester, LogicalKeyboardKey.backspace);
    await chord(tester, LogicalKeyboardKey.backspace);
    expect(query(tester).text, 'holid');
    expect(address(tester).text, docs());
  });

  testWidgets('Backspace in the address bar edits the path', (tester) async {
    await boot(tester);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '/tmp/abc');
    await chord(tester, LogicalKeyboardKey.backspace);
    expect(address(tester).text, '/tmp/ab');
    expect(find.text('report.txt'), findsOneWidget, reason: 'still in docs');
  });

  testWidgets('Backspace in the file list goes up one folder', (tester) async {
    await boot(tester);
    await tester.tap(inList('report.txt'));
    await tester.pump(const Duration(milliseconds: 400));
    await chord(tester, LogicalKeyboardKey.backspace);
    expect(address(tester).text, root.path);
  });

  testWidgets('typing searches the whole tree, best match first', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'holiday');

    for (final n in [
      'holiday',
      'holiday.pdf',
      'holiday.png',
      'holiday-2.jpg',
    ]) {
      expect(inList(n), findsOneWidget, reason: n);
    }
    // Relevance order: the exact name first, then prefix matches by length.
    final ys = [
      'holiday',
      'holiday.pdf',
      'holiday-2.jpg',
    ].map((n) => tester.getTopLeft(inList(n)).dy).toList();
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
    expect(find.textContaining('I found 4 items'), findsOneWidget);
  });

  testWidgets('wildcards work from the query box', (tester) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, '*.png');
    expect(inList('holiday.png'), findsOneWidget);
    expect(inList('holiday.pdf'), findsNothing);
  });

  testWidgets('deleting the query back to empty clears the results', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'so');
    expect(inList('song.mp3'), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.backspace);
    await chord(tester, LogicalKeyboardKey.backspace);
    await settle(tester, until: () => !showingResults());
    expect(query(tester).text, isEmpty);
    expect(inList('report.txt'), findsOneWidget, reason: 'back to docs');
  });

  testWidgets('Clear right after typing never brings stale results back', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await tester.enterText(queryBox(), 'holiday');
    // Let the debounce send the query, then clear before the answer lands.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await settle(tester);
    expect(showingResults(), isFalse);
    expect(query(tester).text, isEmpty);
    expect(queryFocused(tester), isTrue);
  });

  testWidgets('Escape clears the query', (tester) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'song');
    await chord(tester, LogicalKeyboardKey.escape);
    await settle(tester, until: () => !showingResults());
    expect(query(tester).text, isEmpty);
  });

  testWidgets('Ctrl+F while open puts the cursor back with text selected', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'holiday');
    await tester.tap(inList('holiday.pdf'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(queryFocused(tester), isFalse, reason: 'clicking a result');

    await openSearch(tester);
    expect(queryFocused(tester), isTrue);
    final sel = query(tester).selection;
    expect(sel.start, 0);
    expect(sel.end, 'holiday'.length);
  });

  testWidgets('Down moves to the first result and Enter opens it', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'photos');
    await chord(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('1 selected'), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.enter);
    expect(address(tester).text, p.join(root.path, 'photos'));
    expect(inList('holiday.png'), findsOneWidget);
  });

  testWidgets('arrow keys walk the results', (tester) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'holiday');
    await chord(tester, LogicalKeyboardKey.arrowDown); // first
    await chord(tester, LogicalKeyboardKey.arrowDown); // second
    await chord(tester, LogicalKeyboardKey.arrowDown); // third
    await chord(tester, LogicalKeyboardKey.arrowUp); // second
    // (No Enter here: on a file it would launch the desktop's viewer.)
    final list = tester.widget<FileListView>(find.byType(FileListView));
    final state = tester.state<FileListViewState>(find.byType(FileListView));
    expect(state.selectedEntries.single.path, list.entries[1].path);
    expect(list.entries.first.name, 'holiday', reason: 'exact match first');
  });

  testWidgets('closing the pane hands the keyboard back to the list', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await tester.enterText(queryBox(), 'holiday');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SearchPane), findsNothing);
    await chord(tester, LogicalKeyboardKey.backspace);
    expect(address(tester).text, root.path);
  });

  testWidgets('going up while a search is in flight keeps the folder view', (
    tester,
  ) async {
    await boot(tester);
    await openSearch(tester);
    await tester.enterText(queryBox(), 'holiday');
    await tester.pump(const Duration(milliseconds: 200));
    await chord(
      tester,
      LogicalKeyboardKey.arrowUp,
      modifier: LogicalKeyboardKey.altLeft,
    );
    await settle(tester);
    expect(address(tester).text, root.path);
    expect(showingResults(), isFalse);
  });

  testWidgets('a result deleted outside the app is not shown', (tester) async {
    await boot(tester);
    File(p.join(root.path, 'photos', 'holiday-2.jpg')).deleteSync();
    await openSearch(tester);
    await search(tester, 'holiday');
    expect(inList('holiday-2.jpg'), findsNothing);
    expect(find.textContaining('I found 3 items'), findsOneWidget);
  });

  testWidgets('a rename from the results updates them at once', (tester) async {
    await boot(tester);
    await openSearch(tester);
    await search(tester, 'report');
    await tester.tap(inList('report.txt'));
    await tester.pump(const Duration(milliseconds: 400));
    await chord(tester, LogicalKeyboardKey.f2);
    await tester.pump(const Duration(milliseconds: 300));

    // Typing in the dialog — Backspace included — edits its field.
    final field = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'reports.txt');
    await chord(tester, LogicalKeyboardKey.backspace);
    expect(tester.widget<TextField>(field).controller!.text, 'reports.tx');
    await tester.enterText(field, 'report-final.txt');
    await tester.tap(find.text('OK'));
    await tester.pump();
    await settle(
      tester,
      until: () => inList('report-final.txt').evaluate().isNotEmpty,
    );
    expect(inList('report.txt'), findsNothing);
    expect(
      File(p.join(root.path, 'docs', 'report-final.txt')).existsSync(),
      isTrue,
    );
  });
}
