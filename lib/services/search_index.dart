import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'win_attributes.dart';

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
  const SearchResults(this.queryId, this.hits, this.totalMatches);
}

/// Filename kinds understood by the "What are you looking for?" filter.
enum SearchKind { all, folders, pictures, music, video, documents }

/// Everything-style filename index.
///
/// A long-lived background isolate owns the index:
///  * on startup it loads the previous index from a cache file so search is
///    instant, then re-walks the filesystem to refresh it;
///  * queries are answered from the in-memory index (simple substring /
///    prefix scoring over lowercased names), never by touching the disk —
///    except for a folder outside the indexed roots, which is walked on the
///    spot when searched with "only in current folder";
///  * while a scan runs, queries also see what it has found so far, so a
///    first run without a cache is not blind until the scan completes;
///  * changes made from inside the app ([changed]) are applied at once
///    instead of waiting for the next full rescan.
class SearchIndexService {
  SendPort? _toIsolate;
  Isolate? _isolate;
  ReceivePort? _fromIsolate;
  ReceivePort? _errorPort;
  final _resultsController = StreamController<SearchResults>.broadcast();
  final _statusController = StreamController<IndexStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  int _queryCounter = 0;

  Stream<SearchResults> get results => _resultsController.stream;
  Stream<IndexStatus> get status => _statusController.stream;

  /// Errors raised inside the indexer, as text. The indexer survives them
  /// (see [start]); this is for logging.
  Stream<String> get errors => _errorController.stream;
  IndexStatus lastStatus = const IndexStatus(0, false, false);

  Future<void> start({
    required List<String> roots,
    required String cacheFile,
  }) async {
    final fromIsolate = ReceivePort();
    final errorPort = ReceivePort();
    _fromIsolate = fromIsolate;
    _errorPort = errorPort;
    errorPort.listen((e) {
      if (_errorController.isClosed) return;
      _errorController.add(e is List && e.isNotEmpty ? '${e.first}' : '$e');
    });
    // An error that escapes the indexer (a message it cannot read, a walk
    // that fails in an unexpected way) must not take the whole indexer down
    // with it, leaving every later search unanswered.
    _isolate = await Isolate.spawn(
      _indexerMain,
      fromIsolate.sendPort,
      errorsAreFatal: false,
      onError: errorPort.sendPort,
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
            );
            if (!_statusController.isClosed) _statusController.add(lastStatus);
          case 'results':
            if (_resultsController.isClosed) return;
            _resultsController.add(
              SearchResults(
                msg['id'] as int,
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
              ),
            );
        }
      }
    });
    await ready.future;
  }

  /// Fire a query; results arrive on [results] tagged with the returned id.
  ///
  /// Every word of [text] must appear somewhere in the path, in any order,
  /// and at least one of them in the file name. [underPath] restricts hits to
  /// that folder's contents; a folder outside the indexed roots is walked on
  /// the spot.
  int query(
    String text, {
    SearchKind kind = SearchKind.all,
    String? underPath,
    int limit = 400,
  }) {
    final id = ++_queryCounter;
    _toIsolate?.send({
      'cmd': 'query',
      'id': id,
      'text': text,
      'kind': kind.index,
      'under': underPath,
      'limit': limit,
    });
    return id;
  }

  void rescan() => _toIsolate?.send({'cmd': 'rescan'});

  /// Tells the index about files and folders the app itself just renamed,
  /// deleted, moved or created, so searches reflect them at once. Removing a
  /// folder drops everything under it; adding one indexes its contents.
  void changed({
    List<String> removed = const [],
    List<String> added = const [],
  }) {
    if (removed.isEmpty && added.isEmpty) return;
    _toIsolate?.send({'cmd': 'changed', 'removed': removed, 'added': added});
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _fromIsolate?.close();
    _errorPort?.close();
    _resultsController.close();
    _statusController.close();
    _errorController.close();
  }
}

class IndexStatus {
  final int count;
  final bool scanning;
  final bool started;
  const IndexStatus(this.count, this.scanning, this.started);
}

// ---------------------------------------------------------------------------
// Isolate side
// ---------------------------------------------------------------------------

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

/// Paths are compared as the filesystem does: case-insensitively on Windows.
String _fold(String path) => Platform.isWindows ? path.toLowerCase() : path;

class _Index {
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

  void replaceWith(_Index other) {
    clear();
    paths.addAll(other.paths);
    namesLower.addAll(other.namesLower);
    isDirs.addAll(other.isDirs);
  }

  /// Drops [path] and everything under it.
  void removeTree(String path) {
    final target = _fold(path);
    final prefix = _withSeparator(target);
    final keepPaths = <String>[];
    final keepNames = <String>[];
    final keepDirs = <bool>[];
    for (var i = 0; i < paths.length; i++) {
      final f = _fold(paths[i]);
      if (f == target || f.startsWith(prefix)) continue;
      keepPaths.add(paths[i]);
      keepNames.add(namesLower[i]);
      keepDirs.add(isDirs[i]);
    }
    if (keepPaths.length == paths.length) return;
    clear();
    paths.addAll(keepPaths);
    namesLower.addAll(keepNames);
    isDirs.addAll(keepDirs);
  }
}

/// `/home/me/foo` → `/home/me/foo/`, so that `/home/me/foobar` is not "under"
/// it; a bare root (`/`, `C:\`) keeps its own separator.
String _withSeparator(String dir) {
  var d = dir;
  while (d.length > 1 && d.endsWith(p.separator)) {
    d = d.substring(0, d.length - 1);
  }
  return d.endsWith(p.separator) ? d : '$d${p.separator}';
}

late SendPort _mainPort;
final _index = _Index();

/// The index a running scan is building, searched alongside [_index] so a
/// first run (no cache yet) returns what has been found so far.
_Index? _fresh;
var _scanning = false;
List<String> _roots = [];
String _cachePath = '';

/// Completes once the on-disk index cache has been read; queries wait on it.
Future<void>? _cacheLoaded;

/// Changes reported while a scan ran, replayed onto its result so they are
/// not lost when it replaces the index.
final _changesDuringScan = <List<List<String>>>[];

/// A folder outside the indexed roots, walked for "only in current folder"
/// and kept for a short while so typing does not re-walk it per keystroke.
_Index? _adhoc;
String? _adhocRoot;
DateTime _adhocAt = DateTime.fromMillisecondsSinceEpoch(0);

void _indexerMain(SendPort mainPort) {
  _mainPort = mainPort;
  final port = ReceivePort();
  mainPort.send(port.sendPort);
  port.listen((msg) async {
    if (msg is! Map) return;
    try {
      switch (msg['cmd']) {
        case 'init':
          _roots = (msg['roots'] as List).cast<String>();
          _cachePath = msg['cache'] as String;
          // Claimed synchronously so a query arriving during the (async)
          // cache load waits for it instead of racing an empty index.
          final ready = Completer<void>();
          _cacheLoaded = ready.future;
          try {
            await _loadCache();
          } finally {
            ready.complete();
          }
          _sendStatus();
          unawaited(_walk());
        case 'rescan':
          unawaited(_walk());
        case 'changed':
          await _applyChanges(
            (msg['removed'] as List).cast<String>(),
            (msg['added'] as List).cast<String>(),
          );
        case 'query':
          final pending = _cacheLoaded;
          if (pending != null) {
            await pending;
          }
          await _answer(msg);
      }
    } catch (e) {
      // Whatever went wrong, a query is answered, so the UI never waits for
      // a reply that is not coming.
      if (msg['cmd'] == 'query' && msg['id'] is int) {
        _mainPort.send({
          'type': 'results',
          'id': msg['id'],
          'hits': const [],
          'total': 0,
        });
      }
      rethrow; // reported on the service's error stream; the isolate lives on
    }
  });
}

void _sendStatus() => _mainPort.send({
  'type': 'status',
  'count': _index.length,
  'scanning': _scanning,
});

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
      sb.write(_index.isDirs[i] ? 'd' : 'f');
      sb.writeln(_index.paths[i]);
    }
    final f = File(_cachePath);
    await f.parent.create(recursive: true);
    await f.writeAsString(sb.toString());
  } catch (_) {}
}

const _skipDirNames = {'proc', 'sys', 'dev', 'run', 'lost+found'};

Future<void> _walk() async {
  if (_scanning) return;
  _scanning = true;
  final fresh = _fresh = _Index();
  _changesDuringScan.clear();
  _sendStatus();
  try {
    for (final root in _roots) {
      await _scanTree(
        fresh,
        root,
        onProgress: () => _mainPort.send({
          'type': 'status',
          'count': fresh.length,
          'scanning': true,
        }),
      );
    }
    // Anything the app changed meanwhile was applied to the old index; the
    // scan may have passed those folders before or after the change.
    for (final change in _changesDuringScan) {
      await _applyTo(fresh, change[0], change[1]);
    }
    _index.replaceWith(fresh);
    // Saved before announcing the finished scan, so "scan done" also means
    // the cache file is written and no longer open.
    await _saveCache();
  } finally {
    // Also after a failure: a scan that never ends would refuse every later
    // rescan and show "indexing" forever.
    _scanning = false;
    _fresh = null;
    _changesDuringScan.clear();
    _adhoc = null;
    _sendStatus();
  }
}

/// Walks [root] into [into], skipping hidden items, and yields to queued
/// messages (queries) every few thousand entries. Stops at [limit] entries.
Future<void> _scanTree(
  _Index into,
  String root, {
  void Function()? onProgress,
  int? limit,
}) async {
  final stack = <String>[root];
  var sinceYield = 0;
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in children) {
      if (limit != null && into.length >= limit) return;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue; // hidden files/dirs
      // Windows hides with an attribute instead (AppData, NTUSER.DAT...).
      if (WinAttributes.isHidden(e.path)) continue;
      final isDir = e is Directory;
      if (isDir && p.dirname(e.path) == '/' && _skipDirNames.contains(name)) {
        continue;
      }
      into.add(e.path, isDir);
      if (isDir) stack.add(e.path);
      if (++sinceYield >= 4000) {
        sinceYield = 0;
        onProgress?.call();
        // Let queued query messages run between directory batches.
        await Future.delayed(Duration.zero);
      }
    }
  }
}

Future<void> _applyChanges(List<String> removed, List<String> added) async {
  _adhoc = null;
  if (_scanning) _changesDuringScan.add([removed, added]);
  await _applyTo(_index, removed, added);
}

Future<void> _applyTo(
  _Index idx,
  List<String> removed,
  List<String> added,
) async {
  for (final path in removed) {
    idx.removeTree(path);
  }
  for (final path in added) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (p.basename(path).startsWith('.') || WinAttributes.isHidden(path)) {
      continue;
    }
    idx.removeTree(path); // no duplicate if it was already there
    final isDir = type == FileSystemEntityType.directory;
    idx.add(path, isDir);
    if (isDir) await _scanTree(idx, path);
  }
}

bool _withinRoots(String dir) =>
    _roots.any((r) => p.equals(r, dir) || p.isWithin(r, dir));

Future<_Index> _adhocIndex(String root) async {
  final cached = _adhoc;
  if (cached != null &&
      _adhocRoot == root &&
      DateTime.now().difference(_adhocAt) < const Duration(seconds: 30)) {
    return cached;
  }
  final idx = _Index();
  await _scanTree(idx, root, limit: 200000);
  _adhoc = idx;
  _adhocRoot = root;
  _adhocAt = DateTime.now();
  return idx;
}

bool _kindMatches(_Index idx, int kind, int i) {
  final k = SearchKind.values[kind];
  if (k == SearchKind.all) return true;
  final isDir = idx.isDirs[i];
  if (k == SearchKind.folders) return isDir;
  if (isDir) return false;
  final name = idx.namesLower[i];
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot);
  return switch (k) {
    SearchKind.pictures => _picExts.contains(ext),
    SearchKind.music => _musicExts.contains(ext),
    SearchKind.video => _videoExts.contains(ext),
    SearchKind.documents => _docExts.contains(ext),
    _ => true,
  };
}

bool _atWordStart(String name, int pos) {
  if (pos == 0) return true;
  final prev = name.codeUnitAt(pos - 1);
  return prev == 0x20 || // space
      prev == 0x2E || // .
      prev == 0x2D || // -
      prev == 0x5F || // _
      prev == 0x28; // (
}

class _Match {
  final _Index idx;
  final int i;
  final int key; // lower is better
  const _Match(this.idx, this.i, this.key);
}

/// Appends every entry of [idx] matching the query to [out]; returns how many.
///
/// Every word must appear somewhere in the full path and at least one in the
/// name itself, whatever their order. The rank is the best name match (exact,
/// prefix, word start, anywhere), then how many words hit the name, then the
/// name's length. With [seen], paths already matched by another index are
/// skipped, and new matches are recorded in it.
int _collect(
  _Index idx,
  List<String> tokens,
  int kind,
  String? underPrefix,
  List<_Match> out, {
  Set<String>? seen,
  bool record = false,
}) {
  var total = 0;
  for (var i = 0; i < idx.length; i++) {
    final name = idx.namesLower[i];
    String? pathLower;
    var best = 3;
    var inName = 0;
    var ok = true;
    for (final t in tokens) {
      final pos = name.indexOf(t);
      if (pos >= 0) {
        inName++;
        final score = name == t
            ? 0
            : pos == 0
            ? 1
            : _atWordStart(name, pos)
            ? 2
            : 3;
        if (score < best) best = score;
      } else {
        pathLower ??= idx.paths[i].toLowerCase();
        if (!pathLower.contains(t)) {
          ok = false;
          break;
        }
      }
    }
    if (!ok || (tokens.isNotEmpty && inName == 0)) continue;
    if (underPrefix != null) {
      pathLower ??= idx.paths[i].toLowerCase();
      if (!pathLower.startsWith(underPrefix)) continue;
    }
    if (!_kindMatches(idx, kind, i)) continue;
    if (seen != null) {
      if (seen.contains(idx.paths[i])) continue;
      if (record) seen.add(idx.paths[i]);
    }
    total++;
    final rank = best * 10 + (tokens.length - inName).clamp(0, 9);
    out.add(_Match(idx, i, rank * 1000 + name.length.clamp(0, 999)));
  }
  return total;
}

Future<void> _answer(Map msg) async {
  final id = msg['id'] as int;
  final raw = (msg['text'] as String).trim().toLowerCase();
  final kind = msg['kind'] as int;
  final under = msg['under'] as String?;
  final limit = msg['limit'] as int;

  if (raw.isEmpty && kind == SearchKind.all.index) {
    _mainPort.send({'type': 'results', 'id': id, 'hits': const [], 'total': 0});
    return;
  }

  final tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  // The folder's own contents only: `~/foo/` so that `~/foobar` stays out.
  final underPrefix = under == null
      ? null
      : _withSeparator(under).toLowerCase();

  final matches = <_Match>[];
  var total = 0;
  if (under != null && !_withinRoots(under)) {
    // Not covered by the index: look at that folder directly.
    final idx = await _adhocIndex(under);
    total += _collect(idx, tokens, kind, underPrefix, matches);
  } else {
    final fresh = _fresh;
    if (fresh == null) {
      total += _collect(_index, tokens, kind, underPrefix, matches);
    } else {
      // A scan is running: what it has found so far counts too, once.
      final seen = <String>{};
      total += _collect(
        _index,
        tokens,
        kind,
        underPrefix,
        matches,
        seen: seen,
        record: true,
      );
      total += _collect(fresh, tokens, kind, underPrefix, matches, seen: seen);
    }
  }

  matches.sort((a, b) => a.key.compareTo(b.key));
  final hits = <List<Object>>[];
  for (var j = 0; j < matches.length && hits.length < limit; j++) {
    final m = matches[j];
    final path = m.idx.paths[m.i];
    hits.add([path, p.basename(path), m.idx.isDirs[m.i]]);
  }
  _mainPort.send({'type': 'results', 'id': id, 'hits': hits, 'total': total});
}
