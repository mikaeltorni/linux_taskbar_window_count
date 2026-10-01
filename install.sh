#!/usr/bin/env bash
# install.sh - Install and customize the Linux Taskbar Window Count extension.
#
# Deploys the workspace-window-count@local GNOME Shell extension into the target
# user's local extensions directory, compiles its GSettings schema, and enables
# it. This core deploy always runs so the window-count badge works no matter
# which optional components are selected. Each customizable behavior (badge
# position, the minimum window-count threshold, current-vs-all-workspace
# counting, and badge colors/size) is a selectable component routed through the
# repository-local component runtime, so a clean install reproduces the
# built-in behavior while every part stays fully customizable.
#
# Usage:
#   bash install.sh                   # interactive component menu (TTY), else defaults
#   bash install.sh --default         # core + every default-on component, no prompts
#   bash install.sh --all             # core + every component, no prompts
#   bash install.sh --select a,b,c    # core + only the listed component ids
#   bash install.sh --list-components # machine-readable component list (no deploy)
#   bash install.sh --help            # usage
# The master install chain may invoke this under sudo; SUDO_USER is targeted.

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
source "$SCRIPT_DIR/lib/wwc_bin.sh"

# msg: Print a highlighted progress message to stdout and mirror it to the
# centralized installer log. Defined before setup helpers load so this
# logging-aware version is used throughout.
# Arguments: $* - the message text to display.
# Returns: 0 always.
msg() {
  printf "\n==> %s\n" "$*"
  wwc_log INFO "$*"
}

source "$SCRIPT_DIR/lib/window_count_setup.sh"
source "$SCRIPT_DIR/installer/components.sh"
source "$SCRIPT_DIR/lib/component_runtime.sh"

# main: Deploy the extension core unconditionally, then route optional settings
# through the repository-local component runtime.
# Arguments: $@ - forwarded to component_main.
# Returns: the exit status of component_main.
main() {
  msg "=== Linux Taskbar Window Count Setup ==="

  if [ -z "${ISC_COMPONENTS:-}" ]; then
    echo "ERROR: ISC_COMPONENTS manifest is not defined." >&2
    exit 1
  fi

  # Deploy the extension core first, then configure its optional settings
  install_window_count_extension
  msg "Configuring window-count badge options"
  component_main "$@"
}

# Read-only, help, and uninstall commands bypass the unconditional core deploy.
# Check every argument so combinations such as --config NAME --export-selection
# remain side-effect free as well.
READONLY_COMMAND=0
for arg in "$@"; do
  case "$arg" in
    --list-components|--list-configurable-components|--list-select-configure-components|\
    --list-component-config-values|--export-selection|--detect|--help|-h|\
    --configure-component|--configure-component=*|--uninstall|--uninstall=*)
      READONLY_COMMAND=1
      break
      ;;
  esac
done
if [[ "$READONLY_COMMAND" == "1" ]]; then
  component_main "$@"
  exit $?
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
