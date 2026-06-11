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
if [[ "${1:-}" == "get" && "${2:-}" == "org.gnome.shell" && "${3:-}" == "enabled-extensions" ]]; then
  cat "__STATE_FILE__"
  exit 0
fi
if [[ "${1:-}" == "set" && "${2:-}" == "org.gnome.shell" && "${3:-}" == "enabled-extensions" ]]; then
  printf '%s\n' "$4" > "__STATE_FILE__"
  exit 0
fi
exit 0
EOF
sed -i "s#__STATE_FILE__#$STATE_FILE#g" "$BIN_DIR/gsettings"
chmod +x "$BIN_DIR/getent" "$BIN_DIR/sudo" "$BIN_DIR/gsettings"
printf "['app-rules@local']\n" >"$STATE_FILE"

PATH="$BIN_DIR:$PATH" SUDO_USER=mk DISPLAY=:99 bash "$REPO_ROOT/install.sh" >/tmp/linux-taskbar-window-count-install-1.out 2>/tmp/linux-taskbar-window-count-install-1.err || FAIL=$((FAIL + 1))

assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "Should deploy extension.js"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "Should deploy metadata.json"
assert_file_exists "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/stylesheet.css" "Should deploy stylesheet.css"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/metadata.json" "\"uuid\": \"$EXTENSION_UUID\"" "metadata.json should carry the right uuid"
assert_file_contains "$TARGET_HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID/extension.js" "wwc-badge" "extension.js should reference the badge style class"
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
rm -rf "$TMP_DIR"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
