#!/usr/bin/env bash
# install.sh - Install and enable the Linux Taskbar Window Count extension.
#
# Components:
#   - workspace-window-count@local GNOME Shell extension deployment
#   - idempotent enabled-extensions list update for GNOME taskbar badges
#
# Usage: bash install.sh          # no sudo needed; runs entirely user-level
#        sudo bash install.sh     # also supported (clean-install chain)

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

source "$SCRIPT_DIR/lib/logging.sh"

# ── Core helpers (inline to avoid cross-repo sourcing issues) ─────────────────

# msg: Print a highlighted progress message to stdout.
# Arguments: $* - the message text to display.
# Returns: 0 always (writes the formatted line to stdout).
msg() {
  printf "\n==> %s\n" "$*"
  wwc_log INFO "$*"
}

# run_as_target: Run a command as the target (non-root) user with that user's
# session environment (HOME, D-Bus, display) so GSettings/GNOME calls reach the
# right session even when the script itself runs under sudo. When the script is
# already running as the target user no sudo round-trip is made.
# Arguments: $@ - the command and its arguments to execute.
# Returns: the exit status of the executed command.
run_as_target() {
  wwc_log_call ENTER run_as_target "$*"
  local status
  if [ "$(id -u)" -eq "$TARGET_UID" ]; then
    env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
      DISPLAY="$DISPLAY_VAL" "$@"
    status=$?
  else
    sudo -H -u "$TARGET_USER" env \
      HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
      DISPLAY="$DISPLAY_VAL" "$@"
    status=$?
  fi
  wwc_log_call EXIT run_as_target "status=$status"
  return "$status"
}

# append_gsettings_list: Idempotently append a value to a GSettings string-array
# key, preserving existing entries and de-duplicating. Reads the current list,
# merges through a tested helper, and writes the result back.
# Arguments: $1 - schema, $2 - key, $3 - value to ensure is present.
# Returns: the exit status of the final `gsettings set` call.
append_gsettings_list() {
  local schema="$1" key="$2" value="$3" current newlist
  wwc_log_call ENTER append_gsettings_list "schema=$schema key=$key"
  current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null || echo "[]")"
  wwc_log DEBUG "Read current GSettings string-array for $schema $key"
  newlist="$(CURRENT="$current" python3 "$SCRIPT_DIR/lib/gsettings_strv.py" "$value")"
  if run_as_target gsettings set "$schema" "$key" "$newlist"; then
    wwc_log INFO "Updated GSettings string-array for $schema $key"
    wwc_log_call EXIT append_gsettings_list "status=0"
    return 0
  fi
  wwc_log ERROR "Failed to update GSettings string-array for $schema $key"
  wwc_log_call EXIT append_gsettings_list "status=1"
  return 1
}

# install_extension_files: Copy every regular file from the extension source
# directory into the target user's GNOME extensions directory. Skips (with a
# warning) if the source directory is missing.
# Arguments: none (uses EXTENSION_SRC / EXTENSION_DST globals).
# Returns: 0 on success or when skipped; non-zero if a copy fails.
install_extension_files() {
  wwc_log_call ENTER install_extension_files "$EXTENSION_SRC -> $EXTENSION_DST"
  if [ ! -d "$EXTENSION_SRC" ]; then
    msg "WARN: workspace-window-count@local source not found at $EXTENSION_SRC; skipping."
    wwc_log_call EXIT install_extension_files "status=0 skipped=missing_source"
    return 0
  fi

  run_as_target mkdir -p "$EXTENSION_DST"
  for src_file in "$EXTENSION_SRC"/*; do
    [ -f "$src_file" ] || continue
    wwc_log DEBUG "Copying extension file $(basename "$src_file")"
    run_as_target cp "$src_file" "$EXTENSION_DST/$(basename "$src_file")"
  done
  wwc_log_call EXIT install_extension_files "status=0"
}

# enable_extension: Add the extension UUID to GNOME's enabled-extensions list so
# GNOME Shell loads it. Idempotent via append_gsettings_list; failures are
# tolerated so a transient GSettings or session-bus error does not abort clean
# installation, but the skipped enable step remains visible in installer output.
# Arguments: none (uses the ENABLED_EXTENSIONS_* / EXTENSION_UUID globals).
# Returns: 0 always.
enable_extension() {
  wwc_log_call ENTER enable_extension "$EXTENSION_UUID"
  if ! append_gsettings_list "$ENABLED_EXTENSIONS_SCHEMA" \
    "$ENABLED_EXTENSIONS_KEY" "$EXTENSION_UUID"; then
    wwc_log WARNING "Could not update GNOME enabled-extensions"
    msg "WARN: Could not update GNOME enabled-extensions; deploy completed but the extension may need to be enabled manually."
  fi
  wwc_log_call EXIT enable_extension "status=0"
}

# install_window_count_extension: Deploy the extension files and enable it,
# emitting progress messages around the work.
# Arguments: none.
# Returns: 0 on success; propagates a non-zero status if file deployment fails.
install_window_count_extension() {
  wwc_log_call ENTER install_window_count_extension
  msg "Deploying workspace-window-count@local GNOME Shell extension"
  install_extension_files
  enable_extension
  msg "  Extension deployed to $EXTENSION_DST and enabled"
  wwc_log_call EXIT install_window_count_extension "status=0"
}

# main_inner: Top-level entry point invoked when the script is executed
# directly. Orchestrates the full install flow.
# Arguments: $@ - forwarded but currently unused.
# Returns: the exit status of the install steps.
main_inner() {
  wwc_log_call ENTER main_inner "$*"
  install_window_count_extension
  local status=$?
  wwc_log_call EXIT main_inner "status=$status"
  return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_inner "$@"
fi
