#!/usr/bin/env bash
# Require native selection without touching a real extension or desktop.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
SCRIPT_DIR="$ROOT"
TARGET_HOME="$fixture/home"
mkdir -p "$TARGET_HOME" "$fixture/bin"
printf '#!/bin/bash\nprintf attempted > "$WWC_PYTHON_SENTINEL"\nexit 95\n' > "$fixture/bin/python3"
chmod +x "$fixture/bin/python3"
export WWC_PYTHON_SENTINEL="$fixture/python-called"
export PATH="$fixture/bin:$PATH"
ISC_REPO_NAME=fixture
ISC_COMPONENTS=('first|First|on|unused' 'second|Second|off|unused')
source "$ROOT/lib/component_runtime.sh"
# Simulate an unavailable native builder, preserving the original fixture data.
# Parameters: none. Returns: failure without side effects.
ensure_wwc_bin() { return 1; }
if _wwc_selection_config export '' > "$fixture/out" 2> "$fixture/err"; then exit 1; fi
[[ ! -e "$WWC_PYTHON_SENTINEL" ]]
# The standalone runtime must load its native resolver when not already sourced.
unset -f ensure_wwc_bin
WWC_BIN="$ROOT/target/release/wwc-tools"
for round in 1 2; do
  [[ "$(_wwc_selection_config selected '')" == first ]]
done
printf 'Native selection refuses interpreter fallback and repeats expected flags\n'
