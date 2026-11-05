import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Filename kinds understood by the "What are you looking for?" filter.
enum SearchKind { all, folders, pictures, music, video, documents }

const _picExts = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.bmp',
  '.webp',
  '.svg',
  '.ico',
  '.tiff',
  '.heic',
};
const _musicExts = {
  '.mp3',
  '.wav',
  '.flac',
  '.ogg',
  '.m4a',
  '.wma',
  '.aac',
  '.opus',
  '.mid',
};
const _videoExts = {
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.wmv',
  '.webm',
  '.flv',
  '.m4v',
  '.mpg',
  '.mpeg',
};
const _docExts = {
  '.txt',
  '.md',
  '.pdf',
  '.doc',
  '.docx',
  '.xls',
  '.xlsx',
  '.ppt',
  '.pptx',
  '.odt',
  '.ods',
  '.odp',
  '.rtf',
  '.csv',
};

/// The in-memory filename index: three parallel lists, so a full home tree
/// costs one path string per entry plus a lowercased name.
class FileIndex {
  final paths = <String>[];
  final namesLower = <String>[];
  final isDirs = <bool>[];

  void add(String path, bool isDir) {
    paths.add(path);
    namesLower.add(p.basename(path).toLowerCase());
    isDirs.add(isDir);
  }

  int get length => paths.length;

  void clear() {
    paths.clear();
    namesLower.clear();
    isDirs.clear();
  }

  void replaceWith(FileIndex other) {
    clear();
    paths.addAll(other.paths);
    namesLower.addAll(other.namesLower);
    isDirs.addAll(other.isDirs);
  }

  /// Drops every entry that is one of [targets] or lies inside one of them.
  /// Returns how many entries were removed.
  int removeUnder(Iterable<String> targets, {required String separator}) {
    final exact = targets.toSet();
    if (exact.isEmpty) return 0;
    final prefixes = [
      for (final t in exact) t.endsWith(separator) ? t : '$t$separator',
    ];
    var w = 0;
    for (var r = 0; r < paths.length; r++) {
      final path = paths[r];
      var drop = exact.contains(path);
      if (!drop) {
        for (final pre in prefixes) {
          if (path.startsWith(pre)) {
            drop = true;
            break;
          }
        }
      }
      if (drop) continue;
      if (w != r) {
        paths[w] = path;
        namesLower[w] = namesLower[r];
        isDirs[w] = isDirs[r];
      }
      w++;
    }
    final removed = paths.length - w;
    paths.length = w;
    namesLower.length = w;
    isDirs.length = w;
    return removed;
  }
}

/// How one word of the query is matched.
enum TermType {
  /// Plain text: must appear in the file name or somewhere in its path.
  text,

  /// Contains `*` or `?`: must match the whole file name, XP-style.
  wildcard,

  /// Contains a path separator: must appear in the full path.
  path,
}

class QueryTerm {
  final String text;
  final TermType type;
  final RegExp? _pattern;

  // Fast paths for the common wildcard shapes; the regex handles the rest.
  final String? _suffix; // `*.pdf`
  final String? _prefix; // `report*`
  final String? _middle; // `*draft*`

  QueryTerm._(
    this.text,
    this.type,
    this._pattern,
    this._suffix,
    this._prefix,
    this._middle,
  );

  factory QueryTerm.parse(String lower) {
    final hasSep = lower.contains('/') || lower.contains(r'\');
    if (lower.contains('*') || lower.contains('?')) {
      final star = '*'.codeUnitAt(0);
      String? suffix;
      String? prefix;
      String? middle;
      if (!lower.contains('?') && !hasSep) {
        final inner = lower.replaceAll('*', '');
        final stars = lower.length - inner.length;
        if (stars == 1 && lower.codeUnitAt(0) == star) {
          suffix = inner;
        } else if (stars == 1 && lower.codeUnitAt(lower.length - 1) == star) {
          prefix = inner;
        } else if (stars == 2 &&
            lower.length > 2 &&
            lower.codeUnitAt(0) == star &&
            lower.codeUnitAt(lower.length - 1) == star) {
          middle = inner;
        }
      }
      final sb = StringBuffer('^');
      // A path wildcard may start anywhere in the path (`src/*.dart`).
      if (hasSep) sb.write('.*');
      for (final ch in lower.split('')) {
        sb.write(switch (ch) {
          '*' => '.*',
          '?' => '.',
          _ => RegExp.escape(ch),
        });
      }
      sb.write(r'$');
      return QueryTerm._(
        lower,
        hasSep ? TermType.path : TermType.wildcard,
        RegExp(sb.toString(), dotAll: true),
        suffix,
        prefix,
        middle,
      );
    }
    return QueryTerm._(
      lower,
      hasSep ? TermType.path : TermType.text,
      null,
      null,
      null,
      null,
    );
  }

  bool get isWildcard => _pattern != null;

  bool matchesWhole(String s) {
    if (_suffix != null) return s.endsWith(_suffix);
    if (_prefix != null) return s.startsWith(_prefix);
    if (_middle != null) return s.contains(_middle);
    return _pattern!.hasMatch(s);
  }
}

/// Splits a query into lowercased terms. Whitespace separates words; a
/// double-quoted run is one term, so `"annual report"` matches the space.
/// On Windows ([separator] `\`) a typed `/` is read as `\`.
List<QueryTerm> parseQuery(String text, {String separator = '/'}) {
  final terms = <QueryTerm>[];
  var lower = text.toLowerCase();
  if (separator != '/') lower = lower.replaceAll('/', separator);
  final sb = StringBuffer();
  var quoted = false;
  void flush() {
    if (sb.isEmpty) return;
    final t = sb.toString();
    sb.clear();
    // A lone `*` matches everything: it filters nothing, so drop it.
    if (t.replaceAll('*', '').isEmpty) return;
    terms.add(QueryTerm.parse(t));
  }

  for (final ch in lower.split('')) {
    if (ch == '"') {
      flush();
      quoted = !quoted;
    } else if (!quoted && (ch == ' ' || ch == '\t' || ch == '\n')) {
      flush();
    } else {
      sb.write(ch);
    }
  }
  flush();
  return terms;
}

class SearchOutcome {
  /// Index positions of the best hits, best first.
  final List<int> hits;
  final int total;
  const SearchOutcome(this.hits, this.total);

  static const empty = SearchOutcome([], 0);
}

bool kindMatches(SearchKind kind, String nameLower, bool isDir) {
  if (kind == SearchKind.all) return true;
  if (kind == SearchKind.folders) return isDir;
  if (isDir) return false;
  final dot = nameLower.lastIndexOf('.');
  final ext = dot < 0 ? '' : nameLower.substring(dot);
  return switch (kind) {
    SearchKind.pictures => _picExts.contains(ext),
    SearchKind.music => _musicExts.contains(ext),
    SearchKind.video => _videoExts.contains(ext),
    SearchKind.documents => _docExts.contains(ext),
    _ => true,
  };
}

/// Match strength of [term] inside [name]: 0 exact, 1 prefix, 2 word start,
/// 3 substring, or -1 when it does not occur.
int _matchClass(String name, String term) {
  final pos = name.indexOf(term);
  if (pos < 0) return -1;
  if (pos == 0) return name.length == term.length ? 0 : 1;
  final prev = name.codeUnitAt(pos - 1);
  final wordStart =
      prev == 0x20 || // space
      prev == 0x2E || // .
      prev == 0x2D || // -
      prev == 0x5F || // _
      prev == 0x28 || // (
      prev == 0x5B; // [
  return wordStart ? 2 : 3;
}

/// Runs [text] against [index].
///
/// Every word must match: plain words in the name or anywhere in the path,
/// wildcard words (`*.pdf`, `IMG_????.jpg`) against the whole name, words
/// with a `/` against the path. At least one plain or wildcard word has to
/// hit the name itself, so `rover screen` finds `explorer_screen.dart` under
/// `rover_explorer` but not every file below a folder called `screen`. Word
/// order does not matter.
///
/// Results are ranked: names containing more of the words first, then
/// exact > prefix > word-start > substring, then shorter names.
SearchOutcome search(
  FileIndex index,
  String text, {
  SearchKind kind = SearchKind.all,
  String? underPath,
  int limit = 400,
  bool caseSensitivePaths = true,
  String separator = '/',
}) {
  final terms = parseQuery(text, separator: separator);
  if (terms.isEmpty && kind == SearchKind.all) return SearchOutcome.empty;
  if (limit < 1) limit = 1;

  final nameTerms = [
    for (final t in terms)
      if (t.type != TermType.path) t,
  ];
  final pathTerms = [
    for (final t in terms)
      if (t.type == TermType.path) t,
  ];

  String? underPrefix;
  if (underPath != null) {
    var u = underPath;
    if (!u.endsWith(separator)) u = '$u$separator';
    underPrefix = caseSensitivePaths ? u : u.toLowerCase();
  }

  final heap = _TopK(limit);
  var total = 0;

  final paths = index.paths;
  final names = index.namesLower;
  final dirs = index.isDirs;
  // Positions share an int with the score (see below); 64M entries is far
  // beyond any home tree.
  final n = paths.length <= _posMask ? paths.length : _posMask + 1;
  for (var i = 0; i < n; i++) {
    final name = names[i];
    if (!kindMatches(kind, name, dirs[i])) continue;

    var best = 3;
    var misses = 0; // plain words found only in the path
    var inName = 0;
    var needPath = false;
    var rejected = false;
    for (final t in nameTerms) {
      if (t.isWildcard) {
        if (!t.matchesWhole(name)) {
          rejected = true;
          break;
        }
        inName++;
        if (best > 1) best = 1;
        continue;
      }
      final c = _matchClass(name, t.text);
      if (c < 0) {
        misses++;
        needPath = true;
      } else {
        inName++;
        if (c < best) best = c;
      }
    }
    if (rejected) continue;
    if (nameTerms.isNotEmpty && inName == 0) continue;

    if (underPrefix != null) {
      final path = paths[i];
      if (path.length <= underPrefix.length) continue;
      if (caseSensitivePaths
          ? !path.startsWith(underPrefix)
          : path.substring(0, underPrefix.length).toLowerCase() !=
                underPrefix) {
        continue;
      }
    }

    if (needPath || pathTerms.isNotEmpty) {
      final pathLower = paths[i].toLowerCase();
      var ok = true;
      if (needPath) {
        for (final t in nameTerms) {
          if (!t.isWildcard &&
              !name.contains(t.text) &&
              !pathLower.contains(t.text)) {
            ok = false;
            break;
          }
        }
      }
      if (ok) {
        for (final t in pathTerms) {
          if (t.isWildcard
              ? !t.matchesWhole(pathLower)
              : !pathLower.contains(t.text)) {
            ok = false;
            break;
          }
        }
      }
      if (!ok) continue;
    }

    total++;
    // One sortable int per hit: misses, match class, name length, position.
    // Position is last, so equal scores keep index (walk) order.
    final len = name.length > 1023 ? 1023 : name.length;
    final m = misses > 15 ? 15 : misses;
    heap.offer(((((m << 2) | best) << 10 | len) << 26) | i);
  }

  final keys = heap.sorted();
  return SearchOutcome([for (final k in keys) k & _posMask], total);
}

const _posMask = (1 << 26) - 1;

/// Keeps the [k] smallest keys seen, as a binary max-heap.
class _TopK {
  final int k;
  final Int64List _heap;
  int _n = 0;
  _TopK(this.k) : _heap = Int64List(k);

  void offer(int key) {
    if (_n < k) {
      var c = _n++;
      _heap[c] = key;
      while (c > 0) {
        final parent = (c - 1) >> 1;
        if (_heap[parent] >= _heap[c]) break;
        final tmp = _heap[parent];
        _heap[parent] = _heap[c];
        _heap[c] = tmp;
        c = parent;
      }
      return;
    }
    if (key >= _heap[0]) return;
    _heap[0] = key;
    var c = 0;
    while (true) {
      final l = 2 * c + 1;
      if (l >= _n) break;
      final r = l + 1;
      final big = r < _n && _heap[r] > _heap[l] ? r : l;
      if (_heap[c] >= _heap[big]) break;
      final tmp = _heap[c];
      _heap[c] = _heap[big];
      _heap[big] = tmp;
      c = big;
    }
  }

  List<int> sorted() => (_heap.sublist(0, _n)..sort()).toList();
}
