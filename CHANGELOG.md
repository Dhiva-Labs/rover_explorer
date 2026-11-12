# Changelog

All notable changes to Rover Explorer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Packages for other Linux distributions, for x64 and arm64, built from the
  same build as the `.deb` and installed and started on each target in CI:
  an `.rpm` for Fedora and openSUSE, an Arch Linux package, an AppImage and a
  Flatpak bundle, plus an AUR recipe (`rover-explorer-bin`). Tagged releases
  include them.

### Fixed

- Search Companion: Backspace in the query box (and in the address bar)
  deletes a character again instead of going up a folder and hiding the
  results. Opening the pane, from the toolbar or with `Ctrl+F`, puts the
  cursor in the query box, and `Ctrl+F` while it is open returns there.
  Closing the pane hands the keyboard back to the file list, so Backspace,
  Delete, F2 and `Ctrl+F` keep working without a click first.
- Search: the words of a query may come in any order (`rover screen` and
  `screen rover` find the same files); each must appear somewhere in the
  path and at least one in the file name.
- Search: clearing the query, closing the pane or leaving the results while
  a search is still running no longer brings stale results back when it
  completes.
- Search: renames, deletes, moves, pastes and new folders made in the app
  update the index at once instead of after the next full rescan, and files
  deleted outside the app are dropped from the results (and the index)
  instead of listing with a 1970 date.
- Search: on a first run, before the index cache exists, queries are
  answered from whatever has been scanned so far and run again when the
  scan completes, instead of staying empty.
- Search: "Only in current folder" for `~/foo` no longer matches `~/foobar`,
  and works in folders outside the indexed home folder, which are scanned
  on the spot.
- Search: an error inside the background indexer no longer stops every later
  search. The indexer survives it, every query gets an answer, and the dog
  stops sniffing after a while even if one did not come.
- Search results stay in best-match order instead of being re-sorted by
  name; clicking a column header still sorts them.

## [1.0.1] - 2026-10-16

Linux and Windows ARM64 builds, Windows fixes and packaging work.

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
- A privacy policy (`PRIVACY.md`).

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
- Windows: the bark stayed silent when the temp path contained an apostrophe
  (for example a user name like `O'Neil`).
- The indexer writes its cache file before it reports the scan as finished,
  so "done" means the cache is on disk. Before, anything that acted right
  after the status changed (a test, or deleting the indexed folder) raced the
  write and could find no cache or a file still in use.
- Debian source packages for the PPA now ship the Flutter bundle as
  `bundle.tar.gz`. As a plain directory, `dpkg-source`'s default
  `--tar-ignore` patterns silently dropped `libflutter_linux_gtk.so` and
  `libapp.so`, producing a package that installed but could not start
  (`1.0.0~noble1`). `debian/rules` now asserts both libraries are present so
  the build fails instead of shipping an unusable package.
- Snap: under strict confinement Rover opened and indexed the snap's private
  data directory instead of your home folder. The app now gets
  `HOME=$SNAP_REAL_HOME`, and the snap ships a `.desktop` file so it appears
  in the application menu.
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

[Unreleased]: https://github.com/Dhiva-Labs/rover_explorer/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Dhiva-Labs/rover_explorer/releases/tag/v1.0.1
[1.0.0]: https://github.com/Dhiva-Labs/rover_explorer/releases/tag/v1.0.0
