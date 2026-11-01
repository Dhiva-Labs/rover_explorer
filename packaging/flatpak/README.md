# Flatpak

The `flatpak` job in `.github/workflows/release.yml` builds
`rover-explorer-<version>-<x86_64|aarch64>.flatpak` on the GNOME 51 runtime,
then installs that bundle in the Flatpak builder container and runs it: every
ELF file must find its libraries inside the sandbox, and the "Rover Explorer"
window must come up under Xvfb (`test-bundle.sh`).

The manifest does not compile anything: it takes the installed tree of the
`.deb` CI built for that architecture (unpacked into `tree/`), so the Flatpak
runs the same binary as every other package.

Install a bundle from a release (the GNOME runtime comes from Flathub):

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./rover-explorer-1.0.1-x86_64.flatpak
flatpak run com.dhivalabs.rover_explorer
```

Permissions: Wayland/X11, the GPU, `--filesystem=host` (a file manager
browses and indexes the whole file system by path, which no portal covers)
and PulseAudio (the companion's bark, played with the runtime's `pw-play` or
`paplay` when it has one; without, the dog barks silently, as on any system
without those tools). Files open through the runtime's `xdg-open`, which hands
them to the OpenURI portal and so to the host's default applications.

## A Flathub submission would differ

- Flathub does not build from CI artifacts. The `tree` source becomes the
  release `.deb` (`type: file`, `url:` + `sha256:`, unpacked with `bsdtar`),
  or the app is built from source with the Flutter SDK as a module.
- `--filesystem=host` needs a justification in the submission (a file
  manager is the accepted case).
- `flatpak-builder-lint` must pass on the manifest and the metainfo
  (screenshots, release notes, a brand colour).
