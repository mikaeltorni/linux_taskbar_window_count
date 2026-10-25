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

# Convert one raw comma/whitespace selection without glob expansion.
# Parameters: $1 - raw IDs. Returns: zero and _WWC_PARSED_IDS, or two for malformed spelling.
_wwc_parse_ids() {
  printf 'raw_ids=%s\n' "$1" >&2
  local raw="$1" id
  _WWC_PARSED_IDS=()
  if [[ "$raw" == ,* || "$raw" == *, || "$raw" =~ ,[[:space:]]*, ]]; then
    printf 'ERROR: malformed component list\n2\n' >&2; return 2
  fi
  raw="${raw//,/ }"
  raw="${raw//$'\n'/ }"
  IFS=$' \t' read -r -a _WWC_PARSED_IDS <<< "$raw"
  for id in "${_WWC_PARSED_IDS[@]}"; do
    if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]]; then
      printf 'ERROR: malformed component identifier: %s\n2\n' "$id" >&2; return 2
    fi
  done
  printf 'ids=%s status=0\n' "${_WWC_PARSED_IDS[*]}" >&2
  return 0
}

# Normalize a local config filename, preserving the documented optional suffix.
# Parameters: $1 - raw config name. Returns: zero and _WWC_PARSED_CONFIG, or two for invalid local spelling.
_wwc_parse_config_name() {
  printf 'raw_name=%s\n' "$1" >&2
  local name="${1:-default.json}"
  if [[ "$name" == */* || "$name" == *..* ]]; then
    printf 'ERROR: config must name a local installation_configs file\n2\n' >&2; return 2
  fi
  [[ "$name" == *.json ]] || name+=.json
  _WWC_PARSED_CONFIG="$name"
  printf 'name=%s status=0\n' "$name" >&2
  return 0
}

# Parse the complete command before returning ready selector/config/auth/ID values.
# Parameters: $@ - raw installer arguments. Returns: zero and _WWC_REQUEST_* globals, or two for malformed syntax.
_wwc_parse_arguments() {
  printf 'arguments=%s\n' "$*" >&2
  local action=auto config=default.json explicit=0 auth=0 token value ids="" mode_seen=0
  while (( $# )); do
    token="$1"; shift
    case "$token" in
      --auth) auth=1; continue ;;
      --config|--select|--reconfigure|--uninstall|--configure-component)
        if (( $# == 0 )) || [[ "$1" == -* ]]; then
          printf 'ERROR: %s requires an explicit operand\n2\n' "$token" >&2; return 2
        fi
        value="$1"; shift ;;
      --config=*|--select=*|--reconfigure=*|--uninstall=*|--configure-component=*)
        value="${token#*=}"; token="${token%%=*}" ;;
      --default|--all|--help|-h|--list-components|--list-configurable-components|--list-select-configure-components|--list-component-config-values|--detect|--export-selection)
        value="" ;;
      *) printf 'ERROR: unknown argument: %s\n2\n' "$token" >&2; return 2 ;;
    esac
    if [[ "$token" == --config ]]; then
      if (( explicit )); then printf 'ERROR: duplicate config option\n2\n' >&2; return 2; fi
      _wwc_parse_config_name "$value" || { printf '2\n' >&2; return 2; }
      config="$_WWC_PARSED_CONFIG"; explicit=1
      continue
    fi
    if (( mode_seen )); then printf 'ERROR: conflicting installer actions\n2\n' >&2; return 2; fi
    mode_seen=1
    case "$token" in
      --select|--reconfigure) action=select; ids="$value" ;;
      --uninstall) action=uninstall; ids="$value" ;;
      --default) action=default ;;
      --all) action=all ;;
      -h) action=--help ;;
      *) action="$token"; ids="$value" ;;
    esac
    if [[ "$token" == --configure-component && ( -z "$value" || "$value" == *[,$' \t\n']* ) ]]; then
      printf 'ERROR: configure-component needs exactly one identifier\n2\n' >&2; return 2
    fi
  done
  _wwc_parse_ids "$ids" || { printf '2\n' >&2; return 2; }
  _WWC_REQUEST_ACTION="$action"; _WWC_REQUEST_CONFIG="$config"
  _WWC_REQUEST_EXPLICIT="$explicit"; _WWC_REQUEST_AUTH="$auth"
  _WWC_REQUEST_IDS=("${_WWC_PARSED_IDS[@]}")
  printf 'action=%s config=%s explicit=%s auth=%s ids=%s status=0\n' "$action" "$config" "$explicit" "$auth" "${_WWC_REQUEST_IDS[*]}" >&2
  return 0
}

# Parse one independent terminal request, including cancellation and empty install selection.
# Parameters: $@ - converted default IDs. Returns: zero and _WWC_MENU_* values, or two for malformed input.
_wwc_parse_menu_request() {
  printf 'defaults=%s\n' "$*" >&2
  local selected removed
  _WWC_MENU_ACTION=apply
  _WWC_MENU_APPLY=(); _WWC_MENU_REMOVE=()
  if ! read -r -p 'IDs to install or reconfigure [Enter defaults, - none, q cancels]: ' selected; then
    _WWC_MENU_ACTION=cancel
  elif [[ "$selected" == q ]]; then
    _WWC_MENU_ACTION=cancel
  else
    if [[ -z "$selected" ]]; then
      _WWC_MENU_APPLY=("$@")
    elif [[ "$selected" != - ]]; then
      _wwc_parse_ids "$selected" || { printf '2\n' >&2; return 2; }
      _WWC_MENU_APPLY=("${_WWC_PARSED_IDS[@]}")
    fi
    if ! read -r -p 'IDs to uninstall [Enter for none]: ' removed; then
      _WWC_MENU_ACTION=cancel
    else
      _wwc_parse_ids "$removed" || { printf '2\n' >&2; return 2; }
      _WWC_MENU_REMOVE=("${_WWC_PARSED_IDS[@]}")
    fi
  fi
  printf 'action=%s apply=%s remove=%s status=0\n' "$_WWC_MENU_ACTION" "${_WWC_MENU_APPLY[*]}" "${_WWC_MENU_REMOVE[*]}" >&2
  return 0
}



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

# _wwc_selection_config: Resolve selected IDs or JSON through the shared parser.
# Parameters: $1 - selected or export; $2 - config path (empty uses defaults).
# Returns: native parser status, or failure when unavailable.
_wwc_selection_config() {
  local entry id label default rest
  local -a manifest=()
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default rest <<<"$entry"
    manifest+=("$id=$([[ "$default" == "on" ]] && printf 1 || printf 0)")
  done
  if ! declare -F ensure_wwc_bin >/dev/null 2>&1; then
    source "${SCRIPT_DIR:?SCRIPT_DIR unset}/lib/wwc_bin.sh" || return 1
  fi
  ensure_wwc_bin || return 1
  "$WWC_BIN" --selection "$1" \
    "${ISC_REPO_NAME:-linux_taskbar_window_count}" "$2" "${manifest[@]}"
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

# Reject missing manifests, unknown IDs and duplicates using fully converted arguments.
# Parameters: $@ - converted component IDs. Returns: zero, or two without mutation for invalid resources/selections.
_wwc_validate_component_ids() {
  printf 'ids=%s\n' "$*" >&2
  local id
  local -A seen=()
  if ! declare -p ISC_COMPONENTS >/dev/null 2>&1 || (( ${#ISC_COMPONENTS[@]} == 0 )); then
    printf 'ERROR: component manifest is missing\n2\n' >&2; return 2
  fi
  for id in "$@"; do
    if [[ -n "${seen[$id]:-}" ]] || ! _wwc_component_field "$id" 0 >/dev/null; then
      printf 'ERROR: unknown or duplicate component id: %s\n2\n' "$id" >&2; return 2
    fi
    seen[$id]=1
  done
  printf '0\n' >&2
  return 0
}

# Validate every selected callback before core/files/settings can change.
# Parameters: $1 - install or uninstall action; remaining - converted IDs. Returns: zero, or two for unavailable callbacks.
_wwc_validate_callbacks() {
  printf 'action=%s ids=%s\n' "$1" "${*:2}" >&2
  local action="$1" id callback index=3
  shift
  _wwc_validate_component_ids "$@" || { printf '2\n' >&2; return 2; }
  [[ "$action" != uninstall ]] || index=5
  for id in "$@"; do
    callback="$(_wwc_component_field "$id" "$index")"
    if [[ "$action" == uninstall && -z "$callback" ]]; then continue; fi
    if [[ -z "$callback" ]] || ! declare -F "$callback" >/dev/null 2>&1; then
      printf 'ERROR: component callback unavailable: %s\n2\n' "$id" >&2; return 2
    fi
  done
  printf '0\n' >&2
  return 0
}

# Require an existing normalized local configuration resource.
# Parameters: $1 - resolved JSON path. Returns: zero, or one without installer effects when missing.
_wwc_validate_config_file() {
  printf 'config_path=%s\n' "$1" >&2
  if [[ ! -f "$1" ]]; then
    printf 'ERROR: installation config was not found: %s\n1\n' "$1" >&2; return 1
  fi
  printf '0\n' >&2
  return 0
}

# Report the deliberately unsupported nested-screen resource.
# Parameters: $@ - converted component IDs. Returns: two because this owner has no nested configuration screens.
_wwc_validate_nested_screen() {
  printf 'ids=%s\n' "$*" >&2
  printf 'ERROR: this installer has no nested component configuration screens\n2\n' >&2
  return 2
}

# Resolve a parsed config name to its accepted file resource.
# Parameters: $1 - normalized local filename. Returns: zero and its printed path, or one if unavailable.
_wwc_config_file() {
  printf 'config_name=%s\n' "$1" >&2
  local path="$SCRIPT_DIR/installation_configs/$1" status=0
  _wwc_validate_config_file "$path" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  printf '%s\n' "$path"
  printf 'path=%s status=0\n' "$path" >&2
  return 0
}

# Resolve config-selected IDs with the Rust JSON parser and decode its line protocol.
# Parameters: $1 - normalized local config name. Returns: native status and _WWC_CONFIG_IDS as converted identifiers.
_wwc_config_component_ids() {
  printf 'config_name=%s\n' "$1" >&2
  local path output status=0
  _WWC_CONFIG_IDS=()
  path="$(_wwc_config_file "$1")" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  output="$(_wwc_selection_config selected "$path")" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  if [[ -n "$output" ]]; then mapfile -t _WWC_CONFIG_IDS <<< "$output"; fi
  _wwc_validate_component_ids "${_WWC_CONFIG_IDS[@]}" || { printf '2\n' >&2; return 2; }
  printf 'ids=%s status=0\n' "${_WWC_CONFIG_IDS[*]}" >&2
  return 0
}

# Export the same Rust-resolved selection used for installation.
# Parameters: $1 - normalized config name; $2 - whether a config was explicitly requested. Returns: native status and JSON output.
_wwc_export_selection() {
  printf 'config_name=%s explicit=%s\n' "$1" "$2" >&2
  local path="" status=0
  if [[ "$2" == 1 ]]; then
    path="$(_wwc_config_file "$1")" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  fi
  _wwc_selection_config export "$path" || status=$?
  printf '%s\n' "$status" >&2
  return "$status"
}

# Apply converted component IDs in manifest order and record successful operations.
# Parameters: $@ - converted IDs. Returns: zero, one for execution failures or two for invalid callback resources.
_wwc_run_selected() {
  printf 'ids=%s\n' "$*" >&2
  _wwc_validate_callbacks install "$@" || { printf '2\n' >&2; return 2; }
  local entry id label default fn token
  local -A selected=()
  local -a failed=()
  for token in "$@"; do selected[$token]=1; done
  for entry in "${ISC_COMPONENTS[@]}"; do
    IFS='|' read -r id label default fn _ <<< "$entry"
    [[ "${selected[$id]:-0}" == 1 ]] || continue
    msg "[$ISC_REPO_NAME] Installing component: $label ($id)"
    if "$fn"; then _wwc_mark_installed "$id"; else failed+=("$id"); fi
  done
  if (( ${#failed[@]} )); then
    msg "[$ISC_REPO_NAME] Components with failures: ${failed[*]}"
    printf '1\n' >&2; return 1
  fi
  printf '0\n' >&2
  return 0
}

# Reverse converted component settings in reverse manifest order and clear receipts.
# Parameters: $@ - converted IDs. Returns: zero, one for execution failures or two for invalid callbacks.
_wwc_uninstall_selected() {
  printf 'ids=%s\n' "$*" >&2
  _wwc_validate_callbacks uninstall "$@" || { printf '2\n' >&2; return 2; }
  local entry id label default fn detect uninstall token index
  local -A selected=()
  local -a ordered=() failed=()
  for token in "$@"; do selected[$token]=1; done
  for entry in "${ISC_COMPONENTS[@]}"; do IFS='|' read -r id _ <<< "$entry"; ordered+=("$id"); done
  for (( index=${#ordered[@]}-1; index>=0; index-- )); do
    id="${ordered[$index]}"
    [[ "${selected[$id]:-0}" == 1 ]] || continue
    uninstall="$(_wwc_component_field "$id" 5)"
    if [[ -z "$uninstall" ]]; then
      msg "[$ISC_REPO_NAME] '$id' has no uninstall step; clearing its install record only."
      _wwc_clear_receipt "$id"
    elif "$uninstall"; then
      _wwc_clear_receipt "$id"
    else
      failed+=("$id")
    fi
  done
  if (( ${#failed[@]} )); then
    msg "[$ISC_REPO_NAME] Components with uninstall failures: ${failed[*]}"
    printf '1\n' >&2; return 1
  fi
  printf '0\n' >&2
  return 0
}

# Validate the entire install/remove plan before applying core or component changes.
# Parameters: $1 - name of the converted install array; $2 - name of the converted removal array. Returns: action status.
_wwc_apply_selection() {
  printf 'selected_name=%s removed_name=%s\n' "$1" "$2" >&2
  local -n selected="$1" removed="$2"
  local status=0
  _wwc_validate_callbacks install "${selected[@]}" || { printf '2\n' >&2; return 2; }
  _wwc_validate_callbacks uninstall "${removed[@]}" || { printf '2\n' >&2; return 2; }
  if (( ${#selected[@]} || ${#removed[@]} == 0 )); then
    msg "=== Linux Taskbar Window Count Setup ==="
    install_window_count_extension
    msg 'Configuring window-count badge options'
  fi
  if (( ${#removed[@]} )); then
    _wwc_uninstall_selected "${removed[@]}" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  fi
  _wwc_run_selected "${selected[@]}" || status=$?
  printf '%s\n' "$status" >&2
  return "$status"
}

# Present the terminal input boundary, parse it once and route its ready values.
# Parameters: $@ - converted default IDs. Returns: zero on cancellation or the selected operation status.
_wwc_interactive_selection() {
  printf 'default_ids=%s\n' "$*" >&2
  local id label default status=0
  printf 'Taskbar window-count components:\n'
  while IFS=$'\t' read -r id label default; do printf '  %-20s %s\n' "$id" "$label"; done < <(_wwc_list_components)
  printf 'Default selection:'; printf ' %s' "$@"; printf '\n'
  _wwc_parse_menu_request "$@" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  case "$_WWC_MENU_ACTION" in
    cancel) msg 'Selection cancelled — nothing changed.' ;;
    apply) _wwc_apply_selection _WWC_MENU_APPLY _WWC_MENU_REMOVE; status=$? ;;
  esac
  printf '%s\n' "$status" >&2
  return "$status"
}

# Handle accepted read-only queries and unsupported nested screens without core work.
# Parameters: $1 - query selector; $2 - normalized config; $3 - explicit-config flag; remaining - converted IDs. Returns: query status.
_wwc_query() {
  printf 'query=%s config=%s explicit=%s ids=%s\n' "$1" "$2" "$3" "${*:4}" >&2
  local query="$1" config="$2" explicit="$3" id status=0
  shift 3
  _wwc_validate_component_ids "$@" || { printf '2\n' >&2; return 2; }
  case "$query" in
    --list-components) _wwc_list_components ;;
    --list-configurable-components|--list-select-configure-components|--list-component-config-values) : ;;
    --help) _wwc_print_help ;;
    --configure-component) _wwc_validate_nested_screen "$@" || status=$? ;;
    --detect)
      while IFS= read -r id; do
        if _wwc_component_installed "$id"; then printf '%s\tinstalled\n' "$id"; else printf '%s\tabsent\n' "$id"; fi
      done < <(_wwc_all_component_ids)
      ;;
    --export-selection) _wwc_export_selection "$config" "$explicit" || status=$? ;;
  esac
  printf '%s\n' "$status" >&2
  return "$status"
}

# Resolve derived/native configuration selections, then use the same array operations as the terminal.
# Parameters: $1 - action; $2 - parsed config; $3 - explicit-config flag; $4 - auth flag; remaining - converted IDs. Returns: operation status.
_wwc_apply_request() {
  printf 'action=%s config=%s explicit=%s auth=%s ids=%s\n' "$1" "$2" "$3" "$4" "${*:5}" >&2
  local action="$1" config="$2" explicit="$3" auth="$4" id status=0
  shift 4
  local -a apply_ids=("$@") remove_ids=()
  _wwc_validate_component_ids "$@" || { printf '2\n' >&2; return 2; }
  if [[ "$auth" == 1 ]]; then INSTALLER_AUTH=1; export INSTALLER_AUTH; fi
  case "$action" in
    --*) _wwc_query "$action" "$config" "$explicit" "$@"; status=$? ;;
    uninstall) _wwc_uninstall_selected "$@"; status=$? ;;
    *)
      case "$action" in
        default) mapfile -t apply_ids < <(_wwc_default_component_ids) ;;
        all) mapfile -t apply_ids < <(_wwc_all_component_ids) ;;
        auto)
          _wwc_config_component_ids "$config" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
          apply_ids=("${_WWC_CONFIG_IDS[@]}")
          if [[ -t 0 && -t 1 ]]; then
            _wwc_interactive_selection "${apply_ids[@]}"; status=$?
            printf '%s\n' "$status" >&2
            return "$status"
          fi
          ;;
      esac
      _wwc_apply_selection apply_ids remove_ids; status=$?
      ;;
  esac
  printf '%s\n' "$status" >&2
  return "$status"
}

# Dispatch exactly one complete command parse to its operation.
# Parameters: $@ - raw installer arguments. Returns: the parser or operation status.
component_main() {
  printf 'arguments=%s\n' "$*" >&2
  local status=0
  _wwc_parse_arguments "$@" || { status=$?; printf '%s\n' "$status" >&2; return "$status"; }
  _wwc_apply_request "$_WWC_REQUEST_ACTION" "$_WWC_REQUEST_CONFIG" "$_WWC_REQUEST_EXPLICIT" "$_WWC_REQUEST_AUTH" "${_WWC_REQUEST_IDS[@]}"; status=$?
  printf '%s\n' "$status" >&2
  return "$status"
}
