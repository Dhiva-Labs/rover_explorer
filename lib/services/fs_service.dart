import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import 'win_attributes.dart';

/// Plain filesystem operations: listing, drives, open-with-OS, clipboard ops.
class FsService {
  static String get homeDir =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      (Platform.isWindows ? 'C:\\' : '/');

  static String get rootDir => Platform.isWindows ? 'C:\\' : '/';

  static List<String>? _drivesCache;
  static DateTime _drivesCachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// On Windows, enumerate available drive letters. On Linux, common mounts.
  ///
  /// Called from widget builds, so the result is cached for a few seconds:
  /// probing 26 drive letters (or a slow network mount) on every rebuild
  /// would stall the UI.
  static List<String> drives() {
    final now = DateTime.now();
    final cached = _drivesCache;
    if (cached != null && now.difference(_drivesCachedAt).inSeconds < 5) {
      return cached;
    }
    _drivesCachedAt = now;
    return _drivesCache = _probeDrives();
  }

  static List<String> _probeDrives() {
    if (Platform.isWindows) {
      final out = <String>[];
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final root = '${String.fromCharCode(c)}:\\';
        try {
          if (Directory(root).existsSync()) out.add(root);
        } on FileSystemException {
          // A drive with no media (empty card reader or DVD drive) throws
          // "The device is not ready" instead of reporting false.
        }
      }
      return out;
    }
    final out = <String>['/'];
    for (final base in [
      '/media/${Platform.environment['USER'] ?? ''}',
      '/mnt',
    ]) {
      final d = Directory(base);
      if (d.existsSync()) {
        try {
          for (final e in d.listSync()) {
            if (e is Directory) out.add(e.path);
          }
        } catch (_) {}
      }
    }
    return out;
  }

  static List<FileEntry> list(String dir, {bool showHidden = false}) {
    final entries = <FileEntry>[];
    for (final e in Directory(dir).listSync(followLinks: false)) {
      if (!showHidden && isHidden(e.path)) continue;
      final fe = FileEntry.fromEntity(e);
      if (fe != null) entries.add(fe);
    }
    return entries;
  }

  /// Dotfiles everywhere, plus items with the hidden attribute on Windows.
  static bool isHidden(String path) =>
      p.basename(path).startsWith('.') || WinAttributes.isHidden(path);

  static Future<void> openWithOs(String path) async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else {
      await Process.start('xdg-open', [path]);
    }
  }

  static Future<void> revealInOs(String path) async {
    final dir = FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
    await openWithOs(dir);
  }

  static Future<String> newFolder(String parent) async {
    var name = 'New Folder';
    var target = p.join(parent, name);
    var i = 2;
    while (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      name = 'New Folder ($i)';
      target = p.join(parent, name);
      i++;
    }
    await Directory(target).create();
    return target;
  }

  static Future<void> rename(String path, String newName) async {
    final target = p.join(p.dirname(path), newName);
    if (FileSystemEntity.isDirectorySync(path)) {
      await Directory(path).rename(target);
    } else {
      await File(path).rename(target);
    }
  }

  static Future<void> delete(String path) async {
    if (FileSystemEntity.isDirectorySync(path)) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  /// Copies file or directory into [destDir]; returns the new path.
  static Future<String> copyInto(String src, String destDir) async {
    var target = p.join(destDir, p.basename(src));
    if (p.equals(src, target)) {
      final base = p.basenameWithoutExtension(src);
      final ext = p.extension(src);
      var i = 2;
      target = p.join(destDir, 'Copy of ${p.basename(src)}');
      while (FileSystemEntity.typeSync(target) !=
          FileSystemEntityType.notFound) {
        target = p.join(destDir, 'Copy ($i) of $base$ext');
        i++;
      }
    }
    if (FileSystemEntity.isDirectorySync(src)) {
      await _copyDir(Directory(src), Directory(target));
    } else {
      await File(src).copy(target);
    }
    return target;
  }

  static Future<void> _copyDir(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final newPath = p.join(dest.path, p.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, Directory(newPath));
      } else if (e is File) {
        await e.copy(newPath);
      }
    }
  }

  static Future<String> moveInto(String src, String destDir) async {
    final target = p.join(destDir, p.basename(src));
    if (p.equals(src, target)) return src;
    try {
      if (FileSystemEntity.isDirectorySync(src)) {
        await Directory(src).rename(target);
      } else {
        await File(src).rename(target);
      }
    } on FileSystemException {
      // Cross-device move: copy then delete.
      await copyInto(src, destDir);
      await delete(src);
    }
    return target;
  }
}
