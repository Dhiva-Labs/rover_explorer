import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import '../widgets/file_icon.dart';
import '../xp/xp_dialog.dart';
import '../xp/xp_theme.dart';

/// XP-style file/folder properties sheet. Folder sizes are summed in the
/// background so the dialog opens immediately.
Future<void> showPropertiesDialog(
  BuildContext context,
  List<FileEntry> selection,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PropertiesDialog(selection: selection),
  );
}

class _PropertiesDialog extends StatefulWidget {
  final List<FileEntry> selection;
  const _PropertiesDialog({required this.selection});

  @override
  State<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<_PropertiesDialog> {
  int _bytes = 0;
  int _files = 0;
  int _folders = 0;
  bool _counting = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _measure() async {
    var bytes = 0, files = 0, folders = 0;
    for (final e in widget.selection) {
      if (e.isDir) {
        folders++;
        final stack = <String>[e.path];
        while (stack.isNotEmpty) {
          if (_disposed) return;
          final dir = stack.removeLast();
          List<FileSystemEntity> children;
          try {
            children = Directory(dir).listSync(followLinks: false);
          } catch (_) {
            continue;
          }
          for (final c in children) {
            if (c is Directory) {
              folders++;
              stack.add(c.path);
            } else if (c is File) {
              files++;
              try {
                bytes += c.lengthSync();
              } catch (_) {}
            }
          }
          // Yield so the dialog stays responsive on huge trees.
          await Future<void>.delayed(Duration.zero);
        }
      } else {
        files++;
        bytes += e.size;
      }
    }
    if (!_disposed && mounted) {
      setState(() {
        _bytes = bytes;
        _files = files;
        _folders = folders;
        _counting = false;
      });
    }
  }

  static String _fmtBytes(int b) {
    String grouped(int v) {
      final s = v.toString();
      final sb = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) sb.write(',');
        sb.write(s[i]);
      }
      return sb.toString();
    }

    if (b < 1024) return '$b bytes';
    final units = ['KB', 'MB', 'GB', 'TB'];
    var v = b / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(2)} ${units[u]} (${grouped(b)} bytes)';
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.selection.length > 1;
    final first = widget.selection.first;
    final title = multi
        ? '${widget.selection.length} items Properties'
        : '${first.name} Properties';

    String attributes(FileEntry e) {
      final parts = <String>[];
      if (p.basename(e.path).startsWith('.')) parts.add('Hidden');
      if (e.isDir) parts.add('Directory');
      try {
        final st = FileStat.statSync(e.path);
        parts.add('Mode ${st.modeString()}');
      } catch (_) {}
      return parts.isEmpty ? '—' : parts.join(', ');
    }

    return XpDialogShell(
      title: title,
      width: 400,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileIconWidget(
                name: multi ? 'multi' : first.name,
                isDir: multi ? false : first.isDir,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  multi
                      ? '${widget.selection.length} items selected'
                      : first.name,
                  style: Xp.style(size: 13, weight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Xp.faceDark),
          const SizedBox(height: 10),
          if (!multi) ...[
            _row('Type', first.typeLabel),
            _row('Location', p.dirname(first.path)),
          ],
          _row('Size', _counting ? 'Calculating…' : _fmtBytes(_bytes)),
          _row(
            'Contains',
            _counting
                ? 'Calculating…'
                : '$_files file${_files == 1 ? '' : 's'}, '
                      '$_folders folder${_folders == 1 ? '' : 's'}',
          ),
          if (!multi) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: Xp.faceDark),
            const SizedBox(height: 8),
            _row('Modified', first.modifiedLabel),
            _row('Attributes', attributes(first)),
          ],
        ],
      ),
      actions: [XpButton(label: 'OK', onTap: () => Navigator.pop(context))],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: Xp.style(size: 11.5, color: Xp.dimText),
            ),
          ),
          Expanded(child: SelectableText(value, style: Xp.style(size: 11.5))),
        ],
      ),
    );
  }
}
