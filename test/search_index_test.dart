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
    // Shares the prefix of 'photos': must stay out of a search in 'photos'.
    Directory(p.join(root.path, 'photos-old')).createSync();
    Directory(p.join(root.path, 'reports')).createSync();
    File(p.join(root.path, 'photos', 'holiday.png')).writeAsStringSync('x');
    File(p.join(root.path, 'photos-old', 'holiday.gif')).writeAsStringSync('x');
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
    expect(index.lastStatus.count, greaterThanOrEqualTo(9));
    expect(index.lastStatus.scanning, isFalse);
  });

  test('substring query finds every matching name', () async {
    final r = await run('holiday');
    final names = r.hits.map((h) => h.name).toList();
    expect(r.totalMatches, 4);
    expect(
      names,
      containsAll([
        'holiday.png',
        'holiday-2.JPG',
        'holiday.pdf',
        'holiday.gif',
      ]),
    );
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
    expect(pics.hits.map((h) => h.name), hasLength(3));

    final docs = await run('holiday', kind: SearchKind.documents);
    expect(docs.hits.single.name, 'holiday.pdf');

    final music = await run('song', kind: SearchKind.music);
    expect(music.hits.single.name, 'song.mp3');
  });

  test('folder filter returns only directories', () async {
    final r = await run('photos', kind: SearchKind.folders);
    expect(r.hits.every((h) => h.isDir), isTrue);
    expect(
      r.hits.map((h) => h.name),
      unorderedEquals(['photos', 'photos-old']),
    );
  });

  test('underPath scopes the search to one folder', () async {
    final scoped = await run('holiday', under: p.join(root.path, 'reports'));
    expect(scoped.hits.single.name, 'holiday.pdf');
  });

  test('extra words must also match somewhere in the path', () async {
    final r = await run('holiday reports');
    expect(r.hits.single.name, 'holiday.pdf');
  });

  test('word order does not change the results', () async {
    final a = await run('holiday reports');
    final b = await run('reports holiday');
    expect(a.hits.single.name, 'holiday.pdf');
    expect(b.hits.single.name, 'holiday.pdf');
    expect(b.totalMatches, a.totalMatches);
  });

  test('"only in current folder" ignores folders sharing the prefix', () async {
    final r = await run('holiday', under: p.join(root.path, 'photos'));
    expect(
      r.hits.map((h) => h.name),
      unorderedEquals(['holiday.png', 'holiday-2.JPG']),
    );
  });

  test('"only in current folder" works outside the indexed roots', () async {
    final other = Directory.systemTemp.createTempSync('rover_outside_');
    try {
      File(p.join(other.path, 'holiday-abroad.txt')).writeAsStringSync('x');
      final r = await run('holiday', under: other.path);
      expect(r.hits.single.name, 'holiday-abroad.txt');
    } finally {
      other.deleteSync(recursive: true);
    }
  });

  test('a rename reported by the app is searchable without a rescan', () async {
    final old = p.join(root.path, 'reports', 'budget.xlsx');
    final renamed = p.join(root.path, 'reports', 'forecast.xlsx');
    File(old).renameSync(renamed);
    index.changed(removed: [old], added: [renamed]);

    final r = await run('forecast');
    expect(r.hits.single.path, renamed);
    final gone = await run('budget');
    expect(gone.hits, isEmpty);
  });

  test('a folder removed by the app takes everything under it', () async {
    final photos = p.join(root.path, 'photos');
    Directory(photos).deleteSync(recursive: true);
    index.changed(removed: [photos]);

    final r = await run('holiday');
    expect(
      r.hits.map((h) => h.name),
      unorderedEquals(['holiday.pdf', 'holiday.gif']),
    );
  });

  test('a folder added by the app is indexed with its contents', () async {
    final archive = Directory(p.join(root.path, 'archive'))..createSync();
    File(p.join(archive.path, 'holiday-1999.zip')).writeAsStringSync('x');
    index.changed(added: [archive.path]);

    final r = await run('1999');
    expect(r.hits.single.name, 'holiday-1999.zip');
    final folders = await run('archive', kind: SearchKind.folders);
    expect(folders.hits.single.isDir, isTrue);
  });

  test('a query during the first scan sees what was found so far', () async {
    // No cache yet and more entries than one scan batch (4000), so the
    // query is handled while the scan is still running.
    final big = Directory.systemTemp.createTempSync('rover_first_run_');
    for (var i = 0; i < 4500; i++) {
      File(p.join(big.path, 'bulk-$i.txt')).writeAsStringSync('');
    }
    final first = SearchIndexService();
    var scanned = false;
    final done = first.status.firstWhere((s) {
      if (s.scanning) scanned = true;
      return scanned && !s.scanning;
    });
    try {
      await first.start(
        roots: [big.path],
        cacheFile: p.join(big.path, '.cache', 'index.txt'),
      );
      final id = first.query('bulk');
      final r = await first.results
          .firstWhere((x) => x.queryId == id)
          .timeout(const Duration(seconds: 10));
      expect(r.totalMatches, greaterThan(0));
      expect(r.hits.first.name, startsWith('bulk-'));
      await done.timeout(const Duration(seconds: 30));
    } finally {
      first.dispose();
      big.deleteSync(recursive: true);
    }
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
}
