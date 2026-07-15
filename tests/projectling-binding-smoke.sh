#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
MOTD="$ROOT/Quickinstall/deploy/termux/motd.sh"
CLI="$ROOT/bin/aitermux-cli-install"
CLI_DEPLOY="$ROOT/Quickinstall/deploy/aitermux/bin/aitermux-cli-install"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

bash -n "$MOTD" "$CLI" "$CLI_DEPLOY"
cmp -s "$CLI" "$CLI_DEPLOY"

grep -q '^motd_projectling_card_state_key()' "$MOTD"
grep -q '^motd_invalidate_projectling_card()' "$MOTD"
grep -q 'config/persona_links.json' "$MOTD"
grep -q 'motd_invalidate_projectling_card' "$MOTD"
grep -q 'update-projectling)' "$CLI"

eval "$(sed -n '/^motd_invalidate_projectling_card()/,/^}/p' "$MOTD")"
eval "$(sed -n '/^motd_projectling_card_state_key()/,/^}/p' "$MOTD")"
ROOT_DIR="$TEST_ROOT/state-home"
mkdir -p "$ROOT_DIR/projectling/config"
printf 'core-v1\n' >"$ROOT_DIR/projectling/core.py"
printf 'runtime-v1\n' >"$ROOT_DIR/projectling/run.sh"
printf 'PROJECTLING_COLLAB_MODE=standard\n' >"$ROOT_DIR/projectling/config/env"
state_key_before="$(motd_projectling_card_state_key)"
printf 'PROJECTLING_COLLAB_MODE=precise\n' >"$ROOT_DIR/projectling/config/env"
state_key_after="$(motd_projectling_card_state_key)"
test -n "$state_key_before"
test "$state_key_before" != "$state_key_after"

MOTD_LAUNCHER_CARD_SEED='seed'
MOTD_CARD_CACHE_KEY='cached'
MOTD_CARD_CACHE_LINES=('cached-line')
motd_invalidate_projectling_card
test -z "$MOTD_LAUNCHER_CARD_SEED"
test -z "$MOTD_CARD_CACHE_KEY"
test "${#MOTD_CARD_CACHE_LINES[@]}" -eq 0

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/aitermux-bootstrap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$AITERMUX_BINDING_CAPTURE"
EOF
chmod +x "$TEST_ROOT/bin/aitermux-bootstrap"

output="$({
  AITERMUX_HOME="$TEST_ROOT" \
  AITERMUX_BINDING_CAPTURE="$TEST_ROOT/argv.txt" \
    bash "$CLI" update-projectling
} 2>&1)"

grep -qx -- '--force --update --component projectling' "$TEST_ROOT/argv.txt"
grep -q 'projectling_reload' <<<"$output"

printf 'projectling_binding_smoke=ok\n'
