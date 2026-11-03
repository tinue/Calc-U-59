#!/bin/bash
# Installs the last release build into /Applications; run by ReleaseIt as
# release.post_release, from the repository root. Replacing a running bundle
# breaks it, so a running copy is quit first and started again afterwards.
set -euo pipefail

bundle_id=ch.erzberger.calcu59
src=build/release/Calc-U-59.app
dst=/Applications/Calc-U-59.app
tmp=/Applications/.Calc-U-59.app.new

if [ ! -d "$src" ]; then
  echo "$src not found: nothing to install. Run release first." >&2
  exit 1
fi
codesign --verify --deep --strict "$src"

is_running() {
  [ "$(osascript -e "application id \"$bundle_id\" is running")" = "true" ]
}

was_running=false
if is_running; then
  was_running=true
  echo "Quitting Calc-U-59…"
  osascript -e "tell application id \"$bundle_id\" to quit"
  for _ in {1..20}; do
    is_running || break
    sleep 0.5
  done
  if is_running; then
    echo "Calc-U-59 did not quit: $dst was not replaced." >&2
    exit 1
  fi
fi

# Copied first, so a failed copy leaves the installed app alone.
rm -rf "$tmp"
ditto "$src" "$tmp"
rm -rf "$dst"
mv "$tmp" "$dst"
echo "Installed $dst"

if [ "$was_running" = true ]; then
  open "$dst"
fi
