import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'search_engine.dart';
import 'win_attributes.dart';

export 'search_engine.dart' show SearchKind;

/// One search hit. Size/date are stat'd lazily by the UI, not stored in the
/// index — keeping the index to (path, name, isDir) is what makes a full
/// home-directory index cheap enough to hold in RAM and scan per keystroke.
class SearchHit {
  final String path;
  final String name;
  final bool isDir;
  const SearchHit(this.path, this.name, this.isDir);
}

class SearchResults {
  final int queryId;
  final List<SearchHit> hits;
  final int totalMatches;

  /// Set when the indexer hit an error answering this query.
  final String? error;
  const SearchResults(this.queryId, this.hits, this.totalMatches, {this.error});
}

/// Everything-style filename index.
///
/// A long-lived background isolate owns the index:
///  * on startup it loads the previous index from a cache file so search is
///    instant, then re-walks the filesystem to refresh it;
///  * queries are answered from the in-memory index (see [search]), never by
///    touching the disk — except "only in current folder" searches of a
///    folder the index does not cover, which walk that folder once;
///  * file operations done in the app are applied with [touch], so results
///    stay correct without waiting for the next full scan.
class SearchIndexService {
  SendPort? _toIsolate;
  Isolate? _isolate;
  ReceivePort? _fromIsolate;
  final _resultsController = StreamController<SearchResults>.broadcast();
  final _statusController = StreamController<IndexStatus>.broadcast();
  int _queryCounter = 0;

  // Only one query is in the isolate at a time; while it runs, newer queries
  // replace each other here, so fast typing never builds a backlog of stale
  // searches. A replaced query is never answered.
  int? _inFlight;
  Map<String, Object?>? _queued;

  Stream<SearchResults> get results => _resultsController.stream;
  Stream<IndexStatus> get status => _statusController.stream;
  IndexStatus lastStatus = const IndexStatus(0, false, false);

  Future<void> start({
    required List<String> roots,
    required String cacheFile,
  }) async {
    final fromIsolate = _fromIsolate = ReceivePort();
    _isolate = await Isolate.spawn(
      _indexerMain,
      fromIsolate.sendPort,
      // Every command handler catches its own errors; this keeps a stray one
      // from taking the whole indexer (and with it, search) down.
      errorsAreFatal: false,
    );
    final ready = Completer<void>();
    fromIsolate.listen((msg) {
      if (msg is SendPort) {
        _toIsolate = msg;
        _toIsolate!.send({'cmd': 'init', 'roots': roots, 'cache': cacheFile});
        ready.complete();
      } else if (msg is Map) {
        switch (msg['type']) {
          case 'status':
            lastStatus = IndexStatus(
              msg['count'] as int,
              msg['scanning'] as bool,
              true,
              complete: msg['complete'] as bool,
            );
            _statusController.add(lastStatus);
          case 'results':
            final id = msg['id'] as int;
            if (id == _inFlight) {
              _inFlight = null;
              final next = _queued;
              _queued = null;
              if (next != null) _send(next);
            }
            _resultsController.add(
              SearchResults(
                id,
                (msg['hits'] as List)
                    .map(
                      (h) => SearchHit(
                        h[0] as String,
                        h[1] as String,
                        h[2] as bool,
                      ),
                    )
                    .toList(),
                msg['total'] as int,
                error: msg['error'] as String?,
              ),
            );
        }
      }
    });
    await ready.future;
  }

  void _send(Map<String, Object?> msg) {
    final port = _toIsolate;
    if (port == null) return;
    _inFlight = msg['id'] as int;
    port.send(msg);
  }

  /// Fire a query; results arrive on [results] tagged with the returned id.
  /// If another query is still running, this one waits and replaces any
  /// query already waiting.
  int query(
    String text, {
    SearchKind kind = SearchKind.all,
    String? underPath,
    int limit = 400,
  }) {
    final id = ++_queryCounter;
    final msg = <String, Object?>{
      'cmd': 'query',
      'id': id,
      'text': text,
      'kind': kind.index,
      'under': underPath,
      'limit': limit,
    };
    if (_inFlight == null) {
      _send(msg);
    } else {
      _queued = msg;
    }
    return id;
  }

  /// Tell the index about changes made by the app itself: [removed] paths
  /// (and everything under them) are dropped, [added] paths are re-read from
  /// disk (folders with their contents). A rename is one of each.
  void touch({
    Iterable<String> removed = const [],
    Iterable<String> added = const [],
  }) {
    if (removed.isEmpty && added.isEmpty) return;
    _toIsolate?.send({
      'cmd': 'touch',
      'removed': removed.toList(),
      'added': added.toList(),
    });
  }

  void rescan() => _toIsolate?.send({'cmd': 'rescan'});

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _fromIsolate?.close();
    _resultsController.close();
    _statusController.close();
  }
}

class IndexStatus {
  final int count;
  final bool scanning;
  final bool started;

  /// False until the index covers the whole tree at least once (from the
  /// cache or a finished scan); searches before that may miss files.
  final bool complete;
  const IndexStatus(
    this.count,
    this.scanning,
    this.started, {
    this.complete = false,
  });
}

// ---------------------------------------------------------------------------
// Isolate side
// ---------------------------------------------------------------------------

late SendPort _mainPort;
final _index = FileIndex();
var _scanning = false;
var _complete = false;
List<String> _roots = [];
String _cachePath = '';

/// Commands run one after another, so a query never sees a half-applied
/// [_touch] and a rescan never starts before the cache has loaded. The full
/// scan itself runs outside this chain and yields to it.
Future<void> _chain = Future.value();

/// Touches that arrived during a scan, replayed onto the scan's result.
final _touchesDuringScan = <(List<String>, List<String>)>[];

final _sep = Platform.pathSeparator;
final _caseSensitive = !Platform.isWindows;

/// "Only in current folder" outside the indexed tree walks that folder on
/// demand; the walk is kept briefly so each keystroke does not repeat it.
String? _adhocRoot;
Future<FileIndex>? _adhocIndex;
DateTime? _adhocBuiltAt;
const _adhocTtl = Duration(seconds: 30);
const _adhocCap = 500000;

void _indexerMain(SendPort mainPort) {
  _mainPort = mainPort;
  final port = ReceivePort();
  mainPort.send(port.sendPort);
  port.listen((msg) {
    if (msg is! Map) return;
    _chain = _chain.then((_) => _handle(msg)).catchError((Object _) {});
  });
}

Future<void> _handle(Map msg) async {
  switch (msg['cmd']) {
    case 'init':
      _roots = (msg['roots'] as List).cast<String>();
      _cachePath = msg['cache'] as String;
      await _loadCache();
      _complete = _index.length > 0;
      _sendStatus();
      unawaited(_walk());
    case 'rescan':
      _dropAdhoc();
      unawaited(_walk());
    case 'query':
      try {
        await _answer(msg);
      } catch (e) {
        _mainPort.send({
          'type': 'results',
          'id': msg['id'],
          'hits': const [],
          'total': 0,
          'error': '$e',
        });
      }
    case 'touch':
      try {
        final removed = (msg['removed'] as List).cast<String>();
        final added = (msg['added'] as List).cast<String>();
        _dropAdhoc();
        await _touch(_index, removed, added);
        if (_scanning) _touchesDuringScan.add((removed, added));
        _sendStatus();
      } catch (_) {}
  }
}

void _sendStatus({int? count}) => _mainPort.send({
  'type': 'status',
  'count': count ?? _index.length,
  'scanning': _scanning,
  'complete': _complete,
});

void _dropAdhoc() {
  _adhocRoot = null;
  _adhocIndex = null;
  _adhocBuiltAt = null;
}

Future<void> _loadCache() async {
  try {
    final f = File(_cachePath);
    if (!f.existsSync()) return;
    final lines = await f.readAsLines();
    for (final line in lines) {
      if (line.length < 2) continue;
      _index.add(line.substring(1), line.codeUnitAt(0) == 0x64 /* 'd' */);
    }
  } catch (_) {
    _index.clear();
  }
}

Future<void> _saveCache() async {
  try {
    final sb = StringBuffer();
    for (var i = 0; i < _index.length; i++) {
      final path = _index.paths[i];
      // One entry per line: a name with a line break cannot round-trip.
      if (path.contains('\n') || path.contains('\r')) continue;
      sb.write(_index.isDirs[i] ? 'd' : 'f');
      sb.writeln(path);
    }
    final f = File(_cachePath);
    await f.parent.create(recursive: true);
    // Write-then-rename, so a crash mid-write cannot leave a truncated cache.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(sb.toString());
    await tmp.rename(f.path);
  } catch (_) {}
}

const _skipDirNames = {'proc', 'sys', 'dev', 'run', 'lost+found'};

bool _hiddenName(String path) {
  final name = p.basename(path);
  // Windows hides with an attribute instead (AppData, NTUSER.DAT...).
  return name.startsWith('.') || WinAttributes.isHidden(path);
}

/// Adds everything below [roots] (not the roots themselves) to [into],
/// skipping hidden entries. Yields between batches so queued queries run.
Future<void> _walkInto(
  FileIndex into,
  List<String> roots, {
  int? cap,
  void Function(int count)? onProgress,
}) async {
  var sinceYield = 0;
  for (final root in roots) {
    final stack = <String>[root];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = Directory(dir).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in children) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue; // hidden files/dirs
        if (WinAttributes.isHidden(e.path)) continue;
        final isDir = e is Directory;
        if (isDir && p.dirname(e.path) == '/' && _skipDirNames.contains(name)) {
          continue;
        }
        into.add(e.path, isDir);
        if (cap != null && into.length >= cap) return;
        if (isDir) stack.add(e.path);
        if (++sinceYield >= 4000) {
          sinceYield = 0;
          onProgress?.call(into.length);
          // Let queued query messages run between directory batches.
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
  }
}

Future<void> _walk() async {
  if (_scanning) return;
  _scanning = true;
  _touchesDuringScan.clear();
  _sendStatus();
  try {
    // With no cache to serve from, fill the live index as the scan goes, so
    // the very first searches already find what has been seen so far.
    final progressive = _index.length == 0;
    final target = progressive ? _index : FileIndex();
    await _walkInto(target, _roots, onProgress: (n) => _sendStatus(count: n));
    if (!progressive) _index.replaceWith(target);
    // The scan may have read a folder before or after a touch landed in it;
    // re-applying is idempotent, so the result matches the disk either way.
    for (final (removed, added) in _touchesDuringScan) {
      await _touch(_index, removed, added);
    }
    _complete = true;
  } catch (_) {
    // Keep whatever index we had; the next rescan tries again.
  } finally {
    _touchesDuringScan.clear();
    _scanning = false;
  }
  // Saved before announcing the finished scan, so "scan done" also means the
  // cache file is written and no longer open, and the next launch starts
  // from this index.
  await _saveCache();
  _sendStatus();
}

/// Whether [path] is inside the indexed tree: under a root, with no hidden
/// folder in between (hidden folders are never walked).
bool _covered(String path) {
  for (final root in _roots) {
    if (!(p.equals(root, path) || p.isWithin(root, path))) continue;
    var cur = path;
    while (!p.equals(cur, root)) {
      if (_hiddenName(cur)) return false;
      final parent = p.dirname(cur);
      if (parent == cur) break;
      cur = parent;
    }
    return true;
  }
  return false;
}

Future<void> _touch(
  FileIndex idx,
  List<String> removed,
  List<String> added,
) async {
  idx.removeUnder([...removed, ...added], separator: _sep);
  for (final path in added) {
    if (_hiddenName(path) || !_covered(p.dirname(path))) continue;
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    final isDir = type == FileSystemEntityType.directory;
    idx.add(path, isDir);
    if (isDir) await _walkInto(idx, [path]);
  }
}

Future<FileIndex> _adhocFor(String root) {
  final cached = _adhocIndex;
  final builtAt = _adhocBuiltAt;
  if (cached != null &&
      _adhocRoot == root &&
      (builtAt == null || DateTime.now().difference(builtAt) < _adhocTtl)) {
    return cached;
  }
  _adhocRoot = root;
  _adhocBuiltAt = null;
  final built = () async {
    final idx = FileIndex();
    await _walkInto(idx, [root], cap: _adhocCap);
    if (_adhocRoot == root) _adhocBuiltAt = DateTime.now();
    return idx;
  }();
  return _adhocIndex = built;
}

Future<void> _answer(Map msg) async {
  final id = msg['id'] as int;
  final text = msg['text'] as String;
  final kind = SearchKind.values[msg['kind'] as int];
  final under = msg['under'] as String?;
  final limit = msg['limit'] as int;

  var idx = _index;
  final hasQuery =
      kind != SearchKind.all || parseQuery(text, separator: _sep).isNotEmpty;
  if (under != null && hasQuery && !_covered(under)) {
    idx = await _adhocFor(under);
  }

  final out = search(
    idx,
    text,
    kind: kind,
    underPath: under,
    limit: limit,
    caseSensitivePaths: _caseSensitive,
    separator: _sep,
  );
  final hits = <List<Object>>[
    for (final i in out.hits)
      [idx.paths[i], p.basename(idx.paths[i]), idx.isDirs[i]],
  ];
  _mainPort.send({
    'type': 'results',
    'id': id,
    'hits': hits,
    'total': out.total,
  });
}
