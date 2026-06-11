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

# msg: Print a highlighted progress message to stdout.
# Arguments: $* - the message text to display.
# Returns: 0 always (writes the formatted line to stdout).
msg() { printf "\n==> %s\n" "$*"; }

# run_as_target: Run a command as the target (non-root) user with that user's
# session environment (HOME, D-Bus, display) so GSettings/GNOME calls reach the
# right session even when the script itself runs under sudo.
# Arguments: $@ - the command and its arguments to execute.
# Returns: the exit status of the executed command.
run_as_target() { sudo -H -u "$TARGET_USER" env \
  HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
  DISPLAY="$DISPLAY_VAL" "$@"; }

# append_gsettings_list: Idempotently append a value to a GSettings string-array
# key, preserving existing entries and de-duplicating. Reads the current list,
# merges via python3, and writes the result back.
# Arguments: $1 - schema, $2 - key, $3 - value to ensure is present.
# Returns: the exit status of the final `gsettings set` call.
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

# install_extension_files: Copy every regular file from the extension source
# directory into the target user's GNOME extensions directory. Skips (with a
# warning) if the source directory is missing.
# Arguments: none (uses EXTENSION_SRC / EXTENSION_DST globals).
# Returns: 0 on success or when skipped; non-zero if a copy fails.
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

# enable_extension: Add the extension UUID to GNOME's enabled-extensions list so
# GNOME Shell loads it. Idempotent via append_gsettings_list; failures are
# tolerated so a transient GSettings error does not abort the install.
# Arguments: none (uses the ENABLED_EXTENSIONS_* / EXTENSION_UUID globals).
# Returns: 0 always.
enable_extension() {
  append_gsettings_list "$ENABLED_EXTENSIONS_SCHEMA" \
    "$ENABLED_EXTENSIONS_KEY" "$EXTENSION_UUID" || true
}

# install_window_count_extension: Deploy the extension files and enable it,
# emitting progress messages around the work.
# Arguments: none.
# Returns: 0 on success; propagates a non-zero status if file deployment fails.
install_window_count_extension() {
  msg "Deploying workspace-window-count@local GNOME Shell extension"
  install_extension_files
  enable_extension
  msg "  Extension deployed to $EXTENSION_DST and enabled"
}

# main_inner: Top-level entry point invoked when the script is executed
# directly. Orchestrates the full install flow.
# Arguments: $@ - forwarded but currently unused.
# Returns: the exit status of the install steps.
main_inner() {
  install_window_count_extension
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_inner "$@"
fi
