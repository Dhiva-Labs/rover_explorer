import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

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
///    prefix scoring over lowercased names), never by touching the disk.
class SearchIndexService {
  SendPort? _toIsolate;
  Isolate? _isolate;
  final _resultsController = StreamController<SearchResults>.broadcast();
  final _statusController = StreamController<IndexStatus>.broadcast();
  int _queryCounter = 0;

  Stream<SearchResults> get results => _resultsController.stream;
  Stream<IndexStatus> get status => _statusController.stream;
  IndexStatus lastStatus = const IndexStatus(0, false, false);

  Future<void> start({
    required List<String> roots,
    required String cacheFile,
  }) async {
    final fromIsolate = ReceivePort();
    _isolate = await Isolate.spawn(_indexerMain, fromIsolate.sendPort);
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
            _statusController.add(lastStatus);
          case 'results':
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

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _resultsController.close();
    _statusController.close();
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
}

late SendPort _mainPort;
final _index = _Index();
var _scanning = false;
List<String> _roots = [];
String _cachePath = '';

/// Completes once the on-disk index cache has been read; queries wait on it.
Future<void>? _cacheLoaded;

void _indexerMain(SendPort mainPort) {
  _mainPort = mainPort;
  final port = ReceivePort();
  mainPort.send(port.sendPort);
  port.listen((msg) async {
    if (msg is! Map) return;
    switch (msg['cmd']) {
      case 'init':
        _roots = (msg['roots'] as List).cast<String>();
        _cachePath = msg['cache'] as String;
        // Claimed synchronously so a query arriving during the (async) cache
        // load waits for it instead of racing an empty index.
        final ready = Completer<void>();
        _cacheLoaded = ready.future;
        await _loadCache();
        ready.complete();
        _sendStatus();
        unawaited(_walk());
      case 'rescan':
        unawaited(_walk());
      case 'query':
        final pending = _cacheLoaded;
        if (pending != null) {
          await pending;
        }
        _answer(msg);
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
  _sendStatus();

  final fresh = _Index();
  var sinceYield = 0;

  Future<void> yieldNow() async {
    // Let queued query messages run between directory batches.
    await Future.delayed(Duration.zero);
  }

  for (final root in _roots) {
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
        final isDir = e is Directory;
        if (isDir && p.dirname(e.path) == '/' && _skipDirNames.contains(name)) {
          continue;
        }
        fresh.add(e.path, isDir);
        if (isDir) stack.add(e.path);
        if (++sinceYield >= 4000) {
          sinceYield = 0;
          _mainPort.send({
            'type': 'status',
            'count': fresh.length,
            'scanning': true,
          });
          await yieldNow();
        }
      }
    }
  }

  _index
    ..clear()
    ..paths.addAll(fresh.paths)
    ..namesLower.addAll(fresh.namesLower)
    ..isDirs.addAll(fresh.isDirs);
  _scanning = false;
  _sendStatus();
  await _saveCache();
}

bool _kindMatches(int kind, int i) {
  final k = SearchKind.values[kind];
  if (k == SearchKind.all) return true;
  final isDir = _index.isDirs[i];
  if (k == SearchKind.folders) return isDir;
  if (isDir) return false;
  final name = _index.namesLower[i];
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

void _answer(Map msg) {
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
  final first = tokens.isEmpty ? '' : tokens.first;
  final rest = tokens.length > 1 ? tokens.sublist(1) : const <String>[];
  final underLower = under?.toLowerCase();

  // Parallel lists of matching index positions and their scores (lower wins).
  final scored = <int>[];
  final scores = <int>[];
  var total = 0;

  for (var i = 0; i < _index.length; i++) {
    final name = _index.namesLower[i];

    int score;
    if (first.isEmpty) {
      score = 3;
    } else {
      final pos = name.indexOf(first);
      if (pos < 0) continue;
      if (name == first) {
        score = 0;
      } else if (pos == 0) {
        score = 1;
      } else {
        final prev = name.codeUnitAt(pos - 1);
        final wordStart =
            prev == 0x20 ||
            prev == 0x2E ||
            prev == 0x2D ||
            prev == 0x5F ||
            prev == 0x28;
        score = wordStart ? 2 : 3;
      }
    }

    if (underLower != null || rest.isNotEmpty) {
      final pathLower = _index.paths[i].toLowerCase();
      if (underLower != null && !pathLower.startsWith(underLower)) continue;
      var ok = true;
      for (final t in rest) {
        if (!pathLower.contains(t)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
    }

    if (!_kindMatches(kind, i)) continue;

    total++;
    scored.add(i);
    scores.add(score * 1000 + name.length.clamp(0, 999));
  }

  // Partial sort: indices by score then name length, folders get a nudge up
  // within equal scores by being stable-sorted first.
  final order = List<int>.generate(scored.length, (j) => j);
  order.sort((a, b) => scores[a].compareTo(scores[b]));

  final hits = <List<Object>>[];
  for (var j = 0; j < order.length && hits.length < limit; j++) {
    final i = scored[order[j]];
    hits.add([_index.paths[i], p.basename(_index.paths[i]), _index.isDirs[i]]);
  }
  _mainPort.send({'type': 'results', 'id': id, 'hits': hits, 'total': total});
}
