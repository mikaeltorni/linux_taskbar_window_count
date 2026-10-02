#!/usr/bin/env bash
# Test Linux Taskbar Window Count installer behavior without sudo or shell side effects.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/linux-taskbar-window-count-test.XXXXXX)"
cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
BIN_DIR="$TMP_DIR/bin"
STATE_FILE="$TMP_DIR/gsettings-state"
TARGET_HOME="$TMP_DIR/home"
EXTENSION_UUID="workspace-window-count@local"
# Use the invoking account so install checks work on developer machines and VMs.
TEST_TARGET_USER="${SUDO_USER:-$(id -un)}"
export TEST_TARGET_USER
PASS=0
FAIL=0

# assert_file_exists: Assert that a path exists, updating PASS/FAIL counters.
# Arguments: $1 - path to check, $2 - message printed on failure.
# Returns: 0 always (records the result in the global counters).
assert_file_exists() {
  local path="$1" message="$2"
  if [ -e "$path" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $message (missing: $path)"
  fi
}

# assert_file_contains: Assert that a file contains a fixed-string needle,
# updating PASS/FAIL counters.
# Arguments: $1 - path, $2 - literal substring to find, $3 - failure message.
# Returns: 0 always (records the result in the global counters).
assert_file_contains() {
  local path="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$path"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $message"
  fi
}

# assert_eq: Assert that two strings are equal, updating PASS/FAIL counters.
# Arguments: $1 - expected value, $2 - actual value, $3 - failure message.
# Returns: 0 always (records the result in the global counters).
assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $message (expected '$expected', got '$actual')"
  fi
}

if grep -Fq "Phase 3 of 8" "$REPO_ROOT/README.md" || grep -Fq "8-Repo Desktop Setup Chain" "$REPO_ROOT/README.md"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: README still claims the obsolete 8-repo setup chain"
else
  PASS=$((PASS + 1))
fi

if grep -q 'SELECTED_FEATURES="${FEATURES:-}"' "$REPO_ROOT/install.sh"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: FEATURES filter must not skip the core extension deploy"
else
  PASS=$((PASS + 1))
fi
if grep -c 'Linux Taskbar Window Count Setup' "$REPO_ROOT/install.sh" | grep -qx 1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: install banner should appear once"
fi

# Ubuntu 24.04 ships Cargo 1.75, which requires lockfile format version 3.
LOCKFILE_VERSION="$(sed -n 's/^version = //p' "$REPO_ROOT/Cargo.lock" | head -1)"
assert_eq "3" "$LOCKFILE_VERSION" "Cargo.lock should remain readable by Ubuntu 24.04 Cargo 1.75"
RUST_VERSION="$(sed -n 's/^rust-version = "\([^"]*\)"/\1/p' "$REPO_ROOT/Cargo.toml" | head -1)"
assert_eq "1.75" "$RUST_VERSION" "Cargo.toml should declare the supported Ubuntu 24.04 Rust baseline"
LOCKED_BUILD_COUNT="$(grep -cF 'cargo build --locked --release --bin wwc-tools' "$REPO_ROOT/scripts/build_wwc_tools.sh" || true)"
assert_eq "2" "$LOCKED_BUILD_COUNT" "local and container builds should honor Cargo.lock"

mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "passwd" && "${2:-}" == "$TEST_TARGET_USER" ]]; then
  printf '%s\n' "__TARGET_HOME__"
  exit 0
fi
exec /usr/bin/getent "$@"
EOF
sed -i "s#__TARGET_HOME__#$TARGET_HOME#g" "$BIN_DIR/getent"
cat >"$BIN_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
args=()
while (($#)); do
  case "$1" in
    -H)
      shift || true
      ;;
    -u)
      shift; shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
exec "${args[@]}"
EOF
cat >"$BIN_DIR/gsettings" <<'EOF'
#!/usr/bin/env bash
# Mock gsettings: tracks the enabled-extensions list in a state file and records
# every schema `set` to a log file so component writes can be asserted. Tolerates
# the leading `--schemadir DIR` the per-key components pass.
args=("$@")
if [[ "${args[0]:-}" == "--schemadir" ]]; then
  args=("${args[@]:2}")
fi
op="${args[0]:-}" schema="${args[1]:-}" key="${args[2]:-}" value="${args[3]:-}"
if [[ "${GSETTINGS_FAIL_GET:-0}" == "1" && "$op" == "get" ]]; then
  exit 1
fi
if [[ "${GSETTINGS_FAIL_SET:-0}" == "1" && "$op" == "set" ]]; then
  exit 1
fi
if [[ "$op" == "set" ]]; then
  printf '%s\t%s\t%s\n' "$schema" "$key" "$value" >> "__SET_LOG__"
fi
if [[ "$op" == "get" && "$schema" == "org.gnome.shell" && "$key" == "enabled-extensions" ]]; then
  cat "__STATE_FILE__"
  exit 0
fi
if [[ "$op" == "set" && "$schema" == "org.gnome.shell" && "$key" == "enabled-extensions" ]]; then
  printf '%s\n' "$value" > "__STATE_FILE__"
  exit 0
fi
exit 0
EOF
sed -i "s#__STATE_FILE__#$STATE_FILE#g; s#__SET_LOG__#$TMP_DIR/gsettings-sets.log#g" "$BIN_DIR/gsettings"
SET_LOG="$TMP_DIR/gsettings-sets.log"
: >"$SET_LOG"

assert_file_contains "$REPO_ROOT/scripts/build_wwc_tools.sh" 'source "$REPO_ROOT/lib/logging.sh"' "Build helper should use the centralized Bash logger"
assert_file_contains "$REPO_ROOT/scripts/build_wwc_tools.sh" 'wwc_log_stderr ERROR' "Build helper errors should use the centralized stderr logger"
if grep -Eq '^[[:space:]]*log\(\)' "$REPO_ROOT/scripts/build_wwc_tools.sh"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: build helper must not define a local ad-hoc logger"
else
  PASS=$((PASS + 1))
fi
LOGGER_DIR="$TMP_DIR/build-logger"
TASKBAR_WINDOW_COUNT_LOG_DIR="$LOGGER_DIR" WWC_LOG_COMPONENT=build_wwc_tools \
  bash -c 'source "$1"; wwc_log_stderr INFO "build logger probe"; wwc_log_stderr ERROR "build logger error probe"' \
  _ "$REPO_ROOT/lib/logging.sh" >"$TMP_DIR/build-logger.stdout" \
  2>"$TMP_DIR/build-logger.stderr"
assert_eq "" "$(cat "$TMP_DIR/build-logger.stdout")" "Build logger must preserve stdout"
assert_file_contains "$TMP_DIR/build-logger.stderr" "[build_wwc_tools] build logger probe" "Build logger should make diagnostics visible on stderr"
assert_file_contains "$TMP_DIR/build-logger.stderr" "[build_wwc_tools] ERROR: build logger error probe" "Build logger should retain error severity on stderr"
assert_file_contains "$LOGGER_DIR/install.log" "[INFO] build logger probe" "Build logger should write through to the central file sink"
assert_file_contains "$LOGGER_DIR/install.log" "[ERROR] build logger error probe" "Build logger should write error severity to the central file sink"

chmod +x "$BIN_DIR/getent" "$BIN_DIR/sudo" "$BIN_DIR/gsettings"
printf "['app-rules@local']\n" >"$STATE_FILE"

# A clean standalone checkout must install without locating or downloading the
# private shared component framework. Keep HOME and cache paths isolated, and
# fail the regression if the installer attempts any Git operation.
STANDALONE_HOME="$TMP_DIR/standalone-home"
STANDALONE_STATE="$TMP_DIR/standalone-state"
GIT_CALL_LOG="$TMP_DIR/standalone-git.log"
mkdir -p "$STANDALONE_HOME"
cat >"$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_CALL_LOG"
exit 81
EOF
chmod +x "$BIN_DIR/git"
if ! PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 \
  HOME="$STANDALONE_HOME" XDG_CACHE_HOME="$STANDALONE_HOME/.cache" \
  XDG_STATE_HOME="$STANDALONE_STATE" ISC_FUNCTIONS_DIR= \
  GIT_CALL_LOG="$GIT_CALL_LOG" bash "$REPO_ROOT/install.sh" --auth --all \
  >"$TMP_DIR/standalone.out" 2>"$TMP_DIR/standalone.err"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: standalone installation should not require the shared component framework"
  cat "$TMP_DIR/standalone.out" "$TMP_DIR/standalone.err" >&2
else
  PASS=$((PASS + 1))
fi
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "Standalone installation should deploy the extension without the private framework"
if [ -s "$GIT_CALL_LOG" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: standalone installation should not fetch the private shared framework"
else
  PASS=$((PASS + 1))
fi

: >"$SET_LOG"
PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" >"$TMP_DIR/install-1.out" 2>"$TMP_DIR/install-1.err" || FAIL=$((FAIL + 1))

assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "Should deploy extension.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/badgeLifecycle.js" "Should deploy badgeLifecycle.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/windowDiscovery.js" "Should deploy windowDiscovery.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "Should deploy metadata.json"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/stylesheet.css" "Should deploy stylesheet.css"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "\"uuid\": \"$EXTENSION_UUID\"" "metadata.json should carry the right uuid"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "configurable badge" "metadata should describe configurable badge behavior"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/badgeLifecycle.js" "wwc-badge" "badgeLifecycle.js should reference the badge style class"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/badgeLifecycle.js" "export function resolveBadgePosition" "Installed badge lifecycle should include vertical-panel positioning"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "resolveBadgePosition(this._config.position, delegate)" "Installed extension should resolve badge position per panel"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/prefs.js" "Should deploy prefs.js settings UI"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/schemas/org.gnome.shell.extensions.workspace-window-count.gschema.xml" "Should deploy the GSettings schema"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/schemas/gschemas.compiled" "Should compile the GSettings schema"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "settings-schema" "metadata.json should declare its settings-schema"
assert_file_exists "$REPO_ROOT/.log/install.log" "Installer should write a centralized Bash log"
assert_file_contains "$REPO_ROOT/.log/install.log" "Deploying workspace-window-count@local GNOME Shell extension" "Installer log should include deployment state"
assert_file_contains "$REPO_ROOT/.log/install.log" "ENTER install_window_count_extension" "Installer log should trace top-level install function"
if grep -Fq 'wwc_bin "$value"' "$REPO_ROOT/lib/window_count_setup.sh" \
  && ! grep -Fq "python3" "$REPO_ROOT/lib/window_count_setup.sh" \
  && ! grep -Fq "gsettings_strv.py" "$REPO_ROOT/lib/window_count_setup.sh"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: installer should use the wwc-tools Rust helper (no Python)"
fi
# Default (no-arg, no TTY) run installs all default-on components, each writing
# its key on the extension schema.
for KEY in badge-position count-threshold count-all-workspaces badge-text-color badge-background-color badge-font-size; do
  assert_file_contains "$SET_LOG" "org.gnome.shell.extensions.workspace-window-count	$KEY" "Default install should set $KEY"
done
assert_file_contains "$SET_LOG" "badge-position	'bottom-right'" "Default badge-position should preserve bottom-right"
assert_file_contains "$SET_LOG" "count-threshold	2" "Default count-threshold should preserve 2"
assert_file_contains "$SET_LOG" $'badge-font-size\t18' "Default install should apply the larger 18px badge"
INSTALLED_SCHEMA_DIR="$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/schemas"
assert_eq "18" "$(GSETTINGS_BACKEND=memory gsettings --schemadir "$INSTALLED_SCHEMA_DIR" get org.gnome.shell.extensions.workspace-window-count badge-font-size)" "Compiled schema should default to 18px even without the appearance component"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/stylesheet.css" "font-size: 18px;" "Installed stylesheet should use the larger default size"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "fontSize: 18" "Missing-schema fallback should use the larger default size"
case "$(cat "$STATE_FILE")" in
  *"$EXTENSION_UUID"*) PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: Should enable extension via enabled-extensions (got '$(cat "$STATE_FILE")')";;
esac
case "$(cat "$STATE_FILE")" in
  *"app-rules@local"*) PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: Should preserve already-enabled extensions (got '$(cat "$STATE_FILE")')";;
esac

PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" >"$TMP_DIR/install-2.out" 2>"$TMP_DIR/install-2.err" || FAIL=$((FAIL + 1))
WWC_OCCURRENCES="$(printf '%s' "$(cat "$STATE_FILE")" | grep -o "$EXTENSION_UUID" | wc -l | tr -d ' ')"
assert_eq "1" "$WWC_OCCURRENCES" "Re-running should not duplicate the enabled entry"

GSETTINGS_FAIL_SET=1 PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" >"$TMP_DIR/install-gsettings-fail.out" 2>"$TMP_DIR/install-gsettings-fail.err" || FAIL=$((FAIL + 1))
assert_file_contains "$TMP_DIR/install-gsettings-fail.out" "WARN: Could not update GNOME enabled-extensions" "GSettings enable failure should be visible without aborting install"

# A failed read must preserve the entire enabled list, even when writes work.
printf "['app-rules@local', 'another-extension@local']\n" >"$STATE_FILE"
: >"$SET_LOG"
GSETTINGS_FAIL_GET=1 PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 \
  bash "$REPO_ROOT/install.sh" --select "" >"$TMP_DIR/install-read-fail.out" \
  2>"$TMP_DIR/install-read-fail.err" || FAIL=$((FAIL + 1))
assert_eq "['app-rules@local', 'another-extension@local']" "$(cat "$STATE_FILE")" \
  "Failed enabled-extension reads must preserve the existing list"
if grep -Fq $'org.gnome.shell\tenabled-extensions\t' "$SET_LOG"; then
  FAIL=$((FAIL + 1)); echo "FAIL: a failed settings read must never write enabled-extensions"
else
  PASS=$((PASS + 1))
fi
assert_file_contains "$TMP_DIR/install-read-fail.out" "WARN: Could not update GNOME enabled-extensions" \
  "A skipped enable after a failed read should remain visible"

# --list-components must be side-effect free (the master installer parses it):
# it should print the component manifest and deploy nothing into a fresh home.
LIST_HOME="$TMP_DIR/list-home"
cat >"$BIN_DIR/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "$TEST_TARGET_USER" ]]; then
  printf '%s\n' "$LIST_HOME"
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF
chmod +x "$BIN_DIR/getent"
PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" --list-components >"$TMP_DIR/list.out" 2>/dev/null || FAIL=$((FAIL + 1))
for ID in badge_position count_threshold workspace_scope badge_appearance; do
  assert_file_contains "$TMP_DIR/list.out" "$ID" "--list-components should list $ID"
done
if [ -e "$LIST_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID" ]; then
  FAIL=$((FAIL + 1)); echo "FAIL: --list-components should not deploy the extension"
else
  PASS=$((PASS + 1))
fi

# --select runs the core deploy plus only the named component(s); unselected
# component keys must not be written. Honors per-component env overrides.
SELECT_HOME="$TMP_DIR/select-home"
cat >"$BIN_DIR/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "$TEST_TARGET_USER" ]]; then
  printf '%s\n' "$SELECT_HOME"
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF
chmod +x "$BIN_DIR/getent"
: >"$SET_LOG"
WWC_COUNT_THRESHOLD=5 PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" --select count_threshold >"$TMP_DIR/select.out" 2>/dev/null || FAIL=$((FAIL + 1))
assert_file_exists "$SELECT_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "--select should still run the unconditional core deploy"
assert_file_contains "$SET_LOG" "count-threshold	5" "--select count_threshold with WWC_COUNT_THRESHOLD=5 should write 5"
if grep -Fq "	badge-position	" "$SET_LOG"; then
  FAIL=$((FAIL + 1)); echo "FAIL: --select count_threshold should not write badge-position"
else
  PASS=$((PASS + 1))
fi

# An empty component selection still deploys the extension core, without
# changing any of its existing GSettings values.
CORE_HOME="$TMP_DIR/core-only-home"
cat >"$BIN_DIR/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "$TEST_TARGET_USER" ]]; then
  printf '%s\n' "$CORE_HOME"
  exit 0
fi
exec /usr/bin/getent "$@"
EOF
chmod +x "$BIN_DIR/getent"
: >"$SET_LOG"
if ! PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 bash "$REPO_ROOT/install.sh" --select "" >"$TMP_DIR/core-only.out" 2>"$TMP_DIR/core-only.err"; then
  FAIL=$((FAIL + 1))
  cat "$TMP_DIR/core-only.out" "$TMP_DIR/core-only.err" >&2
fi
assert_file_exists "$CORE_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "An empty component selection should still deploy the extension core"
if grep -Fq "org.gnome.shell.extensions.workspace-window-count" "$SET_LOG"; then
  FAIL=$((FAIL + 1)); echo "FAIL: core-only deployment should preserve existing extension settings"
else
  PASS=$((PASS + 1))
fi

# --- Knob lifecycle: receipts, not schema presence, decide installed state ----
# The extension core always deploys the schema, so a schema-presence detector
# reported every knob as installed and made non-interactive runs skip them all.
# State must come from the install receipt instead: absent before the first run,
# installed after it, absent again after --uninstall.
LIFECYCLE_HOME="$TMP_DIR/lifecycle-home"
mkdir -p "$LIFECYCLE_HOME"
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ "${1:-}" == "passwd" && "${2:-}" == "$TEST_TARGET_USER" ]]; then\n'
  printf '  printf "%%s\\n" "%s"\n' "$LIFECYCLE_HOME"
  printf '  exit 0\n'
  printf 'fi\n'
  printf 'exec /usr/bin/getent "$@"\n'
} >"$BIN_DIR/getent"
chmod +x "$BIN_DIR/getent"

run_lifecycle() {
  PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" DISPLAY=:99 HOME="$LIFECYCLE_HOME" \
    ISC_FUNCTIONS_DIR= GIT_CALL_LOG="$TMP_DIR/lifecycle-git.log" \
    XDG_STATE_HOME="$LIFECYCLE_HOME/.local/state" \
    bash "$REPO_ROOT/install.sh" "$@"
}

# The standalone config exporter must remain side-effect free.
: >"$SET_LOG"
if ! run_lifecycle --export-selection >"$TMP_DIR/export-selection.json" 2>"$TMP_DIR/export-selection.err"; then
  FAIL=$((FAIL + 1))
  cat "$TMP_DIR/export-selection.err" >&2
else
  if python3 - "$TMP_DIR/export-selection.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert document["scope"] == "standalone"
assert set(document["components"]) == {
    "badge_position",
    "badge_appearance",
    "count_threshold",
    "workspace_scope",
}
PY
  then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: --export-selection should return valid standalone component JSON"
    cat "$TMP_DIR/export-selection.json" >&2
  fi
fi
if [ -s "$SET_LOG" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: --export-selection must not write desktop settings"
else
  PASS=$((PASS + 1))
fi

if ! run_lifecycle --config empty --export-selection >"$TMP_DIR/export-empty.json" 2>"$TMP_DIR/export-empty.err"; then
  FAIL=$((FAIL + 1))
  cat "$TMP_DIR/export-empty.err" >&2
elif python3 - "$TMP_DIR/export-empty.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
assert set(document["components"]) == {
    "badge_position",
    "badge_appearance",
    "count_threshold",
    "workspace_scope",
}
assert all(values["on"] == 0 for values in document["components"].values())
PY
then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: --config empty --export-selection should return an empty selection"
  cat "$TMP_DIR/export-empty.json" >&2
fi

: >"$SET_LOG"
if ! run_lifecycle --config empty >"$TMP_DIR/install-empty.out" 2>"$TMP_DIR/install-empty.err"; then
  FAIL=$((FAIL + 1))
  cat "$TMP_DIR/install-empty.out" "$TMP_DIR/install-empty.err" >&2
elif grep -Fq "org.gnome.shell.extensions.workspace-window-count" "$SET_LOG"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: --config empty should deploy the core without applying component settings"
else
  PASS=$((PASS + 1))
fi

if ! run_lifecycle --help >"$TMP_DIR/help.out" 2>"$TMP_DIR/help.err"; then
  FAIL=$((FAIL + 1))
  cat "$TMP_DIR/help.err" >&2
else
  assert_file_contains "$TMP_DIR/help.out" "--reconfigure a,b,c" "--help should document reconfiguration"
  assert_file_contains "$TMP_DIR/help.out" "--export-selection" "--help should document selection export"
fi
for OPTION in --list-configurable-components --list-select-configure-components --list-component-config-values; do
  if ! run_lifecycle "$OPTION" >"$TMP_DIR/${OPTION#--}.out" 2>"$TMP_DIR/${OPTION#--}.err"; then
    FAIL=$((FAIL + 1))
    cat "$TMP_DIR/${OPTION#--}.err" >&2
  elif [ -s "$TMP_DIR/${OPTION#--}.out" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $OPTION should be empty because no component has a nested config screen"
  else
    PASS=$((PASS + 1))
  fi
done
if run_lifecycle --configure-component badge_position >"$TMP_DIR/configure.out" 2>"$TMP_DIR/configure.err"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: --configure-component should report that no nested screen is defined"
else
  CONFIGURE_STATUS=$?
  assert_eq "2" "$CONFIGURE_STATUS" "--configure-component should return usage status when no screen exists"
fi
if run_lifecycle --select component_does_not_exist >"$TMP_DIR/invalid-selection.out" 2>"$TMP_DIR/invalid-selection.err"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: --select should reject an unknown component ID"
else
  SELECTION_STATUS=$?
  assert_eq "2" "$SELECTION_STATUS" "--select should return usage status for an unknown component ID"
fi

if command -v script >/dev/null 2>&1; then
  : >"$SET_LOG"
  if ! printf '\n\n' | env PATH="$BIN_DIR:$PATH" SUDO_USER="$TEST_TARGET_USER" \
    DISPLAY=:99 HOME="$LIFECYCLE_HOME" XDG_STATE_HOME="$TMP_DIR/interactive-state" \
    ISC_FUNCTIONS_DIR= GIT_CALL_LOG="$TMP_DIR/lifecycle-git.log" \
    script -q -e -c "bash \"$REPO_ROOT/install.sh\"" /dev/null \
    >"$TMP_DIR/interactive.out" 2>"$TMP_DIR/interactive.err"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: interactive install should accept the default component selection"
    cat "$TMP_DIR/interactive.out" "$TMP_DIR/interactive.err" >&2
  else
    PASS=$((PASS + 1))
  fi
  assert_file_contains "$SET_LOG" "badge-position" "Interactive default selection should apply badge position"
  assert_file_contains "$SET_LOG" "count-threshold" "Interactive default selection should apply count threshold"
fi

run_lifecycle --detect >"$TMP_DIR/detect-before.out" 2>/dev/null || FAIL=$((FAIL + 1))
if grep -Eq '^badge_position[[:space:]]+installed' "$TMP_DIR/detect-before.out"; then
  FAIL=$((FAIL + 1)); echo "FAIL: a knob must not report installed before any run"
else
  PASS=$((PASS + 1))
fi

run_lifecycle --default >"$TMP_DIR/lifecycle-install.out" 2>/dev/null || FAIL=$((FAIL + 1))
: >"$SET_LOG"
WWC_COUNT_THRESHOLD=4 run_lifecycle --reconfigure count_threshold >"$TMP_DIR/reconfigure.out" 2>/dev/null || FAIL=$((FAIL + 1))
assert_file_contains "$SET_LOG" $'count-threshold\t4' "--reconfigure should reapply the selected component settings"
: >"$SET_LOG"
WWC_BADGE_FONT_SIZE=24 run_lifecycle --reconfigure badge_appearance >"$TMP_DIR/reconfigure-appearance.out" 2>/dev/null || FAIL=$((FAIL + 1))
assert_file_contains "$SET_LOG" $'badge-font-size\t24' "Reconfiguration should preserve the requested custom font size"
run_lifecycle --detect >"$TMP_DIR/detect-after.out" 2>/dev/null || FAIL=$((FAIL + 1))
if grep -Eq '^badge_position[[:space:]]+installed' "$TMP_DIR/detect-after.out"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1)); echo "FAIL: knob should report installed after --default"
fi

run_lifecycle --uninstall badge_position >"$TMP_DIR/lifecycle-uninstall.out" 2>/dev/null || FAIL=$((FAIL + 1))
run_lifecycle --detect >"$TMP_DIR/detect-removed.out" 2>/dev/null || FAIL=$((FAIL + 1))
if grep -Eq '^badge_position[[:space:]]+installed' "$TMP_DIR/detect-removed.out"; then
  FAIL=$((FAIL + 1)); echo "FAIL: knob should report absent after --uninstall"
else
  PASS=$((PASS + 1))
fi
if grep -Eq '^count_threshold[[:space:]]+installed' "$TMP_DIR/detect-removed.out"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1)); echo "FAIL: uninstalling one knob must not drop the others"
fi
if [ -e "$TMP_DIR/lifecycle-git.log" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: component lifecycle commands must not fetch the private shared framework"
else
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
