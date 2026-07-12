#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$SCRIPT_ROOT/bin/aitermux-bootstrap"
CANONICAL_REPO="${PROJECTLING_CANONICAL_REPO:-https://github.com/jiangshanyao2200-hue/ProjectLing.git}"
LEGACY_REPO="${PROJECTLING_LEGACY_REPO:-https://github.com/jiangshanyao2200-hue/projectling-termux.git}"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

new_home="$TEST_ROOT/new/AItermux"
AITERMUX_HOME="$new_home" \
AITERMUX_AIDEBUG_DIR="$new_home/projectling/aidebug" \
AITERMUX_PROJECTLING_REPO="$CANONICAL_REPO" \
  bash "$BOOTSTRAP" --force --component projectling

test -x "$new_home/projectling/run.sh"
test -f "$new_home/projectling/projectling.zsh"
test -f "$new_home/projectling/app/core.py"
test "$(git -C "$new_home/projectling" remote get-url origin)" = "$CANONICAL_REPO"
bash "$new_home/projectling/run.sh" --compat-migrate-only

legacy_home="$TEST_ROOT/legacy/AItermux"
mkdir -p "$legacy_home/projectling"
git -C "$legacy_home/projectling" init -b main >/dev/null
git -C "$legacy_home/projectling" config user.name 'PROJECTling migration test'
git -C "$legacy_home/projectling" config user.email 'projectling-migration-test@example.invalid'
printf 'legacy fixture\n' >"$legacy_home/projectling/legacy-version.txt"
printf '#!/usr/bin/env bash\nexit 0\n' >"$legacy_home/projectling/run.sh"
chmod +x "$legacy_home/projectling/run.sh"
printf 'config/\ncontext/\nmemory/\naidebug/\n' >"$legacy_home/projectling/.gitignore"
git -C "$legacy_home/projectling" add .gitignore legacy-version.txt run.sh
git -C "$legacy_home/projectling" commit -m 'Create legacy fixture' >/dev/null
git -C "$legacy_home/projectling" remote add origin "$LEGACY_REPO"
mkdir -p \
  "$legacy_home/projectling/config" \
  "$legacy_home/projectling/context" \
  "$legacy_home/projectling/memory" \
  "$legacy_home/projectling/aidebug/logs"
printf 'PROJECTLING_TEST_MARKER=legacy-migrated\n' >"$legacy_home/projectling/config/env"
printf 'legacy-context\n' >"$legacy_home/projectling/context/shared_context.txt"
printf '{"legacy":true}\n' >"$legacy_home/projectling/memory/datememory.json"
printf 'legacy-aidebug\n' >"$legacy_home/projectling/aidebug/logs/legacy-smoke.log"

AITERMUX_HOME="$legacy_home" \
AITERMUX_AIDEBUG_DIR="$legacy_home/projectling/aidebug" \
AITERMUX_PROJECTLING_REPO="$CANONICAL_REPO" \
  bash "$BOOTSTRAP" --force --update --component projectling

test "$(git -C "$legacy_home/projectling" remote get-url origin)" = "$CANONICAL_REPO"
test -x "$legacy_home/projectling/run.sh"
test -f "$legacy_home/projectling/app/core.py"
test -f "$legacy_home/projectling/config/env"
test -f "$legacy_home/projectling/context/shared_context.txt"
test -f "$legacy_home/projectling/memory/datememory.json"
test -f "$legacy_home/projectling/aidebug/logs/legacy-smoke.log"
bash "$legacy_home/projectling/run.sh" --compat-migrate-only
grep -q 'PROJECTLING_TEST_MARKER=legacy-migrated' "$legacy_home/projectling/app/config/env"
grep -q 'legacy-context' "$legacy_home/projectling/app/context/shared_context.txt"
test -f "$legacy_home/projectling/app/memory/datememory.json"
grep -q '^status=ok$' "$legacy_home/.state/bootstrap/projectling.state"
grep -q '^reason=migrated-unified-repo$' "$legacy_home/.state/bootstrap/projectling.state"

printf 'projectling_live_new_install=ok\n'
printf 'projectling_live_legacy_migration=ok\n'
