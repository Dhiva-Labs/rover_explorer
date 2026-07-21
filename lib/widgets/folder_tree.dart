import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/fs_service.dart';
import '../widgets/file_icon.dart';
import '../xp/xp_theme.dart';

class _TreeNode {
  final String path;
  final String label;
  final int depth;
  List<_TreeNode>? children; // null until expanded once
  bool expanded = false;

  _TreeNode(this.path, this.label, this.depth);
}

/// The classic "Folders" navigation pane: a lazily-loaded, expandable tree
/// with the dotted-line look of XP Explorer.
class FolderTreePane extends StatefulWidget {
  final String currentPath;
  final bool showHidden;
  final ValueChanged<String> onNavigate;
  final VoidCallback onClose;

  const FolderTreePane({
    super.key,
    required this.currentPath,
    required this.onNavigate,
    required this.onClose,
    this.showHidden = false,
  });

  @override
  State<FolderTreePane> createState() => _FolderTreePaneState();
}

class _FolderTreePaneState extends State<FolderTreePane> {
  final List<_TreeNode> _roots = [];
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _buildRoots();
    _revealCurrent();
  }

  @override
  void didUpdateWidget(FolderTreePane old) {
    super.didUpdateWidget(old);
    if (old.currentPath != widget.currentPath) _revealCurrent();
    if (old.showHidden != widget.showHidden) {
      for (final r in _roots) {
        _collapseAll(r);
      }
      setState(_revealCurrent);
    }
  }

  void _collapseAll(_TreeNode n) {
    n.children = null;
    n.expanded = false;
  }

  void _buildRoots() {
    final home = FsService.homeDir;
    _roots
      ..clear()
      ..add(_TreeNode(home, 'Home', 0));
    for (final d in FsService.drives()) {
      if (p.equals(d, home)) continue;
      _roots.add(_TreeNode(d, d, 0));
    }
  }

  List<_TreeNode> _loadChildren(_TreeNode node) {
    final out = <_TreeNode>[];
    try {
      final dirs =
          Directory(node.path)
              .listSync(followLinks: false)
              .whereType<Directory>()
              .where(
                (d) => widget.showHidden || !p.basename(d.path).startsWith('.'),
              )
              .toList()
            ..sort(
              (a, b) => p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase()),
            );
      for (final d in dirs) {
        out.add(_TreeNode(d.path, p.basename(d.path), node.depth + 1));
      }
    } catch (_) {
      // Unreadable directory: leave it childless rather than failing.
    }
    return out;
  }

  void _toggle(_TreeNode node) {
    setState(() {
      if (node.expanded) {
        node.expanded = false;
      } else {
        node.children ??= _loadChildren(node);
        node.expanded = true;
      }
    });
  }

  /// Expand the tree down to [widget.currentPath] so the active folder shows.
  void _revealCurrent() {
    final target = widget.currentPath;
    for (final root in _roots) {
      if (!p.isWithin(root.path, target) && !p.equals(root.path, target)) {
        continue;
      }
      var node = root;
      while (!p.equals(node.path, target)) {
        node.children ??= _loadChildren(node);
        node.expanded = true;
        final next = node.children!.firstWhere(
          (c) => p.equals(c.path, target) || p.isWithin(c.path, target),
          orElse: () => node,
        );
        if (identical(next, node)) break;
        node = next;
      }
      break;
    }
    if (mounted) setState(() {});
  }

  List<_TreeNode> get _visible {
    final out = <_TreeNode>[];
    void walk(_TreeNode n) {
      out.add(n);
      if (n.expanded && n.children != null) {
        for (final c in n.children!) {
          walk(c);
        }
      }
    }

    for (final r in _roots) {
      walk(r);
    }
    return out;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Xp.faceDark)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            decoration: const BoxDecoration(
              color: Xp.face,
              border: Border(bottom: BorderSide(color: Xp.faceDark)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Folders',
                    style: Xp.style(size: 12, weight: FontWeight.bold),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8E4F8),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF7A96DF)),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: Color(0xFF39507C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: rows.length,
              itemExtent: 20,
              itemBuilder: (context, i) {
                final n = rows[i];
                final selected = p.equals(n.path, widget.currentPath);
                return _TreeRow(
                  node: n,
                  selected: selected,
                  onToggle: () => _toggle(n),
                  onTap: () => widget.onNavigate(n.path),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  final _TreeNode node;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  const _TreeRow({
    required this.node,
    required this.selected,
    required this.onToggle,
    required this.onTap,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onToggle,
        child: Container(
          padding: EdgeInsets.only(left: 4.0 + n.depth * 14),
          color: widget.selected
              ? Xp.selection
              : _hover
              ? Xp.selectionFaded
              : Colors.transparent,
          child: Row(
            children: [
              GestureDetector(
                onTap: widget.onToggle,
                child: SizedBox(
                  width: 14,
                  height: 20,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF9A9A9A)),
                      ),
                      child: Icon(
                        n.expanded ? Icons.remove : Icons.add,
                        size: 8,
                        color: const Color(0xFF2B4E8C),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              FileIconWidget(name: n.label, isDir: true, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  n.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Xp.style(
                    size: 11.5,
                    color: widget.selected ? Colors.white : Xp.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
