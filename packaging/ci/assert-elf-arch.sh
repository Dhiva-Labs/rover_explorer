#!/usr/bin/env bash
#
# Fails unless every ELF file under a Flutter Linux bundle is built for the
# expected CPU, so an x64 binary can never ship as arm64 (or the reverse).
#
#   packaging/ci/assert-elf-arch.sh <bundle-dir> <x64|arm64> <relative-file>...
#
# The listed files must exist; they are the ones every bundle has.
set -euo pipefail

dir="${1:?usage: assert-elf-arch.sh <bundle-dir> <x64|arm64> <file>...}"
arch="${2:?usage: assert-elf-arch.sh <bundle-dir> <x64|arm64> <file>...}"
shift 2

case "$arch" in
  x64) machine="x86-64" ;;
  arm64) machine="ARM aarch64" ;;
  *)
    echo "error: unsupported architecture '$arch' (x64 or arm64)" >&2
    exit 1
    ;;
esac

for f in "$@"; do
  [ -f "$dir/$f" ] || { echo "::error::missing $dir/$f"; exit 1; }
done

checked=0
bad=0
while IFS= read -r -d '' f; do
  desc="$(file -b "$f")"
  case "$desc" in ELF*) ;; *) continue ;; esac
  echo "$f: $desc"
  checked=$((checked + 1))
  case "$desc" in
    *"$machine"*) ;;
    *) echo "::error file=$f::not $machine"; bad=1 ;;
  esac
done < <(find "$dir" -type f -print0)

echo "checked $checked ELF files"
[ "$checked" -ge 3 ] && [ "$bad" -eq 0 ]
