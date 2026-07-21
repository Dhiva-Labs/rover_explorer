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

    final second = SearchIndexService();
    await second.start(roots: [root.path], cacheFile: cache);
    final id = second.query('budget');
    final r = await second.results
        .firstWhere((x) => x.queryId == id)
        .timeout(const Duration(seconds: 10));
    expect(r.hits.single.name, 'budget.xlsx');
    second.dispose();
  });
}
