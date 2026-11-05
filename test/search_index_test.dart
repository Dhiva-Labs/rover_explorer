import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rover_explorer/services/search_index.dart';

/// End-to-end exercise of the indexer isolate against a temporary tree.
void main() {
  late Directory root;
  late SearchIndexService index;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('rover_index_test_');
    Directory(p.join(root.path, 'photos')).createSync();
    Directory(p.join(root.path, 'reports')).createSync();
    File(p.join(root.path, 'photos', 'holiday.png')).writeAsStringSync('x');
    File(p.join(root.path, 'photos', 'holiday-2.JPG')).writeAsStringSync('x');
    File(p.join(root.path, 'reports', 'holiday.pdf')).writeAsStringSync('x');
    File(p.join(root.path, 'reports', 'budget.xlsx')).writeAsStringSync('x');
    File(p.join(root.path, 'song.mp3')).writeAsStringSync('x');
    File(p.join(root.path, '.dotfile')).writeAsStringSync('x');

    index = SearchIndexService();
    await index.start(
      roots: [root.path],
      cacheFile: p.join(root.path, '.cache', 'index.txt'),
    );
    // Wait for the first full scan to finish.
    await index.status
        .firstWhere((s) => !s.scanning && s.count > 0)
        .timeout(const Duration(seconds: 20));
  });

  tearDown(() {
    index.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<SearchResults> run(
    String text, {
    SearchKind kind = SearchKind.all,
    String? under,
  }) {
    final id = index.query(text, kind: kind, underPath: under);
    return index.results
        .firstWhere((r) => r.queryId == id)
        .timeout(const Duration(seconds: 10));
  }

  test('indexes the tree and skips dotfiles', () {
    expect(index.lastStatus.count, greaterThanOrEqualTo(7));
    expect(index.lastStatus.scanning, isFalse);
  });

  test('substring query finds every matching name', () async {
    final r = await run('holiday');
    final names = r.hits.map((h) => h.name).toList();
    expect(r.totalMatches, 3);
    expect(names, containsAll(['holiday.png', 'holiday-2.JPG', 'holiday.pdf']));
  });

  test('queries are case-insensitive', () async {
    final r = await run('HOLIDAY.PNG');
    expect(r.hits.single.name, 'holiday.png');
  });

  test('ranking puts exact and prefix matches first', () async {
    final r = await run('holiday');
    // 'holiday.png' / 'holiday.pdf' are prefix matches on the shorter names,
    // so they must outrank the longer 'holiday-2.JPG'.
    expect(r.hits.first.name.startsWith('holiday.'), isTrue);
  });

  test('kind filters restrict results by extension', () async {
    final pics = await run('holiday', kind: SearchKind.pictures);
    expect(pics.hits.map((h) => h.name), hasLength(2));

    final docs = await run('holiday', kind: SearchKind.documents);
    expect(docs.hits.single.name, 'holiday.pdf');

    final music = await run('song', kind: SearchKind.music);
    expect(music.hits.single.name, 'song.mp3');
  });

  test('folder filter returns only directories', () async {
    final r = await run('photos', kind: SearchKind.folders);
    expect(r.hits.single.isDir, isTrue);
    expect(r.hits.single.name, 'photos');
  });

  test('underPath scopes the search to one folder', () async {
    final scoped = await run('holiday', under: p.join(root.path, 'reports'));
    expect(scoped.hits.single.name, 'holiday.pdf');
  });

  test('extra words must also match somewhere in the path', () async {
    final r = await run('holiday reports');
    expect(r.hits.single.name, 'holiday.pdf');
  });

  test('hidden files never enter the index', () async {
    final r = await run('dotfile');
    expect(r.hits, isEmpty);
  });

  test('an empty query returns nothing', () async {
    final r = await run('   ');
    expect(r.hits, isEmpty);
    expect(r.totalMatches, 0);
  });

  test('a fresh service loads the cached index without rescanning', () async {
    final cache = p.join(root.path, '.cache', 'index.txt');
    expect(File(cache).existsSync(), isTrue);

    // Starting a service also starts a rescan, which rewrites the cache. Wait
    // for it before disposing: killing the isolate mid-write leaves the file
    // open, and Windows then refuses to delete the folder in tearDown.
    final second = SearchIndexService();
    var scanned = false;
    final rescanned = second.status.firstWhere((s) {
      if (s.scanning) scanned = true;
      return scanned && !s.scanning;
    });
    await second.start(roots: [root.path], cacheFile: cache);
    final id = second.query('budget');
    final r = await second.results
        .firstWhere((x) => x.queryId == id)
        .timeout(const Duration(seconds: 10));
    expect(r.hits.single.name, 'budget.xlsx');
    await rescanned.timeout(const Duration(seconds: 10));
    second.dispose();
  });

  test('the first finished scan marks the index complete', () {
    expect(index.lastStatus.complete, isTrue);
  });

  test('word order does not matter', () async {
    final a = await run('reports holiday');
    final b = await run('holiday reports');
    expect(a.hits.single.path, b.hits.single.path);
  });

  test('wildcards match whole names', () async {
    final r = await run('*.png');
    expect(r.hits.single.name, 'holiday.png');
    final jpg = await run('holiday-?.jpg');
    expect(jpg.hits.single.name, 'holiday-2.JPG');
  });

  group('touch keeps the index in step with app file operations', () {
    test('a rename shows up under the new name at once', () async {
      final from = p.join(root.path, 'reports', 'budget.xlsx');
      final to = p.join(root.path, 'reports', 'forecast.xlsx');
      File(from).renameSync(to);
      index.touch(removed: [from], added: [to]);
      expect((await run('forecast')).hits.single.path, to);
      expect((await run('budget')).hits, isEmpty);
    });

    test('deleting a folder drops everything inside it', () async {
      final photos = p.join(root.path, 'photos');
      Directory(photos).deleteSync(recursive: true);
      index.touch(removed: [photos]);
      final r = await run('holiday');
      expect(r.hits.single.name, 'holiday.pdf');
      expect(r.totalMatches, 1);
    });

    test('a new folder is indexed together with its contents', () async {
      final added = p.join(root.path, 'new');
      Directory(p.join(added, 'inner')).createSync(recursive: true);
      File(p.join(added, 'inner', 'deep.txt')).writeAsStringSync('x');
      index.touch(added: [added]);
      expect((await run('deep')).hits.single.name, 'deep.txt');
      expect((await run('inner')).hits.single.isDir, isTrue);
    });

    test('touching the same path twice does not duplicate it', () async {
      final f = p.join(root.path, 'twice.txt');
      File(f).writeAsStringSync('x');
      index.touch(added: [f]);
      index.touch(added: [f]);
      expect((await run('twice')).totalMatches, 1);
    });

    test('hidden and out-of-tree paths stay out of the index', () async {
      final secret = p.join(root.path, '.secret');
      Directory(secret).createSync();
      File(p.join(secret, 'key.txt')).writeAsStringSync('x');
      final outside = Directory.systemTemp.createTempSync('rover_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final stray = p.join(outside.path, 'stray.txt');
      File(stray).writeAsStringSync('x');
      index.touch(added: [secret, stray]);
      expect((await run('key')).hits, isEmpty);
      expect((await run('stray')).hits, isEmpty);
    });
  });

  group('"only in current folder" outside the index', () {
    test('a folder outside the indexed roots is walked on demand', () async {
      final outside = Directory.systemTemp.createTempSync('rover_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      Directory(p.join(outside.path, 'sub')).createSync();
      File(p.join(outside.path, 'sub', 'faraway.txt')).writeAsStringSync('x');

      final scoped = await run('faraway', under: outside.path);
      expect(
        scoped.hits.single.path,
        p.join(outside.path, 'sub', 'faraway.txt'),
      );
      // The whole-index search still only covers the roots.
      expect((await run('faraway')).hits, isEmpty);
    });

    test('a hidden folder inside the root is walked on demand', () async {
      final config = p.join(root.path, '.config');
      Directory(p.join(config, 'app')).createSync(recursive: true);
      File(p.join(config, 'app', 'settings.json')).writeAsStringSync('{}');

      final r = await run('settings', under: config);
      expect(r.hits.single.name, 'settings.json');
      expect((await run('settings')).hits, isEmpty);
    });
  });

  test('rapid queries: a query replaced while waiting is skipped', () async {
    final seen = <int>[];
    final sub = index.results.listen((r) => seen.add(r.queryId));
    final first = index.query('holiday');
    final replaced = index.query('budget');
    final last = index.query('song');
    final r = await index.results
        .firstWhere((x) => x.queryId == last)
        .timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect(r.hits.single.name, 'song.mp3');
    expect(seen, contains(first));
    expect(seen, isNot(contains(replaced)));
  });

  test(
    'a file name with a line break cannot corrupt the cache',
    () async {
      final odd = Directory.systemTemp.createTempSync('rover_odd_');
      addTearDown(() => odd.deleteSync(recursive: true));
      File(p.join(odd.path, 'line\nbreak.txt')).writeAsStringSync('x');
      File(p.join(odd.path, 'plain.txt')).writeAsStringSync('x');
      final cache = p.join(odd.path, '.cache', 'index.txt');

      final svc = SearchIndexService();
      await svc.start(roots: [odd.path], cacheFile: cache);
      await svc.status
          .firstWhere((s) => !s.scanning && s.count > 0)
          .timeout(const Duration(seconds: 20));
      svc.dispose();

      final lines = File(cache).readAsLinesSync();
      expect(lines, ['f${p.join(odd.path, 'plain.txt')}']);
    },
    skip: Platform.isWindows ? 'line breaks are not valid in names' : false,
  );
}
