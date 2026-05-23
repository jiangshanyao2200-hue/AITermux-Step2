#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail

AITERMUX_HOME="${AITERMUX_HOME:-$HOME/AItermux}"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
AITERMUX_REPO="${AITERMUX_REPO:-https://github.com/jiangshanyao2200-hue/longgu-termux-kit-step2.git}"
PROJECTYING_DIR="$AITERMUX_HOME/projectying"
PROJECTLING_DIR="$AITERMUX_HOME/projectling"
PROJECTYING_REPO="${AITERMUX_PROJECTYING_REPO:-https://github.com/jiangshanyao2200-hue/projectying-termux.git}"
PROJECTLING_REPO="${AITERMUX_PROJECTLING_REPO:-https://github.com/jiangshanyao2200-hue/projectling-termux.git}"
STATE_DIR="$AITERMUX_HOME/.state/bootstrap"
AIDEBUG_DIR="${AITERMUX_AIDEBUG_DIR:-$AITERMUX_HOME/projectling/aidebug}"
LOG_DIR="$AIDEBUG_DIR/logs"
STARTUP_LOG="$LOG_DIR/startup.log"
BOOTSTRAP_LOG="$LOG_DIR/bootstrap.log"
RETRY_SECS="${AITERMUX_BOOTSTRAP_RETRY_SECS:-600}"
QUIET=0
FORCE=0
UPDATE=0

declare -a COMPONENTS=()

usage() {
  cat <<'EOF'
AITermux bootstrap

用法：
  aitermux-bootstrap [--quiet] [--force] [--update] [--component aitermux|projectying|projectling|codex|gemini|claude]

说明：
  默认会检查并补装 projectying、projectling、codex、gemini、claude。
  projectying/projectling 默认从公开 Termux 仓库 clone；可用 AITERMUX_PROJECTYING_REPO / AITERMUX_PROJECTLING_REPO 覆盖。
  --update 对 aitermux/projectying/projectling 生效：检查远端 main 是否有新提交，有就 fast-forward 拉取源码。
  失败会写入 ~/AItermux/projectling/aidebug/logs/startup.log，并做短暂退避，避免每次登录都重复阻塞。
EOF
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%F %T' 2>/dev/null || echo unknown
}

shrink_log_tail_if_over_kb() {
  local path="$1"
  local max_kb="${2:-512}"
  local keep_kb="${3:-256}"
  [[ -f "$path" ]] || return 0
  [[ "$max_kb" =~ ^[0-9]+$ ]] || return 0
  [[ "$keep_kb" =~ ^[0-9]+$ ]] || return 0
  (( max_kb > 0 && keep_kb > 0 )) || return 0
  local max_bytes=$((max_kb * 1024))
  local keep_bytes=$((keep_kb * 1024))
  local size_bytes tmp
  size_bytes="$(wc -c <"$path" 2>/dev/null || true)"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || return 0
  (( size_bytes > max_bytes )) || return 0
  (( keep_bytes <= max_bytes )) || keep_bytes="$max_bytes"
  mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
  tmp="$LOG_DIR/.trim.$$.$RANDOM"
  if tail -c "$keep_bytes" "$path" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

log() {
  local msg="$*"
  mkdir -p "$LOG_DIR" "$STATE_DIR" >/dev/null 2>&1 || true
  shrink_log_tail_if_over_kb "$STARTUP_LOG" "${AITERMUX_STARTUP_LOG_MAX_KB:-1024}" "${AITERMUX_STARTUP_LOG_KEEP_KB:-512}" || true
  shrink_log_tail_if_over_kb "$BOOTSTRAP_LOG" "${AITERMUX_COMPONENT_LOG_MAX_KB:-512}" "${AITERMUX_COMPONENT_LOG_KEEP_KB:-256}" || true
  local line
  line="$(printf '%s bootstrap %s\n' "$(timestamp_utc)" "$msg")"
  printf '%s\n' "$line" >>"$STARTUP_LOG" 2>/dev/null || true
  printf '%s\n' "$line" >>"$BOOTSTRAP_LOG" 2>/dev/null || true
  if (( QUIET == 0 )); then
    printf '[aitermux-bootstrap] %s\n' "$msg" >&2
  fi
}

state_file_for() {
  printf '%s/%s.state\n' "$STATE_DIR" "$1"
}

state_get() {
  local file="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n 1
}

state_set() {
  local component="$1"
  local status="$2"
  local reason="${3:-}"
  local file tmp

  mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
  file="$(state_file_for "$component")"
  tmp="${file}.tmp.$$.$RANDOM"
  {
    printf 'status=%s\n' "$status"
    printf 'ts=%s\n' "$(date +%s 2>/dev/null || echo 0)"
    printf 'updated_at=%s\n' "$(timestamp_utc)"
    printf 'reason=%s\n' "$reason"
  } >"$tmp"
  mv -f "$tmp" "$file"
}

skip_due_to_backoff() {
  local component="$1"
  local file status ts now

  (( FORCE == 0 )) || return 1
  [[ "$RETRY_SECS" =~ ^[0-9]+$ ]] || return 1
  (( RETRY_SECS > 0 )) || return 1

  file="$(state_file_for "$component")"
  [[ -f "$file" ]] || return 1

  status="$(state_get "$file" status)"
  ts="$(state_get "$file" ts)"
  now="$(date +%s 2>/dev/null || echo 0)"

  [[ "$status" == "fail" ]] || return 1
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  (( now > ts )) || return 1

  if (( now - ts < RETRY_SECS )); then
    log "skip component=${component} reason=recent-failure retry_after=${RETRY_SECS}s"
    return 0
  fi

  return 1
}

append_line_if_missing() {
  local file="$1"
  local line="$2"

  mkdir -p "$(dirname "$file")" >/dev/null 2>&1 || true
  touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

write_file_atomically() {
  local target="$1"
  local mode="$2"
  local tmp

  if [ -L "$target" ]; then
    target="$(readlink "$target" 2>/dev/null || printf '%s' "$target")"
  fi
  mkdir -p "$(dirname "$target")" >/dev/null 2>&1 || true
  tmp="${target}.tmp.$$.$RANDOM"
  cat >"$tmp"
  chmod "$mode" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target"
}

ensure_pkg() {
  local cmd_name="$1"
  local pkg_name="$2"

  if command -v "$cmd_name" >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v pkg >/dev/null 2>&1; then
    log "missing pkg while installing package=${pkg_name}"
    return 1
  fi

  log "pkg install package=${pkg_name}"
  pkg install -y "$pkg_name"
}

ensure_node_stack() {
  ensure_pkg node nodejs-lts || return 1
  command -v npm >/dev/null 2>&1 || return 1
}

ensure_projectying_build_stack() {
  ensure_pkg git git || return 1
  ensure_pkg cargo rust || return 1
  ensure_pkg clang clang || return 1
  ensure_pkg pkg-config pkg-config || return 1
  ensure_pkg make make || return 1
}

ensure_project_clone_stack() {
  ensure_pkg git git || return 1
}

ensure_projectling_stack() {
  ensure_pkg git git || return 1
  ensure_pkg python python || return 1
}

ensure_codex_stack() {
  ensure_node_stack || return 1
}

codex_platform_package() {
  local arch=""
  arch="$(node -p 'process.arch' 2>/dev/null || true)"
  case "$arch" in
    arm64) printf '%s\n' '@openai/codex-linux-arm64' ;;
    x64) printf '%s\n' '@openai/codex-linux-x64' ;;
    *)
      log "component=codex verify-failed reason=unsupported-node-arch arch=${arch:-unknown}"
      return 1
      ;;
  esac
}

codex_native_binary_path() {
  local arch="" package_dir="" candidate=""
  arch="$(node -p 'process.arch' 2>/dev/null || true)"
  case "$arch" in
    arm64)
      package_dir="$PREFIX_DIR/lib/node_modules/@openai/codex-linux-arm64"
      for candidate in \
        "$package_dir/vendor/aarch64-unknown-linux-musl/bin/codex" \
        "$package_dir/vendor/aarch64-unknown-linux-musl/codex/codex"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
      done
      printf '%s\n' "$package_dir/vendor/aarch64-unknown-linux-musl/bin/codex"
      ;;
    x64)
      package_dir="$PREFIX_DIR/lib/node_modules/@openai/codex-linux-x64"
      for candidate in \
        "$package_dir/vendor/x86_64-unknown-linux-musl/bin/codex" \
        "$package_dir/vendor/x86_64-unknown-linux-musl/codex/codex"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
      done
      printf '%s\n' "$package_dir/vendor/x86_64-unknown-linux-musl/bin/codex"
      ;;
    *) return 1 ;;
  esac
}

codex_package_version() {
  local package_json="$PREFIX_DIR/lib/node_modules/@openai/codex/package.json"
  node -e 'const p=require(process.argv[1]); process.stdout.write(String(p.version || ""))' "$package_json" 2>/dev/null || true
}

codex_main_ready() {
  local codex_js="$PREFIX_DIR/lib/node_modules/@openai/codex/bin/codex.js"
  local package_json="$PREFIX_DIR/lib/node_modules/@openai/codex/package.json"

  [[ -x "$PREFIX_DIR/bin/codex" ]] || return 1
  [[ -s "$codex_js" ]] || return 1
  [[ -s "$package_json" ]] || return 1
}

install_codex_main_package() {
  log "npm install component=codex package=@openai/codex include=optional force=true"
  npm install -g --force --include=optional --ignore-scripts=false @openai/codex@latest
}

install_codex_native_package() {
  local version="$1"
  local platform_pkg=""
  local arch=""
  local package_dir=""
  local native_binary=""

  platform_pkg="$(codex_platform_package)" || return 1
  arch="$(node -p 'process.arch' 2>/dev/null || true)"
  [ -n "$version" ] || return 1

  case "$arch" in
    arm64|x64) ;;
    *) return 1 ;;
  esac

  package_dir="$PREFIX_DIR/lib/node_modules/${platform_pkg}"

  log "npm repair component=codex package=${platform_pkg} version=${version}"
  npm uninstall -g "$platform_pkg" >/dev/null 2>&1 || true
  case "$package_dir" in
    "$PREFIX_DIR"/lib/node_modules/@openai/codex-linux-*)
      rm -rf "$package_dir" >/dev/null 2>&1 || true
      ;;
  esac

  log "npm install component=codex package=${platform_pkg} alias=@openai/codex@${version}-linux-${arch}"
  npm install -g --force --include=optional --ignore-scripts=false \
    "${platform_pkg}@npm:@openai/codex@${version}-linux-${arch}" || return 1

  native_binary="$(codex_native_binary_path || true)"
  if [[ -n "$native_binary" && -f "$native_binary" ]]; then
    chmod 0755 "$native_binary" >/dev/null 2>&1 || true
  fi
}

write_codex_wrapper() {
  write_file_atomically "$HOME/.local/bin/codex" 0755 <<'EOF'
#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
REAL_CODEX="${PREFIX_DIR}/bin/codex"
CODEX_JS="${PREFIX_DIR}/lib/node_modules/@openai/codex/bin/codex.js"
native=''

arch="$(node -p 'process.arch' 2>/dev/null || true)"
case "$arch" in
  arm64)
    platform_pkg='@openai/codex-linux-arm64'
    for candidate in \
      "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" \
      "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/codex/codex"; do
      [ -f "$candidate" ] && { native="$candidate"; break; }
    done
    ;;
  x64)
    platform_pkg='@openai/codex-linux-x64'
    for candidate in \
      "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex" \
      "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex/codex"; do
      [ -f "$candidate" ] && { native="$candidate"; break; }
    done
    ;;
  *)
    printf 'CODEX 无法启动：当前 Node 架构不受支持：%s\n' "${arch:-unknown}" >&2
    exit 127
    ;;
esac

codex_ready() {
  [ -x "$REAL_CODEX" ] || return 1
  [ -s "$CODEX_JS" ] || return 1
  [ -n "$native" ] || return 1
  [ -x "$native" ] || return 1
}

codex_repair_once() {
  [ "${AITERMUX_CODEX_SELF_HEAL:-1}" = "1" ] || return 1
  [ "${AITERMUX_CODEX_BOOTSTRAP_ACTIVE:-0}" != "1" ] || return 1
  bootstrap="${AITERMUX_HOME:-$HOME/AItermux}/bin/aitermux-bootstrap"
  [ -x "$bootstrap" ] || return 1
  printf 'CODEX 组件不完整，正在自动修复...\n' >&2
  AITERMUX_CODEX_BOOTSTRAP_ACTIVE=1 "$bootstrap" --force --component codex >&2
}

if ! codex_ready; then
  codex_repair_once || true
fi

if ! codex_ready; then
  native=''
  case "$arch" in
    arm64)
      for candidate in \
        "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" \
        "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/codex/codex"; do
        [ -f "$candidate" ] && { native="$candidate"; break; }
      done
      ;;
    x64)
      for candidate in \
        "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex" \
        "${PREFIX_DIR}/lib/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex/codex"; do
        [ -f "$candidate" ] && { native="$candidate"; break; }
      done
      ;;
  esac
  [ -n "$native" ] && chmod 0755 "$native" 2>/dev/null || true
  if [ ! -x "$REAL_CODEX" ] || [ ! -s "$CODEX_JS" ]; then
    printf 'CODEX 尚未安装完整。请运行：aitermux-cli-install codex\n' >&2
  elif [ -z "$native" ] || [ ! -x "$native" ]; then
    printf 'CODEX 缺少原生组件：%s\n' "$platform_pkg" >&2
    printf '请运行：aitermux-cli-install codex\n' >&2
  fi
  exit 127
fi

export SSL_CERT_FILE="${SSL_CERT_FILE:-${PREFIX_DIR}/etc/tls/cert.pem}"
exec "$REAL_CODEX" "$@"
EOF
}

ensure_claude_stack() {
  ensure_node_stack || return 1
  ensure_pkg proot proot || return 1
  ensure_pkg proot-distro proot-distro || return 1
  if ! proot-distro login alpine -- true >/dev/null 2>&1; then
    log "proot-distro install alpine for claude"
    proot-distro install alpine || return 1
  fi
}

write_gemini_wrapper() {
  write_file_atomically "$HOME/.local/bin/gemini" 0755 <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
REAL_GEMINI="${PREFIX_DIR}/bin/gemini"
REAL_NODE="${PREFIX_DIR}/bin/node"
REAL_GEMINI_BUNDLE="${PREFIX_DIR}/lib/node_modules/@google/gemini-cli/bundle/gemini.js"
REAL_GEMINI_DIST="${PREFIX_DIR}/lib/node_modules/@google/gemini-cli/dist/index.js"
GEMINI_ENV_FILE="${HOME}/.gemini/env"

if [ -f "$GEMINI_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$GEMINI_ENV_FILE"
fi

if [ -x "$REAL_GEMINI" ]; then
  exec "$REAL_GEMINI" "$@"
fi

if [ -f "$REAL_GEMINI_BUNDLE" ]; then
  exec "$REAL_NODE" "$REAL_GEMINI_BUNDLE" "$@"
fi

if [ -f "$REAL_GEMINI_DIST" ]; then
  exec "$REAL_NODE" "$REAL_GEMINI_DIST" "$@"
fi

printf 'gemini launcher not found under %s\n' "${PREFIX_DIR}/lib/node_modules/@google/gemini-cli" >&2
exit 127
EOF
}

write_claude_wrapper() {
  write_file_atomically "$HOME/.local/bin/claude" 0755 <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
REAL_CLAUDE="${PREFIX_DIR}/bin/claude"
REAL_NODE="${PREFIX_DIR}/bin/node"
REAL_CLAUDE_BIN="${PREFIX_DIR}/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
MUSL_CLAUDE="${PREFIX_DIR}/lib/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude"

if [ -x "$MUSL_CLAUDE" ] && command -v proot-distro >/dev/null 2>&1; then
  exec proot-distro login alpine -- sh -lc 'cd "$1" 2>/dev/null || cd /root; shift; exec "$@"' sh "$PWD" "$MUSL_CLAUDE" "$@"
fi

if [ -x "$REAL_CLAUDE" ] && [ -f "$REAL_CLAUDE_BIN" ] && [ "$(wc -c <"$REAL_CLAUDE_BIN" 2>/dev/null || echo 0)" -gt 4096 ]; then
  exec "$REAL_CLAUDE" "$@"
fi

if [ -f "$REAL_CLAUDE_BIN" ] && [ "$(wc -c <"$REAL_CLAUDE_BIN" 2>/dev/null || echo 0)" -gt 4096 ]; then
  exec "$REAL_NODE" "$REAL_CLAUDE_BIN" "$@"
fi

printf 'Claude Code is not runnable in this Termux install.\n' >&2
printf 'Expected Alpine proot plus %s\n' "$MUSL_CLAUDE" >&2
exit 127
EOF
}

gemini_entry_path() {
  local path=""
  for path in \
    "$PREFIX_DIR/lib/node_modules/@google/gemini-cli/bundle/gemini.js" \
    "$PREFIX_DIR/lib/node_modules/@google/gemini-cli/dist/index.js"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

claude_entry_path() {
  local path=""
  for path in \
    "$PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude" \
    "$PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

verify_codex() {
  local version=""
  local codex_js="$PREFIX_DIR/lib/node_modules/@openai/codex/bin/codex.js"
  local package_json="$PREFIX_DIR/lib/node_modules/@openai/codex/package.json"
  local platform_pkg="" native_binary=""

  if [[ ! -x "$PREFIX_DIR/bin/codex" ]]; then
    log "component=codex verify-failed reason=missing-command"
    return 1
  fi
  if [[ ! -s "$codex_js" ]]; then
    log "component=codex verify-failed reason=missing-entry"
    return 1
  fi
  if [[ ! -s "$package_json" ]]; then
    log "component=codex verify-failed reason=missing-package-json"
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    log "component=codex verify-failed reason=missing-node"
    return 1
  fi
  platform_pkg="$(codex_platform_package)" || return 1
  native_binary="$(codex_native_binary_path || true)"
  if [[ -z "$native_binary" || ! -x "$native_binary" ]]; then
    log "component=codex verify-failed reason=missing-native package=${platform_pkg:-unknown}"
    return 1
  fi
  if ! node -e 'const r=require("module").createRequire(process.argv[1]); r.resolve(process.argv[2] + "/package.json")' "$codex_js" "$platform_pkg" >/dev/null 2>&1; then
    log "component=codex verify-failed reason=missing-native-package package=${platform_pkg}"
    return 1
  fi
  version="$(codex_package_version)"
  [[ -n "$version" ]] || version="unknown-version"
  log "component=codex verify-ok method=native package_version=${version} native=${platform_pkg}"
  return 0
}

verify_gemini() {
  local version=""
  if [[ ! -x "$HOME/.local/bin/gemini" ]]; then
    log "component=gemini verify-failed reason=missing-wrapper"
    return 1
  fi
  if ! version="$("$HOME/.local/bin/gemini" --version 2>/dev/null | head -n 1)"; then
    log "component=gemini verify-failed reason=version-command-failed"
    return 1
  fi
  [[ -n "$version" ]] || version="unknown-version"
  log "component=gemini verify-ok version=${version}"
  return 0
}

verify_claude() {
  local version=""
  if [[ ! -x "$HOME/.local/bin/claude" ]]; then
    log "component=claude verify-failed reason=missing-wrapper"
    return 1
  fi
  if ! version="$("$HOME/.local/bin/claude" --version 2>/dev/null | head -n 1)"; then
    log "component=claude verify-failed reason=version-command-failed"
    return 1
  fi
  [[ -n "$version" ]] || version="unknown-version"
  log "component=claude verify-ok version=${version}"
  return 0
}

git_remote_head() {
  local repo="$1"
  git ls-remote "$repo" HEAD 2>/dev/null | awk 'NR==1 { print $1 }'
}

git_local_head() {
  local dir="$1"
  git -C "$dir" rev-parse HEAD 2>/dev/null || true
}

ensure_git_remote_url() {
  local dir="$1"
  local repo="$2"
  local current=""

  current="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    git -C "$dir" remote add origin "$repo" || return 1
    return 0
  fi
  if [[ "$current" != "$repo" ]]; then
    log "git remote differs path=$dir current=$current expected=$repo"
    state_set "$(basename "$dir")" fail remote-mismatch
    return 1
  fi
}

update_git_project() {
  local component="$1"
  local dir="$2"
  local repo="$3"
  local before="" remote="" after=""

  skip_due_to_backoff "$component" && return 0

  if [[ ! -d "$dir/.git" ]]; then
    if [[ -e "$dir" ]]; then
      log "component=${component} update-failed reason=not-git path=$dir"
      state_set "$component" fail not-git
      return 1
    fi
    return 0
  fi

  ensure_project_clone_stack || {
    state_set "$component" fail missing-git
    return 1
  }

  ensure_git_remote_url "$dir" "$repo" || {
    state_set "$component" fail remote-mismatch
    return 1
  }

  if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
    log "component=${component} update-blocked reason=dirty-worktree path=$dir"
    state_set "$component" fail dirty-worktree
    return 1
  fi

  before="$(git_local_head "$dir")"
  remote="$(git_remote_head "$repo")"
  if [[ -z "$remote" ]]; then
    log "component=${component} update-failed reason=remote-head-unavailable repo=$repo"
    state_set "$component" fail remote-head-unavailable
    return 1
  fi

  if [[ "$before" == "$remote" ]]; then
    log "component=${component} update-none head=${before:0:12}"
    state_set "$component" ok up-to-date
    return 0
  fi

  log "component=${component} update-fetch before=${before:0:12} remote=${remote:0:12}"
  git -C "$dir" fetch --prune origin || {
    state_set "$component" fail git-fetch-failed
    return 1
  }
  git -C "$dir" pull --ff-only origin main || {
    state_set "$component" fail git-pull-failed
    return 1
  }
  after="$(git_local_head "$dir")"
  log "component=${component} update-ok before=${before:0:12} after=${after:0:12}"
  if [[ "$component" == "aitermux" ]]; then
    if [[ -x "$AITERMUX_HOME/Quickinstall/install.sh" ]]; then
      log "component=aitermux deploy-updated-quickinstall"
      if ! bash "$AITERMUX_HOME/Quickinstall/install.sh" --quiet; then
        state_set "$component" fail deploy-failed
        return 1
      fi
    else
      log "component=aitermux deploy-skipped reason=missing-install-sh"
    fi
  fi
  state_set "$component" ok updated
  return 0
}

projectling_dir_is_aidebug_only() {
  local item="" base=""

  [[ -d "$PROJECTLING_DIR" ]] || return 1
  shopt -s nullglob dotglob
  for item in "$PROJECTLING_DIR"/*; do
    base="$(basename "$item")"
    case "$base" in
      aidebug) ;;
      .|..) ;;
      *) return 1 ;;
    esac
  done
  shopt -u nullglob dotglob
  return 0
}

clone_projectling_preserving_aidebug() {
  local tmp_dir=""
  local item=""

  if [[ ! -d "$PROJECTLING_DIR" ]]; then
    git clone "$PROJECTLING_REPO" "$PROJECTLING_DIR"
    return $?
  fi

  tmp_dir="${PROJECTLING_DIR}.clone.$$"
  rm -rf "$tmp_dir" >/dev/null 2>&1 || true
  git clone "$PROJECTLING_REPO" "$tmp_dir" || return 1
  shopt -s nullglob dotglob
  for item in "$tmp_dir"/*; do
    mv "$item" "$PROJECTLING_DIR"/ || {
      shopt -u nullglob dotglob
      rm -rf "$tmp_dir" >/dev/null 2>&1 || true
      return 1
    }
  done
  shopt -u nullglob dotglob
  rmdir "$tmp_dir" >/dev/null 2>&1 || rm -rf "$tmp_dir" >/dev/null 2>&1 || true
  return 0
}

ensure_projectying() {
  local component="projectying"

  if [[ -f "$PROJECTYING_DIR/run.sh" ]]; then
    chmod u+x "$PROJECTYING_DIR/run.sh" >/dev/null 2>&1 || true
    state_set "$component" ok present
    return 0
  fi

  skip_due_to_backoff "$component" && return 0

  ensure_projectying_build_stack || {
    state_set "$component" fail missing-build-stack
    return 1
  }

  if [[ -e "$PROJECTYING_DIR" && ! -d "$PROJECTYING_DIR/.git" ]]; then
    log "component=${component} path-exists-but-invalid path=$PROJECTYING_DIR"
    state_set "$component" fail path-exists-but-invalid
    return 1
  fi

  if [[ ! -d "$PROJECTYING_DIR" ]]; then
    mkdir -p "$AITERMUX_HOME" >/dev/null 2>&1 || true
    log "git clone component=${component} repo=${PROJECTYING_REPO}"
    if ! git clone "$PROJECTYING_REPO" "$PROJECTYING_DIR"; then
      state_set "$component" fail git-clone-failed
      return 1
    fi
  fi

  if [[ ! -f "$PROJECTYING_DIR/run.sh" ]]; then
    log "component=${component} missing run.sh after clone"
    state_set "$component" fail missing-runsh
    return 1
  fi

  chmod u+x "$PROJECTYING_DIR/run.sh" >/dev/null 2>&1 || true
  state_set "$component" ok ready
  return 0
}

ensure_projectling() {
  local component="projectling"

  if [[ -f "$PROJECTLING_DIR/run.sh" ]]; then
    chmod u+x "$PROJECTLING_DIR/run.sh" >/dev/null 2>&1 || true
    state_set "$component" ok present
    return 0
  fi

  skip_due_to_backoff "$component" && return 0
  ensure_projectling_stack || {
    state_set "$component" fail missing-projectling-stack
    return 1
  }

  if [[ -e "$PROJECTLING_DIR" && ! -d "$PROJECTLING_DIR/.git" ]] && ! projectling_dir_is_aidebug_only; then
    log "component=${component} path-exists-but-invalid path=$PROJECTLING_DIR"
    state_set "$component" fail path-exists-but-invalid
    return 1
  fi

  if [[ ! -d "$PROJECTLING_DIR/.git" ]]; then
    mkdir -p "$AITERMUX_HOME" >/dev/null 2>&1 || true
    log "git clone component=${component} repo=${PROJECTLING_REPO}"
    if ! clone_projectling_preserving_aidebug; then
      state_set "$component" fail git-clone-failed
      return 1
    fi
  fi

  if [[ ! -f "$PROJECTLING_DIR/run.sh" ]]; then
    log "component=${component} missing run.sh after clone"
    state_set "$component" fail missing-runsh
    return 1
  fi

  chmod u+x "$PROJECTLING_DIR/run.sh" >/dev/null 2>&1 || true
  state_set "$component" ok ready
  return 0
}

ensure_codex() {
  local component="codex"
  local codex_js="$PREFIX_DIR/lib/node_modules/@openai/codex/bin/codex.js"
  local version=""

  if [[ -f "$codex_js" ]]; then
    write_codex_wrapper || true
    if verify_codex; then
      state_set "$component" ok present
      return 0
    fi
  fi

  skip_due_to_backoff "$component" && return 0
  ensure_codex_stack || {
    state_set "$component" fail missing-codex-stack
    return 1
  }

  append_line_if_missing "$HOME/.npmrc" "foreground-scripts=true"

  if ! codex_main_ready; then
    if ! install_codex_main_package; then
      state_set "$component" fail npm-install-failed
      return 1
    fi
  fi

  version="$(codex_package_version)"
  if [[ -z "$version" ]]; then
    if ! install_codex_main_package; then
      state_set "$component" fail npm-install-failed
      return 1
    fi
    version="$(codex_package_version)"
  fi

  if ! verify_codex; then
    if [[ -n "$version" ]]; then
      install_codex_native_package "$version" || {
        state_set "$component" fail native-install-failed
        return 1
      }
    fi
  fi

  write_codex_wrapper || {
    state_set "$component" fail wrapper-write-failed
    return 1
  }

  verify_codex || {
    state_set "$component" fail verify-failed
    return 1
  }

  state_set "$component" ok ready
  return 0
}

ensure_gemini() {
  local component="gemini"
  local gemini_js=""

  gemini_js="$(gemini_entry_path || true)"
  if [[ -n "$gemini_js" && ( -x "$HOME/.local/bin/gemini" || -x "$PREFIX_DIR/bin/gemini" ) ]]; then
    write_gemini_wrapper || true
    if verify_gemini; then
      state_set "$component" ok present
      return 0
    fi
  fi

  skip_due_to_backoff "$component" && return 0
  ensure_node_stack || {
    state_set "$component" fail missing-node-stack
    return 1
  }

  if [[ -z "$gemini_js" ]]; then
    log "npm install component=${component} package=@google/gemini-cli ignore-scripts=true"
    if ! npm install -g --ignore-scripts=true @google/gemini-cli; then
      state_set "$component" fail npm-install-failed
      return 1
    fi
    gemini_js="$(gemini_entry_path || true)"
  fi

  write_gemini_wrapper || {
    state_set "$component" fail wrapper-write-failed
    return 1
  }

  verify_gemini || {
    state_set "$component" fail verify-failed
    return 1
  }

  state_set "$component" ok ready
  return 0
}

ensure_claude() {
  local component="claude"
  local claude_bin=""
  local musl_claude="$PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude"

  claude_bin="$(claude_entry_path || true)"
  if [[ -x "$musl_claude" && -x "$HOME/.local/bin/claude" ]] && proot-distro login alpine -- true >/dev/null 2>&1; then
    write_claude_wrapper || true
    if verify_claude; then
      state_set "$component" ok present
      return 0
    fi
  fi

  skip_due_to_backoff "$component" && return 0
  ensure_claude_stack || {
    state_set "$component" fail missing-claude-stack
    return 1
  }

  if [[ -z "$claude_bin" ]]; then
    log "npm install component=${component} package=@anthropic-ai/claude-code include=optional ignore-scripts=false"
    if ! npm install -g --include=optional --ignore-scripts=false @anthropic-ai/claude-code; then
      state_set "$component" fail npm-install-failed
      return 1
    fi
    claude_bin="$(claude_entry_path || true)"
  fi

  if [[ ! -x "$musl_claude" ]]; then
    log "npm install component=${component} package=@anthropic-ai/claude-code-linux-arm64-musl force=true"
    if ! npm install -g --force --include=optional --ignore-scripts=false @anthropic-ai/claude-code-linux-arm64-musl; then
      state_set "$component" fail npm-musl-install-failed
      return 1
    fi
  fi

  if [[ -z "$claude_bin" && ! -x "$musl_claude" ]]; then
    state_set "$component" fail missing-claude-entry
    return 1
  fi

  write_claude_wrapper || {
    state_set "$component" fail wrapper-write-failed
    return 1
  }

  verify_claude || {
    state_set "$component" fail verify-failed
    return 1
  }

  state_set "$component" ok ready
  return 0
}

run_component() {
  local component="$1"

  if (( UPDATE == 1 )); then
    case "$component" in
      aitermux)
        update_git_project aitermux "$AITERMUX_HOME" "$AITERMUX_REPO"
        ;;
      projectying)
        ensure_projectying || return 1
        update_git_project projectying "$PROJECTYING_DIR" "$PROJECTYING_REPO"
        ;;
      projectling)
        ensure_projectling || return 1
        update_git_project projectling "$PROJECTLING_DIR" "$PROJECTLING_REPO"
        ;;
      *)
        log "update unsupported component=$component"
        state_set "$component" fail update-unsupported
        return 1
        ;;
    esac
    return $?
  fi

  case "$component" in
    projectying) ensure_projectying ;;
    projectling) ensure_projectling ;;
    codex) ensure_codex ;;
    gemini) ensure_gemini ;;
    claude) ensure_claude ;;
    *)
      log "unknown component=$component"
      return 1
      ;;
  esac
}

while (($#)); do
  case "$1" in
    --quiet)
      QUIET=1
      ;;
    --force)
      FORCE=1
      ;;
    --update)
      UPDATE=1
      ;;
    --component)
      shift
      (($#)) || {
        usage >&2
        exit 2
      }
      COMPONENTS+=("$1")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ((${#COMPONENTS[@]} == 0)); then
  if (( UPDATE == 1 )); then
    COMPONENTS=(aitermux projectying projectling)
  else
    COMPONENTS=(projectying projectling codex gemini claude)
  fi
fi

rc=0
for component in "${COMPONENTS[@]}"; do
  if ! run_component "$component"; then
    rc=1
  fi
done

exit "$rc"
