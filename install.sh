#!/usr/bin/env bash
# install.sh - Install and customize the Linux Taskbar Window Count extension.
#
# Deploys the workspace-window-count@local GNOME Shell extension into the target
# user's local extensions directory, compiles its GSettings schema, and enables
# it. This core deploy always runs so the window-count badge works no matter
# which optional components are selected. Each customizable behavior (badge
# position, the minimum window-count threshold, current-vs-all-workspace
# counting, and badge colors/size) is a selectable component routed through the
# shared installer component framework, so a clean install reproduces the
# built-in behavior while every part stays fully customizable.
#
# Usage:
#   bash install.sh                   # interactive component menu (TTY), else defaults
#   bash install.sh --default         # core + every default-on component, no prompts
#   bash install.sh --all             # core + every component, no prompts
#   bash install.sh --select a,b,c    # core + only the listed component ids
#   bash install.sh --list-components # machine-readable component list (no deploy)
#   bash install.sh --help            # usage
#   sudo bash install.sh              # also supported (clean-install chain)

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
SCHEMA_ID="org.gnome.shell.extensions.workspace-window-count"
ENABLED_EXTENSIONS_SCHEMA="org.gnome.shell"
ENABLED_EXTENSIONS_KEY="enabled-extensions"
export TARGET_USER TARGET_UID TARGET_HOME SCRIPT_DIR RUNTIME_DIR USER_BUS \
  DISPLAY_VAL EXTENSION_UUID EXTENSION_SRC EXTENSION_DST SCHEMA_ID \
  ENABLED_EXTENSIONS_SCHEMA ENABLED_EXTENSIONS_KEY

source "$SCRIPT_DIR/lib/logging.sh"

# msg: Print a highlighted progress message to stdout and mirror it to the
# centralized installer log. Defined before the framework helpers load so this
# logging-aware version (not the framework's plain printf) is used throughout.
# Arguments: $* - the message text to display.
# Returns: 0 always.
msg() {
  printf "\n==> %s\n" "$*"
  wwc_log INFO "$*"
}

# load_component_framework: Load the shared installer component framework from a
# sibling checkout of linux_installation_scripts_functions, falling back to an
# on-demand download so a standalone clean install works without that checkout.
# Returns: 0 once isc_activate_components has run.
load_component_framework() {
  local d
  for d in "${ISC_FUNCTIONS_DIR:-}" \
           "$SCRIPT_DIR/../linux_installation_scripts_functions" \
           "$HOME/projects/linux_installation_scripts_functions"; do
    [[ -n "$d" && -f "$d/component_loader.sh" ]] && { source "$d/component_loader.sh"; break; }
  done
  declare -F isc_activate_components >/dev/null 2>&1 || \
    source <(curl -fsSL "https://raw.githubusercontent.com/mikaeltorni/linux_installation_scripts_functions/${ISC_FUNCTIONS_REF:-master}/component_loader.sh")
  isc_activate_components
}

# main: Orchestrate the install: load the framework, deploy the extension core
# unconditionally, then route the customizable components through the shared
# component framework.
# Arguments: $@ - forwarded to component_main.
# Returns: the exit status of component_main.
main() {
  wwc_log_call ENTER main "$*"
  load_component_framework
  # shellcheck source=lib/window_count_setup.sh
  source "$SCRIPT_DIR/lib/window_count_setup.sh"
  install_window_count_extension

  # shellcheck source=installer/components.sh
  source "$SCRIPT_DIR/installer/components.sh"
  local status=0
  component_main "$@" || status=$?
  msg "Workspace window-count extension installed. If GNOME Shell has not loaded it yet, reload the Shell (X11: Alt+F2 then r) or log out and back in (Wayland)."
  wwc_log_call EXIT main "status=$status"
  return "$status"
}

# Listing/help must print only their own output (the master installer parses
# --list-components); skip the core deploy and completion message for those.
case "${1:-}" in
  --list-components|--help|-h)
    load_component_framework
    source "$SCRIPT_DIR/lib/window_count_setup.sh"
    source "$SCRIPT_DIR/installer/components.sh"
    component_main "$1"
    exit $?
    ;;
esac

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
