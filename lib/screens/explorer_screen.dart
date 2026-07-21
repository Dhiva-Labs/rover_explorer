import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_info.dart';
import '../dialogs/about_dialog.dart';
import '../dialogs/properties_dialog.dart';
import '../dialogs/settings_dialog.dart';
import '../models/file_entry.dart';
import '../services/fs_service.dart';
import '../services/search_index.dart';
import '../services/sound_service.dart';
import '../widgets/file_icon.dart';
import '../widgets/file_list.dart';
import '../widgets/folder_tree.dart';
import '../widgets/rover_dog.dart';
import '../widgets/search_pane.dart';
import '../widgets/task_pane.dart';
import '../widgets/xp_menu_bar.dart';
import '../xp/xp_dialog.dart';
import '../xp/xp_theme.dart';

class ExplorerScreen extends StatefulWidget {
  final SearchIndexService index;
  const ExplorerScreen({super.key, required this.index});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  String _path = FsService.homeDir;
  List<FileEntry> _entries = [];
  String? _error;
  final List<String> _back = [];
  final List<String> _forward = [];
  final List<String> _recent = [];

  ViewMode _viewMode = ViewMode.details;
  RoverSettings _settings = RoverSettings();
  bool _showFolderTree = false;

  // search state
  bool _searchOpen = false;
  bool _showingResults = false;
  List<FileEntry> _results = [];
  int? _resultTotal;
  DogMood _mood = DogMood.idle;
  int _pendingQueryId = -1;
  SearchQuerySpec? _lastSpec;
  StreamSubscription<SearchResults>? _resultsSub;
  StreamSubscription<IndexStatus>? _statusSub;
  IndexStatus _indexStatus = const IndexStatus(0, false, false);

  // clipboard
  List<String> _clipboard = [];
  bool _clipIsCut = false;

  List<FileEntry> _selection = [];
  final _listKey = GlobalKey<FileListViewState>();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _indexStatus = widget.index.lastStatus;
    _resultsSub = widget.index.results.listen(_onResults);
    _statusSub = widget.index.status.listen((s) {
      if (mounted) setState(() => _indexStatus = s);
    });
    _load(_path);
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _statusSub?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  // ------------------------------ navigation -----------------------------

  void _pushRecent(String path) {
    _recent.remove(path);
    _recent.insert(0, path);
    if (_recent.length > 10) _recent.removeRange(10, _recent.length);
  }

  void _load(String path, {bool pushHistory = false}) {
    List<FileEntry>? entries;
    String? error;
    try {
      entries = FsService.list(path, showHidden: _settings.showHidden);
    } catch (e) {
      error = 'Cannot access this folder.\n$e';
    }
    setState(() {
      if (pushHistory && path != _path) {
        _back.add(_path);
        _forward.clear();
      }
      _path = path;
      _entries = entries ?? [];
      _error = error;
      _showingResults = false;
      _selection = [];
      _addressController.text = path;
      if (error == null) _pushRecent(path);
    });
    _listKey.currentState?.clearSelection();
  }

  void _goBack() {
    if (_back.isEmpty) return;
    _forward.add(_path);
    _load(_back.removeLast());
  }

  void _goForward() {
    if (_forward.isEmpty) return;
    _back.add(_path);
    _load(_forward.removeLast());
  }

  void _goUp() {
    final parent = p.dirname(_path);
    if (parent == _path) return;
    _load(parent, pushHistory: true);
  }

  // ------------------------------- search --------------------------------

  void _runQuery(SearchQuerySpec spec) {
    _lastSpec = spec;
    if (spec.text.trim().isEmpty && spec.kind == SearchKind.all) {
      setState(() {
        _showingResults = false;
        _results = [];
        _resultTotal = null;
        _mood = DogMood.idle;
      });
      return;
    }
    setState(() => _mood = DogMood.searching);
    _pendingQueryId = widget.index.query(
      spec.text,
      kind: spec.kind,
      underPath: spec.currentFolderOnly ? _path : null,
    );
  }

  void _onResults(SearchResults r) {
    if (r.queryId != _pendingQueryId || !_searchOpen) return;
    final entries = <FileEntry>[];
    for (final h in r.hits) {
      try {
        final stat = FileStat.statSync(h.path);
        entries.add(
          FileEntry(
            path: h.path,
            name: h.name,
            isDir: h.isDir,
            size: h.isDir ? 0 : stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        entries.add(
          FileEntry(
            path: h.path,
            name: h.name,
            isDir: h.isDir,
            size: 0,
            modified: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }
    setState(() {
      _results = entries;
      _resultTotal = r.totalMatches;
      _showingResults = true;
      _mood = r.hits.isEmpty ? DogMood.idle : DogMood.found;
    });
  }

  // ------------------------------ actions --------------------------------

  Future<void> _open(FileEntry e) async {
    if (e.isDir) {
      _load(e.path, pushHistory: true);
    } else {
      await FsService.openWithOs(e.path);
    }
  }

  Future<void> _handleAction(FileAction action, List<FileEntry> sel) async {
    switch (action) {
      case FileAction.open:
        if (sel.isNotEmpty) await _open(sel.first);
      case FileAction.openLocation:
        if (sel.isNotEmpty) {
          setState(() => _searchOpen = false);
          _load(p.dirname(sel.first.path), pushHistory: true);
        }
      case FileAction.copy:
        setState(() {
          _clipboard = sel.map((e) => e.path).toList();
          _clipIsCut = false;
        });
      case FileAction.cut:
        setState(() {
          _clipboard = sel.map((e) => e.path).toList();
          _clipIsCut = true;
        });
      case FileAction.paste:
        await _paste();
      case FileAction.delete:
        await _deleteSelected(sel);
      case FileAction.rename:
        if (sel.length == 1) await _renameDialog(sel.first);
      case FileAction.refresh:
        _refresh();
      case FileAction.newFolder:
        await _newFolder();
      case FileAction.properties:
        if (sel.isNotEmpty && mounted) {
          await showPropertiesDialog(context, sel);
        }
    }
  }

  Future<void> _paste() async {
    if (_clipboard.isEmpty) return;
    final errors = <String>[];
    for (final src in _clipboard) {
      try {
        if (_clipIsCut) {
          await FsService.moveInto(src, _path);
        } else {
          await FsService.copyInto(src, _path);
        }
      } catch (e) {
        errors.add('${p.basename(src)}: $e');
      }
    }
    if (_clipIsCut) _clipboard = [];
    _load(_path);
    if (errors.isNotEmpty && mounted) {
      await xpAlert(
        context,
        'Some items could not be pasted:\n'
        '${errors.take(5).join('\n')}',
      );
    }
  }

  /// Drag & drop: move dropped items into [target].
  Future<void> _dropOnFolder(List<FileEntry> dragged, FileEntry target) async {
    final errors = <String>[];
    for (final e in dragged) {
      if (p.equals(e.path, target.path)) continue;
      if (e.isDir && p.isWithin(e.path, target.path)) {
        errors.add('${e.name}: cannot move a folder into itself');
        continue;
      }
      try {
        await FsService.moveInto(e.path, target.path);
      } catch (err) {
        errors.add('${e.name}: $err');
      }
    }
    _refresh();
    if (errors.isNotEmpty && mounted) {
      await xpAlert(
        context,
        'Some items could not be moved:\n${errors.take(5).join('\n')}',
      );
    }
  }

  Future<void> _deleteSelected(List<FileEntry> sel) async {
    if (sel.isEmpty) return;
    final what = sel.length == 1
        ? "'${sel.first.name}'"
        : '${sel.length} items';
    final ok = await xpConfirm(
      context,
      'Confirm Delete',
      'Are you sure you want to permanently delete $what?',
    );
    if (ok != true) return;
    final errors = <String>[];
    for (final e in sel) {
      try {
        await FsService.delete(e.path);
      } catch (err) {
        errors.add('${e.name}: $err');
      }
    }
    _refresh();
    if (errors.isNotEmpty && mounted) {
      await xpAlert(
        context,
        'Some items could not be deleted:\n${errors.take(5).join('\n')}',
      );
    }
  }

  Future<void> _renameDialog(FileEntry e) async {
    final newName = await xpPrompt(
      context,
      title: 'Rename',
      label: 'New name:',
      initial: e.name,
    );
    if (newName == null || newName.isEmpty || newName == e.name) return;
    try {
      await FsService.rename(e.path, newName);
    } catch (err) {
      if (mounted) await xpAlert(context, 'Could not rename: $err');
    }
    _refresh();
  }

  Future<void> _newFolder() async {
    try {
      await FsService.newFolder(_path);
      _load(_path);
    } catch (e) {
      if (mounted) await xpAlert(context, 'Could not create folder: $e');
    }
  }

  void _refresh() {
    if (_showingResults && _lastSpec != null) {
      _runQuery(_lastSpec!);
    } else {
      _load(_path);
    }
  }

  Future<void> _openSettings() async {
    final updated = await showSettingsDialog(
      context,
      current: _settings,
      indexedItems: _indexStatus.count,
      indexing: _indexStatus.scanning,
      onRebuildIndex: widget.index.rescan,
    );
    if (updated == null) return;
    final hiddenChanged = updated.showHidden != _settings.showHidden;
    setState(() => _settings = updated);
    SoundService.muted = !updated.soundEnabled;
    if (hiddenChanged) _load(_path);
  }

  // ------------------------------- menus ---------------------------------

  List<XpMenu> _menus() {
    final sel = _selection;
    return [
      XpMenu(
        'File',
        () => [
          XpMenuEntry(
            'Open',
            onTap: sel.isEmpty ? null : () => _open(sel.first),
            shortcut: 'Enter',
          ),
          XpMenuEntry(
            'New Folder',
            onTap: _newFolder,
            shortcut: 'Ctrl+Shift+N',
          ),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Rename',
            onTap: sel.length == 1 ? () => _renameDialog(sel.first) : null,
            shortcut: 'F2',
          ),
          XpMenuEntry(
            'Delete',
            onTap: sel.isEmpty ? null : () => _deleteSelected(sel),
            shortcut: 'Del',
          ),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Properties',
            onTap: sel.isEmpty
                ? null
                : () => showPropertiesDialog(context, sel),
            shortcut: 'Alt+Enter',
          ),
          XpMenuEntry.separator,
          XpMenuEntry('Close', onTap: () => exit(0), shortcut: 'Alt+F4'),
        ],
      ),
      XpMenu(
        'Edit',
        () => [
          XpMenuEntry(
            'Cut',
            onTap: sel.isEmpty
                ? null
                : () => _handleAction(FileAction.cut, sel),
            shortcut: 'Ctrl+X',
          ),
          XpMenuEntry(
            'Copy',
            onTap: sel.isEmpty
                ? null
                : () => _handleAction(FileAction.copy, sel),
            shortcut: 'Ctrl+C',
          ),
          XpMenuEntry(
            'Paste',
            onTap: _clipboard.isEmpty || _showingResults ? null : _paste,
            shortcut: 'Ctrl+V',
          ),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Select All',
            onTap: () => _listKey.currentState?.selectAll(),
            shortcut: 'Ctrl+A',
          ),
        ],
      ),
      XpMenu(
        'View',
        () => [
          XpMenuEntry(
            'Icons',
            onTap: () => setState(() => _viewMode = ViewMode.icons),
            checked: _viewMode == ViewMode.icons,
            radio: true,
          ),
          XpMenuEntry(
            'Details',
            onTap: () => setState(() => _viewMode = ViewMode.details),
            checked: _viewMode == ViewMode.details,
            radio: true,
          ),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Explorer Bar: Folders',
            onTap: _toggleFolderTree,
            checked: _showFolderTree,
          ),
          XpMenuEntry(
            'Explorer Bar: Search',
            onTap: _toggleSearch,
            checked: _searchOpen,
          ),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Show hidden files',
            onTap: () {
              setState(() => _settings.showHidden = !_settings.showHidden);
              _load(_path);
            },
            checked: _settings.showHidden,
          ),
          XpMenuEntry('Refresh', onTap: _refresh, shortcut: 'F5'),
        ],
      ),
      XpMenu(
        'Go',
        () => [
          XpMenuEntry(
            'Back',
            onTap: _back.isEmpty ? null : _goBack,
            shortcut: 'Alt+Left',
          ),
          XpMenuEntry(
            'Forward',
            onTap: _forward.isEmpty ? null : _goForward,
            shortcut: 'Alt+Right',
          ),
          XpMenuEntry('Up One Level', onTap: _goUp, shortcut: 'Alt+Up'),
          XpMenuEntry.separator,
          XpMenuEntry(
            'Home',
            onTap: () => _load(FsService.homeDir, pushHistory: true),
          ),
          XpMenuEntry.separator,
          if (_recent.length <= 1)
            const XpMenuEntry('(no recent locations)', enabled: false)
          else
            ..._recent
                .skip(1)
                .take(8)
                .map(
                  (r) => XpMenuEntry(
                    _shortenPath(r),
                    onTap: () => _load(r, pushHistory: true),
                  ),
                ),
        ],
      ),
      XpMenu(
        'Tools',
        () => [
          XpMenuEntry('Folder Options…', onTap: _openSettings),
          XpMenuEntry('Rebuild search index', onTap: widget.index.rescan),
        ],
      ),
      XpMenu(
        'Help',
        () => [
          XpMenuEntry(
            'About ${AppInfo.name}',
            onTap: () =>
                showRoverAboutDialog(context, indexedItems: _indexStatus.count),
          ),
        ],
      ),
    ];
  }

  static String _shortenPath(String path) {
    final home = FsService.homeDir;
    var shown = path;
    if (p.isWithin(home, path)) {
      shown = '~${Platform.pathSeparator}${p.relative(path, from: home)}';
    } else if (p.equals(home, path)) {
      shown = '~';
    }
    return shown.length <= 46
        ? shown
        : '…${shown.substring(shown.length - 45)}';
  }

  void _toggleFolderTree() {
    setState(() {
      _showFolderTree = !_showFolderTree;
      if (_showFolderTree) {
        _searchOpen = false;
        _showingResults = false;
        _mood = DogMood.idle;
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (_searchOpen) {
        _showFolderTree = false;
      } else {
        _showingResults = false;
        _mood = DogMood.idle;
      }
    });
  }

  // ------------------------------- build ---------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final alt = HardwareKeyboard.instance.isAltPressed;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        if (alt && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _goBack();
          return KeyEventResult.handled;
        }
        if (alt && event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _goForward();
          return KeyEventResult.handled;
        }
        if ((alt && event.logicalKey == LogicalKeyboardKey.arrowUp) ||
            event.logicalKey == LogicalKeyboardKey.backspace) {
          _goUp();
          return KeyEventResult.handled;
        }
        if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyN) {
          _newFolder();
          return KeyEventResult.handled;
        }
        if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
          if (!_searchOpen) _toggleSearch();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          XpMenuBar(menus: _menus()),
          _toolbar(),
          _addressBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_searchOpen)
                  SearchPane(
                    onQuery: _runQuery,
                    onClose: _toggleSearch,
                    mood: _mood,
                    indexStatus: _indexStatus,
                    currentFolder: _path,
                    resultCount: _showingResults ? _resultTotal : null,
                    showCompanion: _settings.companionEnabled,
                  )
                else if (_showFolderTree)
                  FolderTreePane(
                    currentPath: _path,
                    showHidden: _settings.showHidden,
                    onNavigate: (path) => _load(path, pushHistory: true),
                    onClose: _toggleFolderTree,
                  )
                else
                  TaskPane(
                    selection: _selection,
                    onNavigate: (path) => _load(path, pushHistory: true),
                    onNewFolder: _newFolder,
                    onDelete: _selection.isEmpty
                        ? null
                        : () => _deleteSelected(_selection),
                    onRename: _selection.length == 1
                        ? () => _renameDialog(_selection.first)
                        : null,
                    onCopy: _selection.isEmpty
                        ? null
                        : () => _handleAction(FileAction.copy, _selection),
                  ),
                Expanded(
                  child: _error != null && !_showingResults
                      ? Container(
                          color: Colors.white,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.report_problem,
                                size: 34,
                                color: Color(0xFFC08A2E),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: Xp.style(size: 12, color: Xp.dimText),
                              ),
                              const SizedBox(height: 12),
                              XpButton(
                                label: 'Go to Home',
                                onTap: () {
                                  _load(FsService.homeDir, pushHistory: true);
                                },
                              ),
                            ],
                          ),
                        )
                      : FileListView(
                          key: _listKey,
                          entries: _showingResults ? _results : _entries,
                          mode: _viewMode,
                          showPathColumn: _showingResults,
                          canPaste: _clipboard.isNotEmpty && !_showingResults,
                          onOpen: _open,
                          onAction: _handleAction,
                          onDropOn: _showingResults ? null : _dropOnFolder,
                          onSelectionChanged: (sel) =>
                              setState(() => _selection = sel),
                        ),
                ),
              ],
            ),
          ),
          _statusBar(),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: Xp.toolbarGradient,
        border: Border(bottom: BorderSide(color: Color(0xFF15489C))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          XpToolButton(
            icon: _navCircle(Icons.arrow_back),
            label: 'Back',
            tooltip: 'Back (Alt+Left)',
            onTap: _back.isEmpty ? null : _goBack,
          ),
          XpToolButton(
            icon: _navCircle(Icons.arrow_forward),
            tooltip: 'Forward (Alt+Right)',
            onTap: _forward.isEmpty ? null : _goForward,
          ),
          XpToolButton(
            icon: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
            tooltip: 'Up one level (Alt+Up)',
            onTap: _goUp,
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white30,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          XpToolButton(
            icon: Stack(
              alignment: Alignment.bottomRight,
              children: [
                const Icon(Icons.search, size: 18, color: Colors.white),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6C13C),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            label: 'Search',
            active: _searchOpen,
            tooltip: 'Search Companion (Ctrl+F)',
            onTap: _toggleSearch,
          ),
          XpToolButton(
            icon: const Icon(Icons.account_tree, size: 18, color: Colors.white),
            label: 'Folders',
            active: _showFolderTree,
            tooltip: 'Folder tree',
            onTap: _toggleFolderTree,
          ),
          XpToolButton(
            icon: Icon(
              _viewMode == ViewMode.details ? Icons.grid_view : Icons.view_list,
              size: 18,
              color: Colors.white,
            ),
            label: 'Views',
            tooltip: 'Toggle icons / details',
            onTap: () => setState(
              () => _viewMode = _viewMode == ViewMode.details
                  ? ViewMode.icons
                  : ViewMode.details,
            ),
          ),
          XpToolButton(
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
            tooltip: 'Refresh (F5)',
            onTap: _refresh,
          ),
          XpToolButton(
            icon: Icon(
              _settings.showHidden ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: Colors.white,
            ),
            tooltip: 'Show hidden files',
            active: _settings.showHidden,
            onTap: () {
              setState(() => _settings.showHidden = !_settings.showHidden);
              _load(_path);
            },
          ),
          const Spacer(),
          if (!_searchOpen && _settings.companionEnabled)
            GestureDetector(
              onTap: _toggleSearch,
              child: const Tooltip(
                message: 'Woof! Click me to search.',
                child: RoverDog(
                  size: 34,
                  mood: DogMood.idle,
                  interactive: false,
                ),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _navCircle(IconData icon) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF8FD18F), Color(0xFF2E8B2E)],
      ),
      border: Border.all(color: Colors.white70),
    ),
    child: Icon(icon, size: 15, color: Colors.white),
  );

  Widget _addressBar() {
    return Container(
      color: Xp.face,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          Text('Address', style: Xp.style(size: 11.5, color: Xp.dimText)),
          const SizedBox(width: 8),
          Expanded(
            child: XpSunken(
              child: Row(
                children: [
                  FileIconWidget(
                    name: p.basename(_path),
                    isDir: true,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      style: Xp.style(size: 12),
                      onSubmitted: (v) => _navigateToTyped(v),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 5),
                      ),
                    ),
                  ),
                  _RecentDropdown(
                    recent: _recent,
                    shorten: _shortenPath,
                    onPick: (path) => _load(path, pushHistory: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          XpButton(
            label: 'Go',
            onTap: () => _navigateToTyped(_addressController.text),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToTyped(String value) async {
    final t = value.trim();
    if (t.isNotEmpty && Directory(t).existsSync()) {
      _load(t, pushHistory: true);
      return;
    }
    if (t.isNotEmpty && File(t).existsSync()) {
      await FsService.openWithOs(t);
      _addressController.text = _path;
      return;
    }
    if (mounted) {
      await xpAlert(context, "Cannot find '$t'. Check the path and try again.");
    }
    _addressController.text = _path;
  }

  Widget _statusBar() {
    final items = _showingResults ? _results : _entries;
    final selText = _selection.isEmpty
        ? '${items.length} object${items.length == 1 ? '' : 's'}'
        : '${_selection.length} selected';
    final idx = _indexStatus;
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: Xp.statusBg,
        border: Border(top: BorderSide(color: Xp.faceDark)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(selText, style: Xp.style(size: 11.5)),
          if (_showingResults &&
              _resultTotal != null &&
              _resultTotal! > _results.length) ...[
            const SizedBox(width: 12),
            Text(
              'showing first ${_results.length} of $_resultTotal matches',
              style: Xp.style(size: 11, color: Xp.dimText),
            ),
          ],
          if (_clipboard.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              '${_clipboard.length} item${_clipboard.length == 1 ? '' : 's'} '
              'ready to ${_clipIsCut ? 'move' : 'copy'}',
              style: Xp.style(size: 11, color: Xp.dimText),
            ),
          ],
          const Spacer(),
          Text(
            !idx.started
                ? ''
                : idx.scanning
                ? 'Indexing… ${idx.count} items'
                : 'Search index: ${idx.count} items',
            style: Xp.style(size: 11, color: Xp.dimText),
          ),
        ],
      ),
    );
  }
}

/// Small arrow at the right of the address bar listing recent locations.
class _RecentDropdown extends StatelessWidget {
  final List<String> recent;
  final String Function(String) shorten;
  final ValueChanged<String> onPick;
  const _RecentDropdown({
    required this.recent,
    required this.shorten,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          if (recent.isEmpty) return;
          final box = context.findRenderObject() as RenderBox;
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          final pos = box.localToGlobal(
            Offset(0, box.size.height),
            ancestor: overlay,
          );
          final picked = await showMenu<String>(
            context: context,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFF999999)),
              borderRadius: BorderRadius.circular(2),
            ),
            position: RelativeRect.fromLTRB(
              pos.dx - 220,
              pos.dy,
              overlay.size.width - pos.dx,
              0,
            ),
            items: [
              for (final r in recent.take(10))
                PopupMenuItem<String>(
                  value: r,
                  height: 26,
                  child: Row(
                    children: [
                      const FileIconWidget(name: '', isDir: true, size: 14),
                      const SizedBox(width: 6),
                      Text(shorten(r), style: Xp.style(size: 11.5)),
                    ],
                  ),
                ),
            ],
          );
          if (picked != null) onPick(picked);
        },
        child: const Icon(
          Icons.arrow_drop_down,
          size: 18,
          color: Color(0xFF39507C),
        ),
      ),
    );
  }
}
