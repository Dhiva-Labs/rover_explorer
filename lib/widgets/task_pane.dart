import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/fs_service.dart';
import '../xp/xp_theme.dart';
import 'file_icon.dart';

/// The classic "common tasks" sidebar shown when search is closed.
class TaskPane extends StatelessWidget {
  final List<FileEntry> selection;
  final void Function(String path) onNavigate;
  final VoidCallback onNewFolder;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onCopy;

  const TaskPane({
    super.key,
    required this.selection,
    required this.onNavigate,
    required this.onNewFolder,
    this.onDelete,
    this.onRename,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final home = FsService.homeDir;
    final sep = home.contains('\\') ? '\\' : '/';
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7A9CE0), Color(0xFF6375D6)],
        ),
        border: Border(right: BorderSide(color: Xp.faceDark)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          XpTaskCard(
            title: 'File and Folder Tasks',
            children: [
              XpLink(
                label: 'Make a new folder',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: onNewFolder,
              ),
              if (selection.length == 1)
                XpLink(
                  label:
                      'Rename this ${selection.first.isDir ? 'folder' : 'file'}',
                  onTap: onRename,
                ),
              if (selection.isNotEmpty) ...[
                XpLink(
                  label:
                      'Copy ${selection.length == 1 ? 'this item' : 'these items'}',
                  onTap: onCopy,
                ),
                XpLink(
                  label:
                      'Delete ${selection.length == 1 ? 'this item' : 'these items'}',
                  onTap: onDelete,
                ),
              ],
            ],
          ),
          XpTaskCard(
            title: 'Other Places',
            children: [
              XpLink(
                label: 'Home',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: () => onNavigate(home),
              ),
              XpLink(
                label: 'Documents',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: () => onNavigate('$home${sep}Documents'),
              ),
              XpLink(
                label: 'Downloads',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: () => onNavigate('$home${sep}Downloads'),
              ),
              XpLink(
                label: 'Pictures',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: () => onNavigate('$home${sep}Pictures'),
              ),
              XpLink(
                label: 'Music',
                icon: const FileIconWidget(name: '', isDir: true, size: 14),
                onTap: () => onNavigate('$home${sep}Music'),
              ),
              for (final d in FsService.drives())
                XpLink(
                  label: d,
                  icon: const Icon(
                    Icons.storage,
                    size: 13,
                    color: Color(0xFF5A78B8),
                  ),
                  onTap: () => onNavigate(d),
                ),
            ],
          ),
          if (selection.length == 1)
            XpTaskCard(
              title: 'Details',
              children: [
                Text(
                  selection.first.name,
                  style: Xp.style(size: 11.5, weight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  selection.first.typeLabel,
                  style: Xp.style(size: 11, color: Xp.dimText),
                ),
                if (!selection.first.isDir)
                  Text(
                    selection.first.sizeLabel,
                    style: Xp.style(size: 11, color: Xp.dimText),
                  ),
                Text(
                  'Modified: ${selection.first.modifiedLabel}',
                  style: Xp.style(size: 11, color: Xp.dimText),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
