import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Plays the bundled bark without any audio plugin: the WAV asset is written
/// to a temp file once, then handed to whatever system player exists
/// (pw-play/paplay/aplay/ffplay on Linux, SoundPlayer via PowerShell on
/// Windows, afplay on macOS).
class SoundService {
  static String? _woofPath;
  static bool muted = false;

  static Future<void> _ensureExtracted() async {
    if (_woofPath != null && File(_woofPath!).existsSync()) return;
    final data = await rootBundle.load('assets/sounds/woof.wav');
    final path = p.join(Directory.systemTemp.path, 'rover_woof.wav');
    await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    _woofPath = path;
  }

  static Future<void> playWoof() async {
    if (muted) return;
    try {
      await _ensureExtracted();
      final f = _woofPath!;
      if (Platform.isWindows) {
        // PlaySync: Play() returns at once and PowerShell would exit,
        // cutting the bark off before it is heard. A ' in the path (a user
        // name like O'Neil) is doubled for the single-quoted string.
        final quoted = f.replaceAll("'", "''");
        await Process.start('powershell', [
          '-NoProfile',
          '-c',
          "(New-Object Media.SoundPlayer '$quoted').PlaySync()",
        ]);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('afplay', [f]);
        return;
      }
      for (final player in [
        ['pw-play', f],
        ['paplay', f],
        ['aplay', '-q', f],
        ['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet', f],
      ]) {
        try {
          await Process.start(player.first, player.sublist(1));
          return;
        } on ProcessException {
          continue;
        }
      }
    } catch (_) {
      // No audio available — the dog barks silently.
    }
  }
}
