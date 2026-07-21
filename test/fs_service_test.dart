import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rover_explorer/services/fs_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rover_fs_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('list hides dotfiles unless asked', () {
    File(p.join(root.path, 'visible.txt')).writeAsStringSync('hi');
    File(p.join(root.path, '.hidden')).writeAsStringSync('shh');
    Directory(p.join(root.path, 'sub')).createSync();

    final shown = FsService.list(root.path).map((e) => e.name).toList();
    expect(shown, containsAll(['visible.txt', 'sub']));
    expect(shown, isNot(contains('.hidden')));

    final all = FsService.list(
      root.path,
      showHidden: true,
    ).map((e) => e.name).toList();
    expect(all, contains('.hidden'));
  });

  test('list reports directories and sizes', () {
    File(p.join(root.path, 'data.bin')).writeAsBytesSync(List.filled(1234, 7));
    Directory(p.join(root.path, 'folder')).createSync();

    final entries = {for (final e in FsService.list(root.path)) e.name: e};
    expect(entries['folder']!.isDir, isTrue);
    expect(entries['data.bin']!.isDir, isFalse);
    expect(entries['data.bin']!.size, 1234);
  });

  test('newFolder avoids collisions', () async {
    final first = await FsService.newFolder(root.path);
    final second = await FsService.newFolder(root.path);
    expect(p.basename(first), 'New Folder');
    expect(p.basename(second), 'New Folder (2)');
    expect(Directory(second).existsSync(), isTrue);
  });

  test('rename keeps the file in the same parent', () async {
    final f = File(p.join(root.path, 'before.txt'))..writeAsStringSync('x');
    await FsService.rename(f.path, 'after.txt');
    expect(File(p.join(root.path, 'after.txt')).existsSync(), isTrue);
    expect(f.existsSync(), isFalse);
  });

  test('copyInto duplicates files and whole trees', () async {
    final src = Directory(p.join(root.path, 'src'))..createSync();
    File(p.join(src.path, 'a.txt')).writeAsStringSync('alpha');
    Directory(p.join(src.path, 'nested')).createSync();
    File(p.join(src.path, 'nested', 'b.txt')).writeAsStringSync('beta');
    final dest = Directory(p.join(root.path, 'dest'))..createSync();

    await FsService.copyInto(src.path, dest.path);

    expect(File(p.join(dest.path, 'src', 'a.txt')).readAsStringSync(), 'alpha');
    expect(
      File(p.join(dest.path, 'src', 'nested', 'b.txt')).readAsStringSync(),
      'beta',
    );
    expect(File(p.join(src.path, 'a.txt')).existsSync(), isTrue);
  });

  test('copyInto de-duplicates when pasting into the same folder', () async {
    final f = File(p.join(root.path, 'note.txt'))..writeAsStringSync('n');
    final copy = await FsService.copyInto(f.path, root.path);
    expect(p.basename(copy), 'Copy of note.txt');
    expect(File(copy).existsSync(), isTrue);
    expect(f.existsSync(), isTrue);
  });

  test('moveInto relocates and leaves nothing behind', () async {
    final f = File(p.join(root.path, 'move-me.txt'))..writeAsStringSync('m');
    final dest = Directory(p.join(root.path, 'target'))..createSync();

    final moved = await FsService.moveInto(f.path, dest.path);

    expect(moved, p.join(dest.path, 'move-me.txt'));
    expect(File(moved).existsSync(), isTrue);
    expect(f.existsSync(), isFalse);
  });

  test('delete removes files and directory trees', () async {
    final dir = Directory(p.join(root.path, 'doomed'))..createSync();
    File(p.join(dir.path, 'child.txt')).writeAsStringSync('bye');
    await FsService.delete(dir.path);
    expect(dir.existsSync(), isFalse);
  });

  test('homeDir and drives resolve to real locations', () {
    expect(FsService.homeDir, isNotEmpty);
    final drives = FsService.drives();
    expect(drives, isNotEmpty);
    expect(Directory(drives.first).existsSync(), isTrue);
  });
}
