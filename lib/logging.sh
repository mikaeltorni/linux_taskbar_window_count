#!/usr/bin/env bash
# Centralized Bash logging for linux_taskbar_window_count installers.
#
# Source this file from Bash scripts that need repository-local diagnostics.
# File logging is best-effort and does not change stdout or stderr contracts;
# wwc_log_stderr is available to build tools that need visible diagnostics.

if [[ -z "${TASKBAR_WINDOW_COUNT_LOGGING_SH_LOADED:-}" ]]; then
  TASKBAR_WINDOW_COUNT_LOGGING_SH_LOADED=1

  _wwc_log_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  WWC_LOG_DIR="${TASKBAR_WINDOW_COUNT_LOG_DIR:-$_wwc_log_root/.log}"
  WWC_INSTALL_LOG="${WWC_INSTALL_LOG:-$WWC_LOG_DIR/install.log}"

  # wwc_log: Append one timestamped line to the centralized installer log.
  # Arguments: $1 - level, $* - message text.
  # Returns: 0 always; logging failures are intentionally ignored.
  wwc_log() {
    local level="${1:-INFO}"
    shift || true
    mkdir -p "$WWC_LOG_DIR" 2>/dev/null || return 0
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" \
      >>"$WWC_INSTALL_LOG" 2>/dev/null || true
  }

  # wwc_log_stderr: Mirror one record to the central log and stderr.
  # Arguments: $1 - level, $* - message text.
  # WWC_LOG_COMPONENT optionally labels the stderr line; file logging remains
  # routed through wwc_log. Stdout is never used.
  # Returns: 0 always, including when the log directory is unavailable.
  wwc_log_stderr() {
    local level="${1:-INFO}"
    shift || true
    local message="$*"
    wwc_log "$level" "$message"
    case "$level" in
      ERROR) printf '[%s] ERROR: %s\n' "${WWC_LOG_COMPONENT:-linux_taskbar_window_count}" "$message" >&2 ;;
      WARN) printf '[%s] WARNING: %s\n' "${WWC_LOG_COMPONENT:-linux_taskbar_window_count}" "$message" >&2 ;;
      *) printf '[%s] %s\n' "${WWC_LOG_COMPONENT:-linux_taskbar_window_count}" "$message" >&2 ;;
    esac
    return 0
  }

  # wwc_log_call: Record a Bash function boundary in the centralized log.
  # Arguments: $1 - ENTER or EXIT, $2 - function name, $3... - optional context.
  # Returns: 0 always.
  wwc_log_call() {
    local boundary="${1:-TRACE}" function_name="${2:-unknown}"
    shift 2 || true
    wwc_log DEBUG "$boundary $function_name $*"
  }
fi
