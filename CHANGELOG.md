# Changelog

All notable changes to Rover Explorer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Packaging work and Windows fixes.

### Added

- Linux and Windows ARM64 builds. CI builds, tests and smoke-runs the app on
  native x64 and arm64 runners, and each release now also carries
  `rover-explorer-<version>-linux-arm64.tar.gz`,
  `rover-explorer_<version>_arm64.deb`,
  `rover-explorer-<version>-windows-arm64.zip` and
  `RoverExplorer-<version>-arm64-setup.exe`, all listed in `SHA256SUMS.txt`.
  The snap and the Microsoft Store package (`--architecture arm64`) build for
  arm64 too.
- Microsoft Store packaging: an `msix_config` block in `pubspec.yaml`
  (`dart run msix:create --store` builds the unsigned Store package) and a
  1024 px logo at `packaging/windows/rover-explorer-logo.png`.
- The Windows executable now carries the Rover icon instead of the default
  Flutter one.

### Fixed

- Windows: the window came up empty (a grey area below the address bar) on
  machines with a card reader or DVD drive and no media in it. Probing that
  drive letter throws "The device is not ready", which failed the task pane
  and folder tree builds; such drives are now skipped. The drive list is also
  cached for a few seconds instead of being probed on every rebuild.
- Windows: files and folders with the hidden attribute (`AppData`,
  `NTUSER.DAT`, `desktop.ini`, the legacy profile junctions) are treated like
  dotfiles: hidden unless "show hidden files" is on, and kept out of the
  search index.
- Windows: the bark was cut off before it was heard, because
  `SoundPlayer.Play()` returns immediately and PowerShell exited with it. It
  now uses `PlaySync()`.

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
