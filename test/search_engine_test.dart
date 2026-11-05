import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover_explorer/services/search_engine.dart';

/// Pure tests of query parsing, matching and ranking — no isolate, no disk.
void main() {
  FileIndex build(Map<String, bool> entries) {
    final idx = FileIndex();
    entries.forEach(idx.add);
    return idx;
  }

  final tree = build({
    '/home/u/projects': true,
    '/home/u/projects/rover_explorer': true,
    '/home/u/projects/rover_explorer/lib': true,
    '/home/u/projects/rover_explorer/lib/main.dart': false,
    '/home/u/projects/rover_explorer/lib/explorer_screen.dart': false,
    '/home/u/projects/rover_explorer/README.md': false,
    '/home/u/projects/other/lib/main.dart': false,
    '/home/u/projects/other/screen': true,
    '/home/u/projects/other/screen/notes.txt': false,
    '/home/u/Pictures': true,
    '/home/u/Pictures/IMG_0001.jpg': false,
    '/home/u/Pictures/IMG_0002.JPG': false,
    '/home/u/Pictures/IMG_12.jpg': false,
    '/home/u/Pictures/holiday photo.png': false,
    '/home/u/Documents/annual report.pdf': false,
    '/home/u/Documents/report-draft.docx': false,
    '/home/u/Documents/report': false,
    '/home/u/Documents/summary_report.pdf': false,
    '/home/u/Documents/misreported.txt': false,
    '/home/u/foo': true,
    '/home/u/foo/a.txt': false,
    '/home/u/foobar': true,
    '/home/u/foobar/a.txt': false,
  });

  List<String> names(
    String q, {
    SearchKind kind = SearchKind.all,
    String? under,
    int limit = 400,
    FileIndex? index,
    bool caseSensitivePaths = true,
    String separator = '/',
  }) {
    final idx = index ?? tree;
    final out = search(
      idx,
      q,
      kind: kind,
      underPath: under,
      limit: limit,
      caseSensitivePaths: caseSensitivePaths,
      separator: separator,
    );
    return [for (final i in out.hits) idx.paths[i]];
  }

  group('matching', () {
    test('word order does not matter', () {
      final a = names('rover_explorer screen');
      final b = names('screen rover_explorer');
      expect(a, ['/home/u/projects/rover_explorer/lib/explorer_screen.dart']);
      expect(b, a);
    });

    test('at least one word must be in the name itself', () {
      // 'notes.txt' sits in a folder called 'screen', but neither word is in
      // its own name, so a search for 'screen other' must not list it.
      expect(
        names('screen other'),
        isNot(contains('/home/u/projects/other/screen/notes.txt')),
      );
      expect(names('screen other'), contains('/home/u/projects/other/screen'));
    });

    test('every word must match somewhere', () {
      expect(names('main rover_explorer'), [
        '/home/u/projects/rover_explorer/lib/main.dart',
      ]);
      expect(names('main nowhere'), isEmpty);
    });

    test('case-insensitive', () {
      expect(names('readme.MD'), ['/home/u/projects/rover_explorer/README.md']);
    });

    test('*.ext wildcard matches the whole name', () {
      expect(names('*.pdf'), hasLength(2));
      expect(
        names('*.pdf'),
        containsAll([
          '/home/u/Documents/annual report.pdf',
          '/home/u/Documents/summary_report.pdf',
        ]),
      );
      // Anchored: '.pdf' in the middle of a name does not count.
      expect(names('*.pd'), isEmpty);
    });

    test('? matches exactly one character', () {
      expect(names('img_????.jpg'), [
        '/home/u/Pictures/IMG_0001.jpg',
        '/home/u/Pictures/IMG_0002.JPG',
      ]);
    });

    test('prefix* and *middle* wildcards', () {
      expect(
        names('report*'),
        containsAll([
          '/home/u/Documents/report-draft.docx',
          '/home/u/Documents/report',
        ]),
      );
      expect(
        names('report*'),
        isNot(contains('/home/u/Documents/misreported.txt')),
      );
      expect(names('*draft*'), ['/home/u/Documents/report-draft.docx']);
    });

    test('wildcards combine with plain words', () {
      expect(names('*.dart rover'), hasLength(2));
      expect(names('*.dart other'), ['/home/u/projects/other/lib/main.dart']);
    });

    test('a lone * filters nothing and is ignored', () {
      expect(names('*'), isEmpty);
      expect(names('* holiday'), ['/home/u/Pictures/holiday photo.png']);
    });

    test('quoted phrases keep their spaces', () {
      expect(names('"holiday photo"'), ['/home/u/Pictures/holiday photo.png']);
      expect(names('"annual report"'), ['/home/u/Documents/annual report.pdf']);
      // Unquoted, 'photo' alone in another name would also have counted.
      expect(names('"day pho"'), ['/home/u/Pictures/holiday photo.png']);
    });

    test('words with a slash match the path', () {
      expect(names('main other/lib'), ['/home/u/projects/other/lib/main.dart']);
      // Trailing slash: what is inside lib, not lib itself.
      expect(names('rover_explorer/lib/'), hasLength(2));
    });

    test('path wildcard', () {
      expect(names('other/*.dart'), ['/home/u/projects/other/lib/main.dart']);
    });

    test('blank and whitespace-only queries return nothing', () {
      expect(names(''), isEmpty);
      expect(names('   '), isEmpty);
      expect(search(tree, '  ').total, 0);
    });
  });

  group('filters', () {
    test('kind filter with no text lists every item of that kind', () {
      expect(names('', kind: SearchKind.pictures), hasLength(4));
      expect(names('', kind: SearchKind.folders), hasLength(7));
    });

    test('kind filter applies with text', () {
      expect(names('report', kind: SearchKind.documents), hasLength(4));
      expect(names('report', kind: SearchKind.folders), isEmpty);
    });

    test('underPath does not leak into sibling folders sharing a prefix', () {
      expect(names('a.txt', under: '/home/u/foo'), ['/home/u/foo/a.txt']);
      expect(names('a.txt', under: '/home/u/foo/'), ['/home/u/foo/a.txt']);
    });

    test('underPath leaves out the folder itself', () {
      expect(names('foo', under: '/home/u/foo'), isEmpty);
    });

    test('underPath at the filesystem root', () {
      expect(names('a.txt', under: '/'), hasLength(2));
    });
  });

  group('ranking', () {
    test('exact > prefix > word start > substring', () {
      expect(names('report'), [
        '/home/u/Documents/report', // exact
        '/home/u/Documents/report-draft.docx', // prefix
        '/home/u/Documents/annual report.pdf', // word start
        '/home/u/Documents/summary_report.pdf', // word start
        '/home/u/Documents/misreported.txt', // substring
      ]);
    });

    test('names holding more of the words rank first', () {
      final r = names('rover explorer');
      expect(r.first, '/home/u/projects/rover_explorer');
    });

    test('total counts every match beyond the limit', () {
      final out = search(tree, 'report', limit: 2);
      expect(out.total, 5);
      expect(out.hits, hasLength(2));
    });

    test('top-k selection agrees with a full sort', () {
      final rnd = Random(7);
      final idx = FileIndex();
      const letters = 'abcde_.- ';
      for (var i = 0; i < 20000; i++) {
        final len = 1 + rnd.nextInt(14);
        final name = String.fromCharCodes([
          for (var j = 0; j < len; j++)
            letters.codeUnitAt(rnd.nextInt(letters.length)),
        ]);
        idx.add('/r/d${i % 50}/$name', rnd.nextBool());
      }
      for (final q in ['a', 'ab', 'b_', 'e', 'cd', 'a b']) {
        final all = search(idx, q, limit: 1 << 20);
        final top = search(idx, q, limit: 37);
        expect(top.total, all.total, reason: q);
        expect(top.hits, all.hits.take(37).toList(), reason: q);
      }
    });
  });

  group('Windows paths', () {
    final win = build({
      r'C:\Users\U\Docs': true,
      r'C:\Users\U\Docs\Plan.txt': false,
      r'C:\Users\U\DocsOld\Plan.txt': false,
    });

    test('folder scope is case-insensitive and separator-aware', () {
      expect(
        names(
          'plan',
          index: win,
          under: r'c:\users\u\docs',
          caseSensitivePaths: false,
          separator: r'\',
        ),
        [r'C:\Users\U\Docs\Plan.txt'],
      );
    });

    test('a typed forward slash matches backslash paths', () {
      expect(
        names(
          'plan docs/',
          index: win,
          caseSensitivePaths: false,
          separator: r'\',
        ),
        [r'C:\Users\U\Docs\Plan.txt'],
      );
    });
  });

  group('FileIndex.removeUnder', () {
    test('removes the entry and its subtree, not prefix siblings', () {
      final idx = build({
        '/a/foo': true,
        '/a/foo/x': false,
        '/a/foo/y/z': false,
        '/a/foobar': true,
        '/a/foobar/x': false,
        '/a/keep': false,
      });
      final removed = idx.removeUnder(['/a/foo'], separator: '/');
      expect(removed, 3);
      expect(idx.paths, ['/a/foobar', '/a/foobar/x', '/a/keep']);
      expect(idx.namesLower, ['foobar', 'x', 'keep']);
      expect(idx.isDirs, [true, false, false]);
    });

    test('several targets in one pass', () {
      final idx = build({'/a': true, '/a/1': false, '/b': true, '/c': false});
      idx.removeUnder(['/a', '/c'], separator: '/');
      expect(idx.paths, ['/b']);
    });
  });
}
