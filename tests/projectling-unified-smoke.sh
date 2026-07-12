#!/usr/bin/env bash
set -euo pipefail

PUBLIC_ROOT="${1:-}"
if [[ -z "$PUBLIC_ROOT" || ! -f "$PUBLIC_ROOT/run.sh" || ! -f "$PUBLIC_ROOT/app/run.sh" ]]; then
  printf 'usage: %s /path/to/ProjectLing-public-root\n' "$0" >&2
  exit 2
fi

bash -n "$PUBLIC_ROOT/run.sh"
zsh -n "$PUBLIC_ROOT/projectling.zsh"
bash -n "$PUBLIC_ROOT/app/run.sh"
zsh -n "$PUBLIC_ROOT/app/projectling.zsh"

migration_root="$(mktemp -d)"
selftest_root="$(mktemp -d)"
cleanup() {
  rm -rf "$migration_root" "$selftest_root"
}
trap cleanup EXIT

cp -a "$PUBLIC_ROOT/." "$migration_root/"
mkdir -p "$migration_root/config" "$migration_root/context" "$migration_root/memory"
printf 'PROJECTLING_TEST_MARKER=unified\n' >"$migration_root/config/env"
printf 'legacy-context\n' >"$migration_root/context/shared_context.txt"
printf '{"legacy":true}\n' >"$migration_root/memory/datememory.json"
chmod +x "$migration_root/run.sh" "$migration_root/app/run.sh"
bash "$migration_root/run.sh" --compat-migrate-only

grep -q 'PROJECTLING_TEST_MARKER=unified' "$migration_root/app/config/env"
grep -q 'legacy-context' "$migration_root/app/context/shared_context.txt"
test -f "$migration_root/app/memory/datememory.json"

cp -a "$PUBLIC_ROOT/." "$selftest_root/"
chmod +x "$selftest_root/run.sh" "$selftest_root/app/run.sh"
bash "$selftest_root/run.sh" selftest

printf 'projectling_unified_smoke=ok\n'
