#!/usr/bin/env bash
# Test Linux Taskbar Window Count installer behavior without sudo or shell side effects.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/linux-taskbar-window-count-test.XXXXXX)"
BIN_DIR="$TMP_DIR/bin"
STATE_FILE="$TMP_DIR/gsettings-state"
TARGET_HOME="$TMP_DIR/home"
EXTENSION_UUID="workspace-window-count@local"
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
  if grep -Fq "$needle" "$path"; then
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

mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "passwd" && "${2:-}" == "mk" ]]; then
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
chmod +x "$BIN_DIR/getent" "$BIN_DIR/sudo" "$BIN_DIR/gsettings"
printf "['app-rules@local']\n" >"$STATE_FILE"

PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" >/tmp/linux-taskbar-window-count-install-1.out 2>/tmp/linux-taskbar-window-count-install-1.err || FAIL=$((FAIL + 1))

assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "Should deploy extension.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/badgeLifecycle.js" "Should deploy badgeLifecycle.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/windowDiscovery.js" "Should deploy windowDiscovery.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "Should deploy metadata.json"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/stylesheet.css" "Should deploy stylesheet.css"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "\"uuid\": \"$EXTENSION_UUID\"" "metadata.json should carry the right uuid"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/badgeLifecycle.js" "wwc-badge" "badgeLifecycle.js should reference the badge style class"
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
case "$(cat "$STATE_FILE")" in
  *"$EXTENSION_UUID"*) PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: Should enable extension via enabled-extensions (got '$(cat "$STATE_FILE")')";;
esac
case "$(cat "$STATE_FILE")" in
  *"app-rules@local"*) PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: Should preserve already-enabled extensions (got '$(cat "$STATE_FILE")')";;
esac

PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" >/tmp/linux-taskbar-window-count-install-2.out 2>/tmp/linux-taskbar-window-count-install-2.err || FAIL=$((FAIL + 1))
WWC_OCCURRENCES="$(printf '%s' "$(cat "$STATE_FILE")" | grep -o "$EXTENSION_UUID" | wc -l | tr -d ' ')"
assert_eq "1" "$WWC_OCCURRENCES" "Re-running should not duplicate the enabled entry"

GSETTINGS_FAIL_SET=1 PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" >/tmp/linux-taskbar-window-count-install-gsettings-fail.out 2>/tmp/linux-taskbar-window-count-install-gsettings-fail.err || FAIL=$((FAIL + 1))
assert_file_contains /tmp/linux-taskbar-window-count-install-gsettings-fail.out "WARN: Could not update GNOME enabled-extensions" "GSettings enable failure should be visible without aborting install"

# --list-components must be side-effect free (the master installer parses it):
# it should print the component manifest and deploy nothing into a fresh home.
LIST_HOME="$TMP_DIR/list-home"
cat >"$BIN_DIR/getent" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "mk" ]]; then
  printf '%s\n' "$LIST_HOME"
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF
chmod +x "$BIN_DIR/getent"
PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" --list-components >"$TMP_DIR/list.out" 2>/dev/null || FAIL=$((FAIL + 1))
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
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "mk" ]]; then
  printf '%s\n' "$SELECT_HOME"
  exit 0
fi
exec /usr/bin/getent "\$@"
EOF
chmod +x "$BIN_DIR/getent"
: >"$SET_LOG"
WWC_COUNT_THRESHOLD=5 PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" --select count_threshold >"$TMP_DIR/select.out" 2>/dev/null || FAIL=$((FAIL + 1))
assert_file_exists "$SELECT_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "--select should still run the unconditional core deploy"
assert_file_contains "$SET_LOG" "count-threshold	5" "--select count_threshold with WWC_COUNT_THRESHOLD=5 should write 5"
if grep -Fq "	badge-position	" "$SET_LOG"; then
  FAIL=$((FAIL + 1)); echo "FAIL: --select count_threshold should not write badge-position"
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
  printf 'if [[ "${1:-}" == "passwd" && "${2:-}" == "mk" ]]; then\n'
  printf '  printf "%%s\\n" "%s"\n' "$LIFECYCLE_HOME"
  printf '  exit 0\n'
  printf 'fi\n'
  printf 'exec /usr/bin/getent "$@"\n'
} >"$BIN_DIR/getent"
chmod +x "$BIN_DIR/getent"

# The sandbox HOME hides install.sh's ~/projects fallback for the shared
# framework, and the sibling checkout only exists next to the live checkout (not
# next to a git worktree), so resolve it here instead of letting the loader
# reach the network.
for candidate in "${ISC_FUNCTIONS_DIR:-}" \
                 "$REPO_ROOT/../linux_installation_scripts_functions" \
                 "$REPO_ROOT/../../linux_installation_scripts_functions" \
                 "$HOME/projects/linux_installation_scripts_functions"; do
  [ -n "$candidate" ] || continue
  if [ -f "$candidate/component_loader.sh" ]; then
    LIFECYCLE_ISC_DIR="$(cd "$candidate" && pwd)"
    break
  fi
done

run_lifecycle() {
  PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 HOME="$LIFECYCLE_HOME" \
    ISC_FUNCTIONS_DIR="${LIFECYCLE_ISC_DIR:-}" \
    XDG_STATE_HOME="$LIFECYCLE_HOME/.local/state" \
    bash "$REPO_ROOT/install.sh" "$@"
}

run_lifecycle --detect >"$TMP_DIR/detect-before.out" 2>/dev/null || FAIL=$((FAIL + 1))
if grep -Eq '^badge_position[[:space:]]+installed' "$TMP_DIR/detect-before.out"; then
  FAIL=$((FAIL + 1)); echo "FAIL: a knob must not report installed before any run"
else
  PASS=$((PASS + 1))
fi

run_lifecycle --default >"$TMP_DIR/lifecycle-install.out" 2>/dev/null || FAIL=$((FAIL + 1))
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
rm -rf "$TMP_DIR"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
