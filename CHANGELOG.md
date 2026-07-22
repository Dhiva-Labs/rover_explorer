# Changelog

All notable changes to Rover Explorer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Packaging fixes only — the application itself is unchanged from 1.0.0.

### Fixed

- Debian source packages for the PPA now ship the Flutter bundle as
  `bundle.tar.gz`. As a plain directory, `dpkg-source`'s default
  `--tar-ignore` patterns silently dropped `libflutter_linux_gtk.so` and
  `libapp.so`, producing a package that installed but could not start
  (`1.0.0~noble1`). `debian/rules` now asserts both libraries are present so
  the build fails instead of shipping an unusable package.
- The snap build no longer inherits a local `build/` directory, whose stale
  `CMakeCache.txt` pointed at the host path and made CMake refuse the
  in-container build.

### Changed

- The snapcraft manifest moved to the canonical `snap/snapcraft.yaml`.
- Debian packaging for the PPA added under `packaging/ppa/`.

## [1.0.0] - 2026-07-22

First public release.

### Added

- **Explorer shell** styled after the Windows XP Luna theme: gradient toolbar,
  menu bar (File / Edit / View / Go / Tools / Help), address bar with a recent
  locations drop-down, status bar, and the beige classic chrome.
- **Common Tasks pane** ("File and Folder Tasks" / "Other Places" / "Details")
  and a lazily-loaded **Folders tree** navigation pane.
- **Search Companion** with an original animated dog: idle tricks (bark with
  sound, read, jump, wave, lick, scratch, floor-scratch, dig, ear flap, head
  tilt, tail wag, sleep, ball), a nose-down sniffing pose while searching, and
  a bone-in-mouth celebration when results arrive.
- **Instant indexed search**: a background isolate keeps an in-memory filename
  index (hundreds of thousands of entries), answers ranked queries on every
  keystroke, and caches the index to disk for an instant next launch.
- Search filters for All / Folders / Pictures / Music / Videos / Documents,
  plus a "only in current folder" scope, and multi-word queries that match
  across the full path.
- **File management**: open with the system handler, cut / copy / paste,
  rename, delete, new folder, multi-select (Ctrl and Shift), drag & drop onto
  folders, sortable columns, details and icons views, hidden-file toggle.
- **Properties dialog** with background size and item counting, and a
  **Folder Options** dialog for hidden files, companion, sounds and index
  rebuilding.
- **About dialog** reporting version, vendor, licence, platform and index size.
- Keyboard shortcuts: `F2` rename, `Del` delete, `F5` refresh, `Ctrl+A` select
  all, `Ctrl+C/X/V`, `Alt+Enter` properties, `Alt+Left/Right/Up` and
  `Backspace` navigation, `Ctrl+F` search, `Ctrl+Shift+N` new folder.
- Packaging for Debian (`.deb`), Snap, and Windows (Inno Setup), plus GitHub
  Actions workflows for CI and releases.

[1.0.0]: https://github.com/Dhiva-Labs/rover_explorer/releases/tag/v1.0.0
