#!/usr/bin/env bash
# install.sh - Install and enable the Linux Taskbar Window Count extension.
#
# Components:
#   - workspace-window-count@local GNOME Shell extension deployment
#   - idempotent enabled-extensions list update for GNOME taskbar badges
#
# Usage: sudo bash install.sh

set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="/run/user/$TARGET_UID"
USER_BUS="unix:path=${RUNTIME_DIR}/bus"
DISPLAY_VAL="${DISPLAY:-:0}"
EXTENSION_UUID="workspace-window-count@local"
EXTENSION_SRC="$SCRIPT_DIR/workspace-window-count@local"
EXTENSION_DST="${TARGET_HOME}/.local/share/gnome-shell/extensions/$EXTENSION_UUID"
ENABLED_EXTENSIONS_SCHEMA="org.gnome.shell"
ENABLED_EXTENSIONS_KEY="enabled-extensions"

# ── Core helpers (inline to avoid cross-repo sourcing issues) ─────────────────
msg() { printf "\n==> %s\n" "$*"; }
run_as_target() { sudo -H -u "$TARGET_USER" env \
  HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
  DISPLAY="$DISPLAY_VAL" "$@"; }
append_gsettings_list() {
  local schema="$1" key="$2" value="$3" current newlist
  current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null || echo "[]")"
  newlist="$(VAL="$value" CURRENT="$current" python3 - <<'PY'
import ast, os
cur_raw = os.environ.get("CURRENT", "").strip()
if cur_raw.startswith("@as "):
    cur_raw = cur_raw[4:].strip()
try:
    cur = ast.literal_eval(cur_raw) if cur_raw else []
except Exception:
    cur = []
if not isinstance(cur, list):
    cur = []
cur = list(dict.fromkeys(str(item) for item in cur))
val = os.environ.get("VAL", "")
if val and val not in cur:
    cur.append(val)
print("[" + ", ".join(repr(str(item)) for item in cur) + "]")
PY
)"
  run_as_target gsettings set "$schema" "$key" "$newlist"
}

install_extension_files() {
  if [ ! -d "$EXTENSION_SRC" ]; then
    msg "WARN: workspace-window-count@local source not found at $EXTENSION_SRC; skipping."
    return 0
  fi

  run_as_target mkdir -p "$EXTENSION_DST"
  for src_file in "$EXTENSION_SRC"/*; do
    [ -f "$src_file" ] || continue
    run_as_target cp "$src_file" "$EXTENSION_DST/$(basename "$src_file")"
  done
}

enable_extension() {
  append_gsettings_list "$ENABLED_EXTENSIONS_SCHEMA" \
    "$ENABLED_EXTENSIONS_KEY" "$EXTENSION_UUID" || true
}

install_window_count_extension() {
  msg "Deploying workspace-window-count@local GNOME Shell extension"
  install_extension_files
  enable_extension
  msg "  Extension deployed to $EXTENSION_DST and enabled"
}

main_inner() {
  install_window_count_extension
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_inner "$@"
fi
