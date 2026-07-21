import 'package:flutter_test/flutter_test.dart';
import 'package:rover_explorer/models/file_entry.dart';

FileEntry entry(String name, {bool isDir = false, int size = 0}) => FileEntry(
  path: '/tmp/$name',
  name: name,
  isDir: isDir,
  size: size,
  modified: DateTime(2026, 7, 17, 14, 5),
);

void main() {
  group('FileEntry formatting', () {
    test('folders report no size and a folder type', () {
      final e = entry('Documents', isDir: true);
      expect(e.sizeLabel, '');
      expect(e.typeLabel, 'File Folder');
      expect(e.extension, '');
    });

    test('byte sizes scale through the units', () {
      expect(entry('a', size: 512).sizeLabel, '512 B');
      expect(entry('a', size: 2048).sizeLabel, '2.0 KB');
      expect(entry('a', size: 5 * 1024 * 1024).sizeLabel, '5.0 MB');
      expect(entry('a', size: 3 * 1024 * 1024 * 1024).sizeLabel, '3.00 GB');
    });

    test('type label comes from the extension', () {
      expect(entry('song.mp3').typeLabel, 'MP3 File');
      expect(entry('README').typeLabel, 'File');
      expect(entry('Report.PDF').extension, '.pdf');
    });

    test('modified label uses a 12-hour clock', () {
      expect(entry('a').modifiedLabel, '17/07/2026 2:05 PM');
      final midnight = FileEntry(
        path: '/tmp/b',
        name: 'b',
        isDir: false,
        size: 0,
        modified: DateTime(2026, 1, 2, 0, 30),
      );
      expect(midnight.modifiedLabel, '02/01/2026 12:30 AM');
    });
  });

  group('kindOf', () {
    test('classifies entries by extension', () {
      expect(kindOf('x', true), FileKind.folder);
      expect(kindOf('a.png', false), FileKind.image);
      expect(kindOf('a.FLAC', false), FileKind.audio);
      expect(kindOf('a.mkv', false), FileKind.video);
      expect(kindOf('a.pdf', false), FileKind.document);
      expect(kindOf('a.dart', false), FileKind.code);
      expect(kindOf('a.zip', false), FileKind.archive);
      expect(kindOf('a.AppImage', false), FileKind.exe);
      expect(kindOf('a.unknownext', false), FileKind.generic);
    });
  });
}
