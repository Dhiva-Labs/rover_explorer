#!/usr/bin/env bash
#
# Starts Rover Explorer and waits for proof that its Dart code is running.
# Run it inside a display, e.g.
#
#   xvfb-run -a dbus-run-session -- packaging/ci/smoke-linux.sh rover-explorer
#
# The native runner only shows the window once Flutter has drawn its first
# frame, so a visible "Rover Explorer" window means the engine and the app's
# AOT snapshot ran on this CPU. main() then starts the indexer isolate, which
# scans $HOME and writes rover_index.txt. $HOME is a throwaway folder holding
# one marker file, so finding the marker in that cache shows the Dart file
# system code ran too.
set -u

cmd="${1:?usage: smoke-linux.sh <rover_explorer command>}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME/Documents"
: > "$HOME/Documents/rover-smoke-marker.txt"
log="$tmp/app.log"

"$cmd" > "$log" 2>&1 &
pid=$!

for i in $(seq 1 90); do
  if xdotool search --onlyvisible --name '^Rover Explorer$' > /dev/null 2>&1 &&
    grep -qs rover-smoke-marker.txt "$HOME"/.local/share/*/rover_index.txt; then
    echo "window is up and the index holds the marker after ${i}s"
    sleep 5
    kill -0 "$pid" 2> /dev/null || { echo "$cmd died after showing its window"; cat "$log"; exit 1; }
    kill "$pid"
    cat "$log"
    exit 0
  fi
  kill -0 "$pid" 2> /dev/null || { echo "$cmd exited early"; cat "$log"; exit 1; }
  sleep 1
done

echo "no window and index marker after 90s"
ls -R "$HOME" | head -50
cat "$log"
kill "$pid" 2> /dev/null
exit 1
