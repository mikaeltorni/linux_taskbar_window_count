#!/usr/bin/env bash
# Local component command runtime for the taskbar window-count installer.
#
# The manifest and setup functions belong to this repository, so this runtime
# keeps installs, receipts, and read-only commands usable from a clean checkout
# without fetching a separate installer framework.

if [[ -n "${WWC_COMPONENT_RUNTIME_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WWC_COMPONENT_RUNTIME_SOURCED=1

# _wwc_component_field: Return one pipe-delimited manifest field by component id.
# Arguments: $1 - component id; $2 - zero-based manifest field index.
# Returns: 0 and prints the field, or 1 when the component is absent.
_wwc_component_field() {
  local wanted="$1" index="$2" entry id
  local -a fields
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r -a fields <<<"$entry"
    id="${fields[0]:-}"
    if [[ "$id" == "$wanted" ]]; then
      printf '%s' "${fields[$index]:-}"
      return 0
    fi
  done
  return 1
}

# _wwc_all_component_ids: Print component IDs in manifest order.
# Arguments: none.
# Returns: 0.
_wwc_all_component_ids() {
  local entry id rest
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id rest <<<"$entry"
    printf '%s\n' "$id"
  done
}

# _wwc_default_component_ids: Print components whose manifest default is on.
# Arguments: none.
# Returns: 0.
_wwc_default_component_ids() {
  local entry id label default rest
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default rest <<<"$entry"
    [[ "$default" == "on" ]] && printf '%s\n' "$id"
  done
}

# _wwc_receipt_directory: Resolve per-user install receipts for this project.
# Arguments: none.
# Returns: 0 and prints the receipt directory.
_wwc_receipt_directory() {
  local state_home
  if [[ -n "${ISC_RECEIPT_DIR:-}" ]]; then
    printf '%s/%s' "$ISC_RECEIPT_DIR" "${ISC_REPO_NAME:-installer}"
    return 0
  fi
  if [[ "$(id -u)" != "${TARGET_UID:-$(id -u)}" ]]; then
    # sudo's XDG_STATE_HOME may belong to root; target state must stay writable
    # by the desktop account when a later installer run is unprivileged.
    state_home="${TARGET_HOME:?}/.local/state"
  else
    state_home="${XDG_STATE_HOME:-${TARGET_HOME:-$HOME}/.local/state}"
  fi
  printf '%s/isc/receipts/%s' "$state_home" "${ISC_REPO_NAME:-installer}"
}

# _wwc_component_installed: Check a manifest detector or local install receipt.
# Arguments: $1 - component id.
# Returns: 0 when installed, 1 when absent.
_wwc_component_installed() {
  local id="$1" detector receipt_dir
  detector="$(_wwc_component_field "$id" 4)" || return 1
  if [[ -n "$detector" ]] && declare -F "$detector" >/dev/null 2>&1; then
    "$detector"
    return $?
  fi
  receipt_dir="$(_wwc_receipt_directory)"
  [[ -f "$receipt_dir/$id" ]]
}

# _wwc_mark_installed: Write a receipt after a component function succeeds.
# Arguments: $1 - component id.
# Returns: 0, including when state storage is unavailable.
_wwc_mark_installed() {
  local id="$1" receipt_dir
  receipt_dir="$(_wwc_receipt_directory)"
  if run_as_target mkdir -p "$receipt_dir" 2>/dev/null; then
    if ! printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" | \
      run_as_target tee "$receipt_dir/$id" >/dev/null 2>&1; then
      wwc_log WARNING "Could not write component receipt $receipt_dir/$id"
    fi
  else
    wwc_log WARNING "Could not create component receipt directory $receipt_dir"
  fi
}

# _wwc_clear_receipt: Remove a component's local install marker.
# Arguments: $1 - component id.
# Returns: 0.
_wwc_clear_receipt() {
  local receipt_dir
  receipt_dir="$(_wwc_receipt_directory)"
  run_as_target rm -f "$receipt_dir/$1" 2>/dev/null || true
}

# _wwc_config_file: Resolve a config name to a file in installation_configs.
# Arguments: $1 - config name, optionally ending in .json.
# Returns: 0 and prints the path, or 1 for an unsafe or missing name.
_wwc_config_file() {
  local name="$1"
  [[ -n "$name" ]] || name="default.json"
  [[ "$name" == *.json ]] || name+=".json"
  [[ "$name" != */* && "$name" != *..* ]] || return 1
  [[ -f "$SCRIPT_DIR/installation_configs/$name" ]] || return 1
  printf '%s/installation_configs/%s' "$SCRIPT_DIR" "$name"
}

# _wwc_config_component_ids: Read selected IDs from a validated config file.
# Arguments: $1 - config name.
# Returns: 0 and prints enabled IDs, or 1 for invalid/missing JSON.
_wwc_config_component_ids() {
  local config_path
  config_path="$(_wwc_config_file "$1")" || {
    msg "ERROR: installation config '$1' was not found under installation_configs/" >&2
    return 1
  }
  _wwc_selection_config selected "$config_path"
}

# _wwc_list_components: Emit the machine-readable component manifest.
# Arguments: none.
# Returns: 0.
_wwc_list_components() {
  local entry id label default install detect uninstall section requires
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default install detect uninstall section requires <<<"$entry"
    if [[ -n "$requires" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$label" "$default" "$section" "$requires"
    elif [[ -n "$section" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$id" "$label" "$default" "$section"
    else
      printf '%s\t%s\t%s\n' "$id" "$label" "$default"
    fi
  done
}

# _wwc_export_selection: Print normalized standalone-selection JSON.
# Arguments: $1 - config name or empty; $2 - 1 when config was explicit.
# Returns: 0 on valid input, 1 on missing or malformed config.
_wwc_export_selection() {
  local config_path=""
  local explicit="$2"
  if [[ "$explicit" == "1" ]]; then
    config_path="$(_wwc_config_file "$1")" || {
      msg "ERROR: installation config '$1' was not found under installation_configs/" >&2
      return 1
    }
  fi
  _wwc_selection_config export "$config_path"
}

# _wwc_selection_config: Resolve selected IDs or JSON through the shared parser.
# Arguments: $1 - selected or export; $2 - config path (empty uses defaults).
# Returns: the parser status.
_wwc_selection_config() {
  local entry id label default rest
  local -a manifest=()
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default rest <<<"$entry"
    manifest+=("$id=$([[ "$default" == "on" ]] && printf 1 || printf 0)")
  done
  python3 "$SCRIPT_DIR/lib/selection_config.py" "$1" \
    "${ISC_REPO_NAME:-linux_taskbar_window_count}" "$2" "${manifest[@]}"
}

# _wwc_validate_component_ids: Reject unknown selections before any mutation.
# Arguments: $1 - comma/space-separated component IDs.
# Returns: 0 for valid IDs (including an empty selection), 2 otherwise.
_wwc_validate_component_ids() {
  local requested="${1//,/ }" token
  local -a tokens=()
  IFS=$' \t\n' read -r -a tokens <<<"${requested//$'\n'/ }"
  for token in "${tokens[@]}"; do
    if ! _wwc_component_field "$token" 0 >/dev/null; then
      msg "ERROR: unknown component id '$token'" >&2
      return 2
    fi
  done
}

# _wwc_run_selected: Apply selected components in manifest order and record them.
# Arguments: $1 - comma/space-separated IDs; $2 - strict to reject unknown IDs.
# Returns: 0 when selected functions succeed, otherwise non-zero.
_wwc_run_selected() {
  local requested="$1" strictness="${2:-derived}" selected=" " token entry id label default fn
  local -a failed=() tokens=()
  requested="${requested//,/ }"
  IFS=$' \t\n' read -r -a tokens <<<"${requested//$'\n'/ }"
  for token in "${tokens[@]}"; do
    if ! _wwc_component_field "$token" 0 >/dev/null; then
      msg "ERROR: unknown component id '$token'" >&2
      [[ "$strictness" == "strict" ]] && return 2
      continue
    fi
    [[ "$selected" == *" $token "* ]] || selected+="$token "
  done

  local ran=0 detect uninstall section requires
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default fn detect uninstall section requires <<<"$entry"
    [[ "$selected" == *" $id "* ]] || continue
    if [[ -z "$fn" ]] || ! declare -F "$fn" >/dev/null 2>&1; then
      msg "WARN: install function for '$id' is not defined; skipping"
      failed+=("$id")
      continue
    fi
    ran=$((ran + 1))
    msg "[$ISC_REPO_NAME] Installing component: $label ($id)"
    if "$fn"; then
      _wwc_mark_installed "$id"
    else
      msg "WARN: component '$id' failed"
      failed+=("$id")
    fi
  done
  if (( ran == 0 )); then
    msg "[$ISC_REPO_NAME] No components selected — nothing to do."
  fi
  if (( ${#failed[@]} > 0 )); then
    msg "[$ISC_REPO_NAME] Components with failures: ${failed[*]}"
    return 1
  fi
}

# _wwc_uninstall_selected: Reverse selected component settings and receipts.
# Arguments: $1 - comma/space-separated IDs.
# Returns: 0 when removals succeed, otherwise 1 or 2 for invalid IDs.
_wwc_uninstall_selected() {
  local requested="${1//,/ }" selected=" " token i entry id label default fn detect uninstall
  local -a ordered=() failed=() tokens=()
  IFS=$' \t\n' read -r -a tokens <<<"${requested//$'\n'/ }"
  for token in "${tokens[@]}"; do
    if ! _wwc_component_field "$token" 0 >/dev/null; then
      msg "ERROR: unknown component id '$token'" >&2
      return 2
    fi
    selected+="$token "
  done
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default fn detect uninstall <<<"$entry"
    ordered+=("$id")
  done
  local ran=0
  for ((i=${#ordered[@]} - 1; i >= 0; i--)); do
    id="${ordered[$i]}"
    [[ "$selected" == *" $id "* ]] || continue
    ran=$((ran + 1))
    label="$(_wwc_component_field "$id" 1)"
    uninstall="$(_wwc_component_field "$id" 5)"
    if [[ -n "$uninstall" ]] && declare -F "$uninstall" >/dev/null 2>&1; then
      msg "[$ISC_REPO_NAME] Uninstalling component: $label ($id)"
      if "$uninstall"; then
        _wwc_clear_receipt "$id"
      else
        failed+=("$id")
        msg "WARN: uninstall of '$id' failed"
      fi
    else
      _wwc_clear_receipt "$id"
    fi
  done
  (( ran > 0 )) || msg "[$ISC_REPO_NAME] No components selected to uninstall — nothing to do."
  (( ${#failed[@]} == 0 )) || { msg "[$ISC_REPO_NAME] Components with uninstall failures: ${failed[*]}"; return 1; }
}

# _wwc_print_help: Show installer commands supported by this repository.
# Arguments: none.
# Returns: 0.
_wwc_print_help() {
  cat <<EOF
${ISC_REPO_NAME:-installer} — component-based installer

Usage:
  bash install.sh                 Interactive component selection (TTY), else defaults
  bash install.sh --config NAME   Load installation_configs/NAME.json
  bash install.sh --default       Install all default-on components
  bash install.sh --all           Install every component
  bash install.sh --select a,b,c  Install exactly these component IDs
  bash install.sh --reconfigure a,b,c  Re-apply selected component settings
  bash install.sh --uninstall a,b,c    Uninstall selected components
  bash install.sh --auth          Accept the setup chain's compatibility flag
  bash install.sh --list-components  List component IDs and labels
  bash install.sh --list-configurable-components  No nested screens (empty output)
  bash install.sh --list-select-configure-components  No nested screens (empty output)
  bash install.sh --list-component-config-values  No nested values (empty output)
  bash install.sh --configure-component ID  Report no nested screen (status 2)
  bash install.sh --detect        Show id<TAB>installed|absent state
  bash install.sh --export-selection  Export resolved selection as JSON
  bash install.sh --help          Show this help

Components:
$(_wwc_list_components | sed 's/^/  /')
EOF
}

# _wwc_interactive_selection: Ask for component IDs in a terminal session.
# Arguments: $1 - validated default component IDs.
# Returns: 0 and sets WWC_SELECTED_IDS / WWC_UNINSTALL_IDS; 1 on cancel/error.
_wwc_interactive_selection() {
  local defaults="$1" id
  printf 'Taskbar window-count components:\n'
  _wwc_list_components | while IFS=$'\t' read -r id label default; do
    printf '  %-20s %s\n' "$id" "$label"
  done
  printf 'Default selection: %s\n' "${defaults:-none}"
  read -r -p 'IDs to install or reconfigure [Enter keeps defaults, q cancels]: ' WWC_SELECTED_IDS || return 1
  [[ "$WWC_SELECTED_IDS" != "q" ]] || return 1
  [[ -n "$WWC_SELECTED_IDS" ]] || WWC_SELECTED_IDS="$defaults"
  read -r -p 'IDs to uninstall [Enter for none]: ' WWC_UNINSTALL_IDS || return 1
}

# component_main: Route supported installer commands and component actions.
# Arguments: $@ - command-line arguments passed by install.sh.
# Returns: the selected operation's status.
component_main() {
  local mode="" command="" selected_ids="" uninstall_ids=""
  local config_name="default.json" config_explicit=0 arg
  while (($#)); do
    case "$1" in
      --list-components|--list-configurable-components|--list-select-configure-components|--list-component-config-values|--detect|--export-selection)
        command="$1"
        ;;
      --configure-component|--config|--select|--reconfigure|--uninstall)
        if [[ $# -lt 2 || "$2" == -* ]]; then
          msg "ERROR: $1 requires an explicit argument" >&2
          return 2
        fi
        case "$1" in
          --configure-component) command="--configure-component" ;;
          --config) config_name="$2"; config_explicit=1 ;;
          --select|--reconfigure) mode="select"; selected_ids="$2" ;;
          --uninstall) mode="uninstall"; selected_ids="$2" ;;
        esac
        shift
        ;;
      --configure-component=*) command="--configure-component" ;;
      --config=*) config_name="${1#*=}"; config_explicit=1 ;;
      --default) mode="default" ;;
      --all) mode="all" ;;
      --select=*|--reconfigure=*) mode="select"; selected_ids="${1#*=}" ;;
      --uninstall=*) mode="uninstall"; selected_ids="${1#*=}" ;;
      --auth) INSTALLER_AUTH=1; export INSTALLER_AUTH ;;
      --help|-h) command="--help" ;;
      *) msg "ERROR: unknown argument: $1" >&2; _wwc_print_help >&2; return 2 ;;
    esac
    shift
  done

  # Parse all flags before dispatch so read-only commands honor --config in
  # either order and invalid input never reaches the desktop deployment.
  case "$command" in
    --list-components) _wwc_list_components; return 0 ;;
    --list-configurable-components|--list-select-configure-components|--list-component-config-values) return 0 ;;
    --configure-component)
      msg "ERROR: this installer has no nested component configuration screens" >&2
      return 2
      ;;
    --detect)
      while IFS= read -r arg; do
        [[ -n "$arg" ]] || continue
        if _wwc_component_installed "$arg"; then printf '%s\tinstalled\n' "$arg"; else printf '%s\tabsent\n' "$arg"; fi
      done < <(_wwc_all_component_ids)
      return 0
      ;;
    --export-selection) _wwc_export_selection "$config_name" "$config_explicit"; return $? ;;
    --help) _wwc_print_help; return 0 ;;
  esac

  case "$mode" in
    default) selected_ids="$(_wwc_default_component_ids)" ;;
    all) selected_ids="$(_wwc_all_component_ids)" ;;
    select|uninstall) ;;
    *)
      selected_ids="$(_wwc_config_component_ids "$config_name")" || return 1
      if [[ -t 0 && -t 1 ]]; then
        if ! _wwc_interactive_selection "$selected_ids"; then
          msg 'Selection cancelled — nothing changed.'
          return 0
        fi
        selected_ids="$WWC_SELECTED_IDS"
        uninstall_ids="$WWC_UNINSTALL_IDS"
      fi
      ;;
  esac
  _wwc_validate_component_ids "$selected_ids" || return $?
  _wwc_validate_component_ids "$uninstall_ids" || return $?
  if [[ "$mode" == "uninstall" ]]; then
    _wwc_uninstall_selected "$selected_ids"
    return $?
  fi

  msg "=== Linux Taskbar Window Count Setup ==="
  install_window_count_extension
  msg "Configuring window-count badge options"
  if [[ -n "$uninstall_ids" ]]; then
    _wwc_uninstall_selected "$uninstall_ids" || return $?
  fi
  _wwc_run_selected "$selected_ids" strict
}
