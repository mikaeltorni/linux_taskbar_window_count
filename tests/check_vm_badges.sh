#!/usr/bin/env bash
# Check the actual GNOME badge theme during a live style refresh.
set -euo pipefail
if [[ ${MT_STACK_VM_TEST:-} != 1 ]]; then
  printf 'Run only in a test VM with the badge active and multiple app windows.\n' >&2
  exit 2
fi
schema=org.gnome.shell.extensions.workspace-window-count
schema_dir="$HOME/.local/share/gnome-shell/extensions/workspace-window-count@local/schemas"
old_size="$(gsettings --schemadir "$schema_dir" get "$schema" badge-font-size)"
trap 'gsettings --schemadir "$schema_dir" set "$schema" badge-font-size "$old_size"' EXIT
cursor="$(journalctl --user -n 1 --show-cursor --no-pager | sed -n 's/^-- cursor: //p')"
test -n "$cursor"
gsettings --schemadir "$schema_dir" set "$schema" badge-font-size 19
sleep 1
gsettings --schemadir "$schema_dir" set "$schema" badge-font-size "$old_size"
sleep 1
output="$(journalctl --user --after-cursor="$cursor" --no-pager)"
if [[ "$output" == *'Ignoring excess values in shadow definition'* ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi
printf 'PASS: live badge style refresh produces no unsupported shadow warnings\n'
