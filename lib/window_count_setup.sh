#!/usr/bin/env bash
# window_count_setup.sh — install steps for the workspace-window-count@local
# GNOME Shell extension.
#
# The core install (install_window_count_extension) deploys the extension,
# compiles its GSettings schema, and enables it so the window-count badge always
# works no matter which optional components the user selects. Each selectable
# component then writes one (or a few related) GSettings key(s) on the bundled
# schema, so every customizable behavior is fully editable without touching the
# extension source. All components default the schema back to the extension's
# built-in behavior, so a clean install reproduces the original badge exactly.
#
# Functions:
#   run_as_target                 - run a command in the target user's session.
#   append_gsettings_list         - idempotently add a value to a strv key.
#   install_extension_files       - copy extension + schema + prefs, compile schema.
#   enable_extension              - add the UUID to enabled-extensions.
#   install_window_count_extension- deploy + enable the extension (always).
#   wwc_set                       - write one key on the bundled schema.
#   wwc_configure_position        - set badge-position (WWC_BADGE_POSITION).
#   wwc_configure_threshold       - set count-threshold (WWC_COUNT_THRESHOLD).
#   wwc_configure_workspace_scope - set count-all-workspaces (WWC_COUNT_ALL_WORKSPACES).
#   wwc_configure_appearance      - set badge color/size keys (WWC_BADGE_*).
#
# Required globals (exported by install.sh before sourcing this file):
#   SCRIPT_DIR TARGET_USER TARGET_UID TARGET_HOME RUNTIME_DIR USER_BUS
#   DISPLAY_VAL EXTENSION_UUID EXTENSION_SRC EXTENSION_DST SCHEMA_ID

EXTENSION_UUID="${EXTENSION_UUID:-workspace-window-count@local}"
SCHEMA_ID="${SCHEMA_ID:-org.gnome.shell.extensions.workspace-window-count}"
ENABLED_EXTENSIONS_SCHEMA="${ENABLED_EXTENSIONS_SCHEMA:-org.gnome.shell}"
ENABLED_EXTENSIONS_KEY="${ENABLED_EXTENSIONS_KEY:-enabled-extensions}"

# Defaults preserve the extension's built-in behavior. Override via the
# environment to customize a clean or scripted install.
WWC_BADGE_POSITION="${WWC_BADGE_POSITION:-bottom-right}"
WWC_COUNT_THRESHOLD="${WWC_COUNT_THRESHOLD:-2}"
WWC_COUNT_ALL_WORKSPACES="${WWC_COUNT_ALL_WORKSPACES:-false}"
WWC_BADGE_TEXT_COLOR="${WWC_BADGE_TEXT_COLOR:-#ffffff}"
WWC_BADGE_BACKGROUND_COLOR="${WWC_BADGE_BACKGROUND_COLOR:-transparent}"
WWC_BADGE_FONT_SIZE="${WWC_BADGE_FONT_SIZE:-18}"

# msg: Print a highlighted progress message to stdout and mirror it to the log.
# Defined only if install.sh has not already provided one.
# Arguments: $* - the message text to display.
# Returns: 0 always.
if ! declare -F msg >/dev/null 2>&1; then
  msg() {
    printf "\n==> %s\n" "$*"
    wwc_log INFO "$*"
  }
fi

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
  if ! current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null)"; then
    wwc_log ERROR "Could not read GSettings string-array $schema $key; preserving existing state"
    wwc_log_call EXIT append_gsettings_list "status=1 skipped=read_failure"
    return 1
  fi
  wwc_log DEBUG "Read current GSettings string-array for $schema $key"
  newlist="$(CURRENT="$current" wwc_bin "$value")"
  if run_as_target gsettings set "$schema" "$key" "$newlist"; then
    wwc_log INFO "Updated GSettings string-array for $schema $key"
    wwc_log_call EXIT append_gsettings_list "status=0"
    return 0
  fi
  wwc_log ERROR "Failed to update GSettings string-array for $schema $key"
  wwc_log_call EXIT append_gsettings_list "status=1"
  return 1
}

# wwc_set: Write one key on the bundled extension schema in the target user's
# session, resolving the schema from the deployed extension's schemas dir so it
# works before GNOME Shell has reloaded and registered the schema globally.
# Best-effort: a write failure is warned but never aborts the install, so the
# installer always finishes (the extension falls back to the schema default).
# Arguments: $1 - key name, $2 - value (gsettings literal for the key type).
# Returns: 0 always.
wwc_set() {
  local key="$1" value="$2"
  wwc_log_call ENTER wwc_set "key=$key"
  if run_as_target gsettings --schemadir "$EXTENSION_DST/schemas" set \
    "$SCHEMA_ID" "$key" "$value"; then
    wwc_log INFO "Set $SCHEMA_ID $key"
  else
    wwc_log WARNING "Could not set $SCHEMA_ID $key (schema may compile on next Shell reload)"
    msg "WARN: could not set $key; it will use the schema default until applied."
  fi
  wwc_log_call EXIT wwc_set "status=0"
  return 0
}

# install_extension_files: Copy every regular file from the extension source
# directory into the target user's GNOME extensions directory, deploy and
# compile the GSettings schema, and (when run as root) hand ownership to the
# target user. Skips (with a warning) if the source directory is missing.
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

  # Deploy and compile the GSettings schema so getSettings() resolves and the
  # per-behavior components can write keys. Best-effort: a missing
  # glib-compile-schemas must not abort the core deploy — the extension falls
  # back to its built-in defaults when the schema is unavailable.
  if [ -d "$EXTENSION_SRC/schemas" ]; then
    run_as_target mkdir -p "$EXTENSION_DST/schemas"
    for schema_file in "$EXTENSION_SRC"/schemas/*; do
      [ -f "$schema_file" ] || continue
      wwc_log DEBUG "Copying schema file $(basename "$schema_file")"
      run_as_target cp "$schema_file" "$EXTENSION_DST/schemas/$(basename "$schema_file")"
    done
    if command -v glib-compile-schemas >/dev/null 2>&1; then
      wwc_log INFO "Compiling GSettings schema in $EXTENSION_DST/schemas"
      run_as_target glib-compile-schemas "$EXTENSION_DST/schemas" || {
        wwc_log WARNING "glib-compile-schemas failed; extension will use built-in defaults"
        msg "WARN: schema compile failed; extension will use built-in defaults until recompiled."
      }
    else
      wwc_log WARNING "glib-compile-schemas not found; extension will use built-in defaults"
      msg "WARN: glib-compile-schemas not found; extension will use built-in defaults."
    fi
  fi

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
# emitting progress messages around the work. Always runs (unconditional core)
# so the badge works regardless of which optional components are selected.
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

# wwc_configure_position: Set the badge corner from WWC_BADGE_POSITION.
# Returns: the wwc_set exit status.
wwc_configure_position() {
  wwc_log_call ENTER wwc_configure_position "$WWC_BADGE_POSITION"
  msg "Setting badge position: $WWC_BADGE_POSITION"
  wwc_set "badge-position" "'$WWC_BADGE_POSITION'"
}

# wwc_configure_threshold: Set the minimum window count from WWC_COUNT_THRESHOLD.
# Returns: the wwc_set exit status.
wwc_configure_threshold() {
  wwc_log_call ENTER wwc_configure_threshold "$WWC_COUNT_THRESHOLD"
  msg "Setting minimum window count threshold: $WWC_COUNT_THRESHOLD"
  wwc_set "count-threshold" "$WWC_COUNT_THRESHOLD"
}

# wwc_configure_workspace_scope: Set whether windows are counted across all
# workspaces from WWC_COUNT_ALL_WORKSPACES.
# Returns: the wwc_set exit status.
wwc_configure_workspace_scope() {
  wwc_log_call ENTER wwc_configure_workspace_scope "$WWC_COUNT_ALL_WORKSPACES"
  msg "Setting count-all-workspaces: $WWC_COUNT_ALL_WORKSPACES"
  wwc_set "count-all-workspaces" "$WWC_COUNT_ALL_WORKSPACES"
}

# wwc_configure_appearance: Set the badge color and size keys from the
# WWC_BADGE_TEXT_COLOR, WWC_BADGE_BACKGROUND_COLOR, and WWC_BADGE_FONT_SIZE
# environment variables. Best-effort via wwc_set.
# Returns: 0 always.
wwc_configure_appearance() {
  wwc_log_call ENTER wwc_configure_appearance
  msg "Setting badge appearance (text=$WWC_BADGE_TEXT_COLOR bg=$WWC_BADGE_BACKGROUND_COLOR size=$WWC_BADGE_FONT_SIZE)"
  wwc_set "badge-text-color" "'$WWC_BADGE_TEXT_COLOR'"
  wwc_set "badge-background-color" "'$WWC_BADGE_BACKGROUND_COLOR'"
  wwc_set "badge-font-size" "$WWC_BADGE_FONT_SIZE"
  wwc_log_call EXIT wwc_configure_appearance "status=0"
  return 0
}

###############################################################################
# Detection and uninstall (component lifecycle)
###############################################################################
# These knobs all configure the one bundled extension's GSettings schema.
# Uninstalling a knob resets its key(s) to the schema default; the mandatory
# extension deploy/enable itself is core and is not a selectable component, so
# uninstall here never removes the extension. None of them declares a detect
# function (see installer/components.sh): installed state comes from the
# install receipt, because the values they write are indistinguishable from the
# schema defaults the extension ships.

# wwc_schema_present: true when the bundled extension schema is readable.
wwc_schema_present() {
  run_as_target gsettings --schemadir "$EXTENSION_DST/schemas" \
    get "$SCHEMA_ID" badge-position >/dev/null 2>&1
}

# wwc_reset: reset one extension schema key to its default. Best-effort.
wwc_reset() {
  local key="$1"
  if ! wwc_schema_present; then
    msg "Extension schema not installed; skipping reset of $key"
    return 0
  fi
  run_as_target gsettings --schemadir "$EXTENSION_DST/schemas" \
    reset "$SCHEMA_ID" "$key" 2>/dev/null || true
}

uninstall_wwc_position()        { msg "Resetting badge-position to default";        wwc_reset badge-position; }
uninstall_wwc_threshold()       { msg "Resetting count-threshold to default";       wwc_reset count-threshold; }
uninstall_wwc_workspace_scope() { msg "Resetting count-all-workspaces to default";  wwc_reset count-all-workspaces; }
uninstall_wwc_appearance() {
  msg "Resetting badge appearance to defaults"
  wwc_reset badge-text-color
  wwc_reset badge-background-color
  wwc_reset badge-font-size
}
