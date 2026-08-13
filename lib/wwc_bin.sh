#!/usr/bin/env bash
# wwc_bin.sh — Resolve and invoke the wwc-tools Rust helper.
#
# Sourced by install.sh / lib/window_count_setup.sh after SCRIPT_DIR is set.
# Builds the binary on demand via scripts/build_wwc_tools.sh.
#
# Public functions:
#   ensure_wwc_bin  — build/locate dist/wwc-tools; sets WWC_BIN
#   wwc_bin         — ensure_wwc_bin then run it with "$@"

# ensure_wwc_bin — Locate or build dist/wwc-tools; export WWC_BIN.
ensure_wwc_bin() {
  local build_script bin
  build_script="${SCRIPT_DIR:?SCRIPT_DIR unset}/scripts/build_wwc_tools.sh"
  if [ -n "${WWC_BIN:-}" ] && [ -x "$WWC_BIN" ]; then
    return 0
  fi
  if [ ! -x "$build_script" ]; then
    if declare -F msg >/dev/null 2>&1; then
      msg "Missing build helper: $build_script"
    else
      printf 'Missing build helper: %s\n' "$build_script" >&2
    fi
    return 1
  fi
  bin="$(bash "$build_script" --print)" || return 1
  WWC_BIN="$bin"
  export WWC_BIN
}

# wwc_bin — Run the helper CLI.
wwc_bin() {
  ensure_wwc_bin || return 1
  "$WWC_BIN" "$@"
}
