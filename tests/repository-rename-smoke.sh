#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$SCRIPT_ROOT/bin/aitermux-bootstrap"
TEST_ROOT="$(mktemp -d)"
AITERMUX_HOME="$TEST_ROOT/AItermux"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

git clone -q https://github.com/jiangshanyao2200-hue/AITermux-Step2.git "$AITERMUX_HOME"
git -C "$AITERMUX_HOME" remote set-url origin \
  https://github.com/jiangshanyao2200-hue/longgu-termux-kit-step2.git

git clone -q https://github.com/jiangshanyao2200-hue/ProjectLing.git \
  "$AITERMUX_HOME/projectling"
git -C "$AITERMUX_HOME/projectling" remote set-url origin \
  https://github.com/jiangshanyao2200-hue/PROJECTling.git

git clone -q https://github.com/jiangshanyao2200-hue/ProjectYing.git \
  "$AITERMUX_HOME/projectying"
git -C "$AITERMUX_HOME/projectying" remote set-url origin \
  https://github.com/jiangshanyao2200-hue/projectying-termux.git

for component in aitermux projectling projectying; do
  AITERMUX_HOME="$AITERMUX_HOME" \
  AITERMUX_AIDEBUG_DIR="$AITERMUX_HOME/projectling/aidebug" \
    bash "$BOOTSTRAP" --force --update --component "$component"
done

test "$(git -C "$AITERMUX_HOME" remote get-url origin)" = \
  'https://github.com/jiangshanyao2200-hue/AITermux-Step2.git'
test "$(git -C "$AITERMUX_HOME/projectling" remote get-url origin)" = \
  'https://github.com/jiangshanyao2200-hue/ProjectLing.git'
test "$(git -C "$AITERMUX_HOME/projectying" remote get-url origin)" = \
  'https://github.com/jiangshanyao2200-hue/ProjectYing.git'

printf 'repository_rename_migration=ok\n'
