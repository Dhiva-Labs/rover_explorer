import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rover_explorer/screens/explorer_screen.dart';
import 'package:rover_explorer/services/search_index.dart';
import 'package:rover_explorer/widgets/search_pane.dart';

/// Keyboard focus between the file list, the Search Companion's query box
/// and the address bar (issue #4).
void main() {
  late Directory root;
  late Directory docs;
  late SearchIndexService index;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('rover_explorer_test_');
    docs = Directory(p.join(root.path, 'docs'))..createSync();
    File(p.join(docs.path, 'notes.txt')).writeAsStringSync('x');
    index = SearchIndexService();
    await index.start(
      roots: [root.path],
      cacheFile: p.join(root.path, '.cache', 'index.txt'),
    );
    await index.status
        .firstWhere((s) => !s.scanning && s.count > 0)
        .timeout(const Duration(seconds: 20));
  });

  tearDown(() {
    index.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> pumpExplorer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorerScreen(index: index, initialPath: docs.path),
        ),
      ),
    );
    await tester.pump();
  }

  // The address bar is the first text field in the tree; the query box lives
  // inside the search pane.
  TextField addressBar(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);
  final queryBox = find.descendant(
    of: find.byType(SearchPane),
    matching: find.byType(TextField),
  );

  Future<void> pressCtrlF(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Backspace in the file list goes up one folder', (tester) async {
    await pumpExplorer(tester);
    expect(addressBar(tester).controller!.text, docs.path);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(addressBar(tester).controller!.text, root.path);
  });

  testWidgets('Ctrl+F opens the Search Companion with the cursor in the query '
      'box', (tester) async {
    await pumpExplorer(tester);
    await pressCtrlF(tester);

    expect(find.text('Search Companion'), findsOneWidget);
    expect(tester.widget<TextField>(queryBox).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Backspace in the query box deletes a character instead of '
      'going up a folder', (tester) async {
    await pumpExplorer(tester);
    await pressCtrlF(tester);

    await tester.enterText(queryBox, 'notes');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(tester.widget<TextField>(queryBox).controller!.text, 'note');
    expect(addressBar(tester).controller!.text, docs.path);
    expect(find.text('Search Companion'), findsOneWidget);
  });

  testWidgets('Backspace in the address bar edits the path', (tester) async {
    await pumpExplorer(tester);
    final address = find.byType(TextField).first;
    await tester.tap(address);
    await tester.pump();
    // The cursor goes to the end of the path, like a click after the text.
    addressBar(tester).controller!.selection = TextSelection.collapsed(
      offset: docs.path.length,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final typed = addressBar(tester).controller!.text;
    expect(typed, docs.path.substring(0, docs.path.length - 1));
  });

  testWidgets('closing the pane hands the keyboard back to the file list', (
    tester,
  ) async {
    await pumpExplorer(tester);
    await pressCtrlF(tester);
    await tester.enterText(queryBox, 'note');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Search Companion'), findsNothing);

    // Without a click anywhere, Backspace works again as "up one level"...
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(addressBar(tester).controller!.text, root.path);

    // ...and Ctrl+F reopens the pane, focused.
    await pressCtrlF(tester);
    expect(find.text('Search Companion'), findsOneWidget);
    expect(tester.widget<TextField>(queryBox).focusNode!.hasFocus, isTrue);
  });
}
