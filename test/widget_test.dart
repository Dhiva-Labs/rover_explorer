import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover_explorer/app_info.dart';
import 'package:rover_explorer/models/file_entry.dart';
import 'package:rover_explorer/widgets/file_list.dart';
import 'package:rover_explorer/widgets/rover_dog.dart';
import 'package:rover_explorer/widgets/xp_menu_bar.dart';

List<FileEntry> sampleEntries() => [
  FileEntry(
    path: '/tmp/Zebra',
    name: 'Zebra',
    isDir: true,
    size: 0,
    modified: DateTime(2026, 3, 1),
  ),
  FileEntry(
    path: '/tmp/apple.txt',
    name: 'apple.txt',
    isDir: false,
    size: 2048,
    modified: DateTime(2026, 2, 1),
  ),
  FileEntry(
    path: '/tmp/beta.mp3',
    name: 'beta.mp3',
    isDir: false,
    size: 4096,
    modified: DateTime(2026, 1, 1),
  ),
];

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
);

void main() {
  testWidgets('file list renders entries with folders grouped first', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FileListView(
          entries: sampleEntries(),
          mode: ViewMode.details,
          onOpen: (_) {},
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Zebra'), findsOneWidget);
    expect(find.text('apple.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('File Folder'), findsOneWidget);

    final folderY = tester.getTopLeft(find.text('Zebra')).dy;
    final fileY = tester.getTopLeft(find.text('apple.txt')).dy;
    expect(folderY, lessThan(fileY), reason: 'folders sort above files');
  });

  testWidgets('tapping an entry selects it and reports the selection', (
    tester,
  ) async {
    var reported = <FileEntry>[];
    await tester.pumpWidget(
      host(
        FileListView(
          entries: sampleEntries(),
          mode: ViewMode.details,
          onOpen: (_) {},
          onAction: (_, _) {},
          onSelectionChanged: (sel) => reported = sel,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('apple.txt'));
    // Rows accept double-clicks too, so a single tap only resolves once the
    // double-tap window has closed.
    await tester.pump(const Duration(milliseconds: 400));

    expect(reported.map((e) => e.name), ['apple.txt']);
  });

  testWidgets('double-tapping an entry opens it', (tester) async {
    FileEntry? opened;
    await tester.pumpWidget(
      host(
        FileListView(
          entries: sampleEntries(),
          mode: ViewMode.details,
          onOpen: (e) => opened = e,
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    final target = find.text('Zebra');
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(target);
    await tester.pump();

    expect(opened?.name, 'Zebra');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('icons view lays entries out in a grid', (tester) async {
    await tester.pumpWidget(
      host(
        FileListView(
          entries: sampleEntries(),
          mode: ViewMode.icons,
          onOpen: (_) {},
          onAction: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('beta.mp3'), findsOneWidget);
  });

  testWidgets('menu bar opens a drop-down and fires the chosen entry', (
    tester,
  ) async {
    var fired = false;
    await tester.pumpWidget(
      host(
        XpMenuBar(
          menus: [
            XpMenu(
              'File',
              () => [XpMenuEntry('Close', onTap: () => fired = true)],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(fired, isTrue);
  });

  testWidgets('the companion paints in every mood without throwing', (
    tester,
  ) async {
    for (final mood in DogMood.values) {
      await tester.pumpWidget(host(Center(child: RoverDog(mood: mood))));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(RoverDog), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('version metadata is consistent', () {
    expect(AppInfo.name, 'Rover Explorer');
    expect(AppInfo.vendor, 'Dhiva Labs');
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(AppInfo.version), isTrue);
    expect(AppInfo.fullVersion, contains(AppInfo.version));
  });
}
