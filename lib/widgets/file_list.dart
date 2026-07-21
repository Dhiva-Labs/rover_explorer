import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import '../xp/xp_theme.dart';
import 'file_icon.dart';

enum ViewMode { details, icons }

enum FileAction {
  open,
  openLocation,
  cut,
  copy,
  paste,
  delete,
  rename,
  refresh,
  newFolder,
  properties,
}

class FileListView extends StatefulWidget {
  final List<FileEntry> entries;
  final ViewMode mode;
  final bool showPathColumn; // search results show location instead of type
  final void Function(FileEntry) onOpen;
  final void Function(FileAction, List<FileEntry>) onAction;
  final void Function(List<FileEntry>)? onSelectionChanged;

  /// Called when [dragged] items are dropped onto the [target] folder.
  final void Function(List<FileEntry> dragged, FileEntry target)? onDropOn;
  final bool canPaste;

  const FileListView({
    super.key,
    required this.entries,
    required this.mode,
    required this.onOpen,
    required this.onAction,
    this.onSelectionChanged,
    this.onDropOn,
    this.showPathColumn = false,
    this.canPaste = false,
  });

  @override
  State<FileListView> createState() => FileListViewState();
}

class FileListViewState extends State<FileListView> {
  final Set<String> _selected = {};
  int _anchorIndex = -1;
  int _sortCol = 0; // 0 name, 1 size, 2 type/path, 3 modified
  bool _sortAsc = true;

  List<FileEntry> get _sorted {
    final list = List<FileEntry>.from(widget.entries);
    int cmp(FileEntry a, FileEntry b) {
      // Folders always group before files, like classic Explorer.
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final r = switch (_sortCol) {
        1 => a.size.compareTo(b.size),
        2 =>
          widget.showPathColumn
              ? a.path.toLowerCase().compareTo(b.path.toLowerCase())
              : a.typeLabel.compareTo(b.typeLabel),
        3 => a.modified.compareTo(b.modified),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    list.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    return list;
  }

  List<FileEntry> get selectedEntries =>
      widget.entries.where((e) => _selected.contains(e.path)).toList();

  void clearSelection() {
    setState(() => _selected.clear());
    widget.onSelectionChanged?.call([]);
  }

  void selectAll() {
    setState(
      () => _selected
        ..clear()
        ..addAll(widget.entries.map((e) => e.path)),
    );
    _notify();
  }

  void _notify() => widget.onSelectionChanged?.call(selectedEntries);

  void _tapItem(int index, FileEntry e) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    setState(() {
      if (shift && _anchorIndex >= 0) {
        final list = _sorted;
        final lo = index < _anchorIndex ? index : _anchorIndex;
        final hi = index > _anchorIndex ? index : _anchorIndex;
        if (!ctrl) _selected.clear();
        for (var i = lo; i <= hi && i < list.length; i++) {
          _selected.add(list[i].path);
        }
      } else if (ctrl) {
        if (!_selected.remove(e.path)) _selected.add(e.path);
        _anchorIndex = index;
      } else {
        _selected
          ..clear()
          ..add(e.path);
        _anchorIndex = index;
      }
    });
    _notify();
  }

  Future<void> _showContext(Offset globalPos, FileEntry? under) async {
    if (under != null && !_selected.contains(under.path)) {
      setState(() {
        _selected
          ..clear()
          ..add(under.path);
      });
      _notify();
    }
    final sel = selectedEntries;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    PopupMenuItem<FileAction> item(
      FileAction a,
      String label, {
      bool enabled = true,
      bool bold = false,
    }) => PopupMenuItem(
      value: a,
      enabled: enabled,
      height: 26,
      child: Text(
        label,
        style: Xp.style(
          size: 12,
          weight: bold ? FontWeight.bold : FontWeight.normal,
          color: enabled ? Xp.text : Xp.dimText,
        ),
      ),
    );

    final action = await showMenu<FileAction>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF999999)),
        borderRadius: BorderRadius.circular(2),
      ),
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (sel.isNotEmpty) ...[
          item(FileAction.open, 'Open', bold: true),
          if (widget.showPathColumn)
            item(FileAction.openLocation, 'Open Containing Folder'),
          const PopupMenuDivider(height: 6),
          item(FileAction.cut, 'Cut'),
          item(FileAction.copy, 'Copy'),
        ],
        item(FileAction.paste, 'Paste', enabled: widget.canPaste),
        const PopupMenuDivider(height: 6),
        if (sel.isNotEmpty) ...[
          item(FileAction.delete, 'Delete'),
          item(FileAction.rename, 'Rename', enabled: sel.length == 1),
          const PopupMenuDivider(height: 6),
        ],
        item(FileAction.newFolder, 'New Folder'),
        item(FileAction.refresh, 'Refresh'),
        if (sel.isNotEmpty) ...[
          const PopupMenuDivider(height: 6),
          item(FileAction.properties, 'Properties'),
        ],
      ],
    );
    if (action != null) widget.onAction(action, sel);
  }

  /// Wraps a row/cell so items can be dragged out, and folders accept drops.
  Widget _dragWrap(FileEntry e, Widget child) {
    final payload = _selected.contains(e.path) && _selected.length > 1
        ? selectedEntries
        : [e];

    final draggable = Draggable<List<FileEntry>>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragGhost(items: payload),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );

    if (!e.isDir || widget.onDropOn == null) return draggable;

    return DragTarget<List<FileEntry>>(
      onWillAcceptWithDetails: (d) =>
          d.data.every((x) => !p.equals(x.path, e.path)),
      onAcceptWithDetails: (d) => widget.onDropOn!(d.data, e),
      builder: (context, candidate, rejected) => Container(
        foregroundDecoration: candidate.isNotEmpty
            ? BoxDecoration(
                border: Border.all(color: Xp.selection, width: 2),
                color: Xp.selection.withValues(alpha: 0.15),
              )
            : null,
        child: draggable,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final sel = selectedEntries;
        if (event.logicalKey == LogicalKeyboardKey.delete && sel.isNotEmpty) {
          widget.onAction(FileAction.delete, sel);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.f2 && sel.length == 1) {
          widget.onAction(FileAction.rename, sel);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.f5) {
          widget.onAction(FileAction.refresh, const []);
          return KeyEventResult.handled;
        }
        if (ctrl &&
            event.logicalKey == LogicalKeyboardKey.keyC &&
            sel.isNotEmpty) {
          widget.onAction(FileAction.copy, sel);
          return KeyEventResult.handled;
        }
        if (ctrl &&
            event.logicalKey == LogicalKeyboardKey.keyX &&
            sel.isNotEmpty) {
          widget.onAction(FileAction.cut, sel);
          return KeyEventResult.handled;
        }
        if (ctrl &&
            event.logicalKey == LogicalKeyboardKey.keyV &&
            widget.canPaste) {
          widget.onAction(FileAction.paste, const []);
          return KeyEventResult.handled;
        }
        if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
          setState(
            () => _selected
              ..clear()
              ..addAll(widget.entries.map((e) => e.path)),
          );
          _notify();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter && sel.isNotEmpty) {
          if (HardwareKeyboard.instance.isAltPressed) {
            widget.onAction(FileAction.properties, sel);
          } else if (sel.length == 1) {
            widget.onOpen(sel.first);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: clearSelection,
        onSecondaryTapUp: (d) => _showContext(d.globalPosition, null),
        child: Container(
          color: Colors.white,
          child: widget.mode == ViewMode.details ? _details() : _icons(),
        ),
      ),
    );
  }

  // ------------------------------ details view ---------------------------

  static const _nameW = 260.0;
  static const _sizeW = 90.0;
  static const _typeW = 180.0;
  static const _dateW = 150.0;

  Widget _headerCell(
    String label,
    int col,
    double width, {
    AlignmentGeometry align = Alignment.centerLeft,
  }) {
    return GestureDetector(
      onTap: () => setState(() {
        if (_sortCol == col) {
          _sortAsc = !_sortAsc;
        } else {
          _sortCol = col;
          _sortAsc = true;
        }
      }),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: const BoxDecoration(
          color: Xp.face,
          border: Border(
            right: BorderSide(color: Color(0xFFD8D5C8)),
            bottom: BorderSide(color: Xp.faceDark),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: align,
                child: Text(label, style: Xp.style(size: 11.5)),
              ),
            ),
            if (_sortCol == col)
              Icon(
                _sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 14,
                color: const Color(0xFF7A7256),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details() {
    final list = _sorted;
    final typeHeader = widget.showPathColumn ? 'In Folder' : 'Type';
    final totalW =
        _nameW + _sizeW + (widget.showPathColumn ? 320 : _typeW) + _dateW + 20;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = totalW > constraints.maxWidth
            ? totalW
            : constraints.maxWidth;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch},
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _headerCell('Name', 0, _nameW),
                      _headerCell(
                        'Size',
                        1,
                        _sizeW,
                        align: Alignment.centerRight,
                      ),
                      _headerCell(
                        typeHeader,
                        2,
                        widget.showPathColumn ? 320 : _typeW,
                      ),
                      Expanded(child: _headerCell('Date Modified', 3, _dateW)),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemExtent: 22,
                      itemBuilder: (context, i) {
                        final e = list[i];
                        final selected = _selected.contains(e.path);
                        return _dragWrap(
                          e,
                          GestureDetector(
                            onTap: () => _tapItem(i, e),
                            onDoubleTap: () => widget.onOpen(e),
                            onSecondaryTapUp: (d) =>
                                _showContext(d.globalPosition, e),
                            child: Container(
                              color: selected
                                  ? Xp.selection
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: _nameW,
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 4),
                                        FileIconWidget(
                                          name: e.name,
                                          isDir: e.isDir,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            e.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Xp.style(
                                              size: 12,
                                              color: selected
                                                  ? Colors.white
                                                  : Xp.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: _sizeW,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        e.sizeLabel,
                                        textAlign: TextAlign.right,
                                        style: Xp.style(
                                          size: 11.5,
                                          color: selected
                                              ? Colors.white
                                              : Xp.dimText,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: widget.showPathColumn ? 320 : _typeW,
                                    child: Text(
                                      widget.showPathColumn
                                          ? p.dirname(e.path)
                                          : e.typeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Xp.style(
                                        size: 11.5,
                                        color: selected
                                            ? Colors.white
                                            : Xp.dimText,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: _dateW,
                                    child: Text(
                                      e.modifiedLabel,
                                      maxLines: 1,
                                      style: Xp.style(
                                        size: 11.5,
                                        color: selected
                                            ? Colors.white
                                            : Xp.dimText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------ icons view -----------------------------

  Widget _icons() {
    final list = _sorted;
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        mainAxisExtent: 86,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final e = list[i];
        final selected = _selected.contains(e.path);
        return _dragWrap(
          e,
          GestureDetector(
            onTap: () => _tapItem(i, e),
            onDoubleTap: () => widget.onOpen(e),
            onSecondaryTapUp: (d) => _showContext(d.globalPosition, e),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: selected ? Xp.selectionFaded : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FileIconWidget(name: e.name, isDir: e.isDir, size: 34),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Xp.selection : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    e.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Xp.style(
                      size: 11,
                      color: selected ? Colors.white : Xp.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Floating label shown under the cursor while dragging files.
class _DragGhost extends StatelessWidget {
  final List<FileEntry> items;
  const _DragGhost({required this.items});

  @override
  Widget build(BuildContext context) {
    final label = items.length == 1
        ? items.first.name
        : '${items.length} items';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Xp.selection.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white70),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileIconWidget(
              name: items.first.name,
              isDir: items.first.isDir,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(label, style: Xp.style(size: 11.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
