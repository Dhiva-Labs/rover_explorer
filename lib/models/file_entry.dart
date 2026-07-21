import 'dart:io';

import 'package:path/path.dart' as p;

class FileEntry {
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;

  FileEntry({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  String get extension => isDir ? '' : p.extension(name).toLowerCase();

  static FileEntry? fromEntity(FileSystemEntity e) {
    try {
      final stat = e.statSync();
      final isDir = stat.type == FileSystemEntityType.directory;
      if (stat.type == FileSystemEntityType.notFound) return null;
      return FileEntry(
        path: e.path,
        name: p.basename(e.path),
        isDir: isDir,
        size: isDir ? 0 : stat.size,
        modified: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  String get sizeLabel {
    if (isDir) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get modifiedLabel {
    final m = modified;
    String two(int v) => v.toString().padLeft(2, '0');
    final h = m.hour % 12 == 0 ? 12 : m.hour % 12;
    final ampm = m.hour < 12 ? 'AM' : 'PM';
    return '${two(m.day)}/${two(m.month)}/${m.year} $h:${two(m.minute)} $ampm';
  }

  String get typeLabel {
    if (isDir) return 'File Folder';
    final ext = extension.replaceFirst('.', '').toUpperCase();
    if (ext.isEmpty) return 'File';
    return '$ext File';
  }
}

enum FileKind {
  folder,
  image,
  audio,
  video,
  document,
  code,
  archive,
  exe,
  generic,
}

FileKind kindOf(String name, bool isDir) {
  if (isDir) return FileKind.folder;
  final ext = p.extension(name).toLowerCase();
  const image = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.bmp',
    '.webp',
    '.svg',
    '.ico',
  };
  const audio = {
    '.mp3',
    '.wav',
    '.flac',
    '.ogg',
    '.m4a',
    '.wma',
    '.aac',
    '.opus',
  };
  const video = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.webm',
    '.flv',
    '.m4v',
  };
  const doc = {
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
    '.rtf',
    '.csv',
  };
  const code = {
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.c',
    '.cpp',
    '.h',
    '.java',
    '.kt',
    '.rs',
    '.go',
    '.sh',
    '.html',
    '.css',
    '.json',
    '.xml',
    '.yaml',
    '.yml',
    '.sql',
    '.toml',
  };
  const archive = {
    '.zip',
    '.tar',
    '.gz',
    '.rar',
    '.7z',
    '.xz',
    '.bz2',
    '.deb',
    '.rpm',
    '.apk',
  };
  const exe = {'.exe', '.msi', '.bat', '.cmd', '.appimage', '.bin', '.run'};
  if (image.contains(ext)) return FileKind.image;
  if (audio.contains(ext)) return FileKind.audio;
  if (video.contains(ext)) return FileKind.video;
  if (doc.contains(ext)) return FileKind.document;
  if (code.contains(ext)) return FileKind.code;
  if (archive.contains(ext)) return FileKind.archive;
  if (exe.contains(ext)) return FileKind.exe;
  return FileKind.generic;
}
