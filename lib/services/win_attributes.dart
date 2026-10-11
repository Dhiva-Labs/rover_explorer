import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows file attributes, read with `GetFileAttributesW`.
///
/// Windows marks hidden items with an attribute rather than a leading dot:
/// `AppData`, `NTUSER.DAT`, `desktop.ini` and the legacy profile junctions
/// ("My Documents", "Cookies", ...) would otherwise all show up in a user's
/// home folder and bloat the search index.
class WinAttributes {
  WinAttributes._();

  static const int _hidden = 0x2;
  static const int _invalid = 0xFFFFFFFF;

  static int Function(Pointer<Utf16>)? _getAttributes;

  static int Function(Pointer<Utf16>) _lookup() => _getAttributes ??=
      DynamicLibrary.open('kernel32.dll').lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('GetFileAttributesW');

  /// True when [path] carries the hidden attribute. Always false off Windows
  /// and for paths whose attributes cannot be read.
  static bool isHidden(String path) {
    if (!Platform.isWindows) return false;
    final native = path.toNativeUtf16();
    try {
      final attrs = _lookup()(native);
      return attrs != _invalid && attrs & _hidden != 0;
    } catch (_) {
      return false;
    } finally {
      calloc.free(native);
    }
  }
}
