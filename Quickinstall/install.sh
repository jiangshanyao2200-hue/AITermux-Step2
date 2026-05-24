#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

QUICK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$QUICK_ROOT/.." && pwd)"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
AITERMUX_HOME="${AITERMUX_HOME:-$HOME/AItermux}"
PROJECTYING_REPO="${AITERMUX_PROJECTYING_REPO:-https://github.com/jiangshanyao2200-hue/projectying-termux.git}"
PROJECTLING_REPO="${AITERMUX_PROJECTLING_REPO:-https://github.com/jiangshanyao2200-hue/projectling-termux.git}"
BACKUP_ROOT="$AITERMUX_HOME/backups"
AIDEBUG_DIR="${AITERMUX_AIDEBUG_DIR:-$AITERMUX_HOME/projectling/aidebug}"
AIDEBUG_LOG_DIR="$AIDEBUG_DIR/logs"
INSTALL_AIDEBUG_LOG="$AIDEBUG_LOG_DIR/install.log"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/upgrade-$STAMP"
DRY_RUN=0
QUIET=0

usage() {
  cat <<'EOF'
AITermux 一键覆盖部署（Termux）

用法：
  bash ~/AItermux/install.sh [--dry-run] [--quiet]
  # 或者：cd ~/AItermux/Quickinstall && bash install.sh [args]

参数：
  --dry-run       仅打印操作，不写入文件
  --quiet         减少输出（不打印每条命令）

环境变量：
  AITERMUX_HOME            默认：$HOME/AItermux
  AITERMUX_AIDEBUG_DIR     默认：$HOME/AItermux/projectling/aidebug
  AITERMUX_PROJECTYING_REPO 默认：https://github.com/jiangshanyao2200-hue/projectying-termux.git
  AITERMUX_PROJECTLING_REPO 默认：https://github.com/jiangshanyao2200-hue/projectling-termux.git
EOF
}

log() {
  printf '[%s] [install-aitermux] %s\n' "$(date '+%F %T' 2>/dev/null || echo unknown)" "$*"
}

append_manifest() {
  (( DRY_RUN == 0 )) || return 0
  [ -n "${MANIFEST_FILE:-}" ] || return 0
  printf '%s\n' "$*" >>"$MANIFEST_FILE" 2>/dev/null || true
}

run_cmd() {
  if (( QUIET == 0 )); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  fi
  (( DRY_RUN )) && return 0
  "$@"
}

backup_file() {
  local target="$1"
  [ -e "$target" ] || return 0
  local rel="${target#/}"
  local dest="$BACKUP_DIR/$rel"
  run_cmd mkdir -p "$(dirname "$dest")"
  log "备份：$target -> $dest"
  run_cmd cp -a "$target" "$dest"
}

cleanup_home_junk_files() {
  local rel path
  local -a junk_paths=(
    "longgu-stage1.log"
    "longgu-termux-kit-step1"
    "old-config-20260524-033818.tar.xz"
    "termux-desktop.log"
    ".zshrc-24-05-2026.bak"
  )

  log "清理已知安装残留"
  for rel in "${junk_paths[@]}"; do
    path="$HOME/$rel"
    [ -e "$path" ] || continue
    log "删除残留：$path"
    run_cmd rm -rf "$path"
  done
}

cleanup_old_backup_dirs() {
  local keep="${AITERMUX_BACKUP_KEEP:-5}"
  local index=0 dir

  case "$keep" in ''|*[!0-9]*) keep=5 ;; esac
  [ "$keep" -ge 1 ] 2>/dev/null || keep=5
  [ -d "$BACKUP_ROOT" ] || return 0

  log "清理旧备份目录：保留最近 ${keep} 个 upgrade-*"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    index=$((index + 1))
    [ "$index" -le "$keep" ] && continue
    [ -d "$dir" ] || continue
    log "删除旧备份：$dir"
    run_cmd rm -rf "$dir"
  done < <(ls -1dt "$BACKUP_ROOT"/upgrade-* 2>/dev/null || true)
}

install_file() {
  local src="$1"
  local dst="$2"
  local mode="$3"
  local sha_src="" sha_dst=""
  backup_file "$dst"
  run_cmd mkdir -p "$(dirname "$dst")"
  log "写入：$dst (mode=$mode) <- $src"
  run_cmd install -m "$mode" "$src" "$dst"
  if (( DRY_RUN == 0 )); then
    sha_src="$(sha256sum "$src" 2>/dev/null | awk '{print $1}' || true)"
    sha_dst="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}' || true)"
    append_manifest "$(printf '%s\t%s\t%s\t%s' "$mode" "$dst" "${sha_dst:-}" "${sha_src:-}")"
  fi
}

ensure_termux_shell() {
  local zsh_bin="$PREFIX_DIR/bin/zsh"
  local shell_link="$HOME/.termux/shell"

  if [ ! -x "$zsh_bin" ]; then
    echo "[install-aitermux] 未检测到 zsh：$zsh_bin" >&2
    echo "[install-aitermux] 请先执行：pkg install zsh" >&2
    exit 1
  fi

  backup_file "$shell_link"
  run_cmd mkdir -p "$HOME/.termux"
  log "设置登录 shell：$shell_link -> $zsh_bin"
  run_cmd ln -sfn "$zsh_bin" "$shell_link"
  append_manifest "$(printf 'shell\t%s\t%s' "$shell_link" "$zsh_bin")"
}

ensure_zshrc_block() {
  local zshrc="$HOME/.zshrc"
  local marker_begin="# >>> AITERMUX AUTOSTART >>>"
  local marker_end="# <<< AITERMUX AUTOSTART <<<"

  if (( DRY_RUN )); then
    log "将更新 $zshrc 的 AITERMUX AUTOSTART 段。"
    return 0
  fi

  mkdir -p "$(dirname "$zshrc")"
  [ -f "$zshrc" ] || touch "$zshrc"
  backup_file "$zshrc"
  log "写入：$zshrc（注入 AITERMUX AUTOSTART 段）"

  local tmp="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/zshrc.aitermux.$$"
  awk -v b="$marker_begin" -v e="$marker_end" '
    BEGIN { skip=0 }
    $0==b { skip=1; next }
    $0==e { skip=0; next }
    !skip { print }
  ' "$zshrc" >"$tmp"

  local tmp2="${tmp}.legacy"
  awk '
    BEGIN { in_legacy=0; seen_unset=0 }
    {
      if (!in_legacy && $0 ~ /^# CMD 模式：从 AItermux 切到原生 zsh/) {
        in_legacy=1
        next
      }
      if (in_legacy) {
        if ($0 ~ /^\s*unset _aitermux_rc _aitermux_tty_id _aitermux_motd_runfile\s*$/) {
          seen_unset=1
          next
        }
        if (seen_unset && $0 ~ /^\s*fi\s*$/) {
          in_legacy=0
          seen_unset=0
          next
        }
        next
      }
      print
    }
  ' "$tmp" >"$tmp2"

  {
    cat "$tmp2"
    printf '\n%s\n' "$marker_begin"
    cat "$QUICK_ROOT/deploy/aitermux/zshrc.autostart.zsh"
    printf '%s\n' "$marker_end"
  } >"$tmp.new"

  mv "$tmp.new" "$zshrc"
  rm -f "$tmp" "$tmp2"
  append_manifest "$(printf 'zshrc\t%s' "$zshrc")"
}

ensure_zsh_theme_source() {
  local zshrc="$HOME/.zshrc"
  local source_line='source "/data/data/com.termux/files/home/.zsh-themes/td.zsh-theme"'

  if (( DRY_RUN )); then
    log "将校验 $zshrc 是否加载 td.zsh-theme。"
    return 0
  fi

  mkdir -p "$(dirname "$zshrc")"
  [ -f "$zshrc" ] || touch "$zshrc"
  if grep -Fqx "$source_line" "$zshrc" 2>/dev/null; then
    return 0
  fi

  backup_file "$zshrc"
  log "写入：$zshrc（补齐 td.zsh-theme source 行）"
  printf '\n%s\n' "$source_line" >>"$zshrc"
}

install_startboot_pool() {
  local src base mode

  log "安装开屏动画脚本池"
  for src in "$QUICK_ROOT"/deploy/startboot/*; do
    [ -f "$src" ] || continue
    base="$(basename "$src")"
    mode=0644
    case "$base" in
      *.sh) mode=0755 ;;
    esac
    install_file "$src" "$AITERMUX_HOME/startboot/$base" "$mode"
  done
}

install_zsh_theme() {
  local src="$QUICK_ROOT/deploy/aitermux/td.zsh-theme"
  local dst="$HOME/.zsh-themes/td.zsh-theme"

  if [ ! -f "$src" ]; then
    echo "[install-aitermux] zsh 主题缺失：$src" >&2
    exit 1
  fi

  log "安装 zsh 主题"
  install_file "$src" "$dst" 0644
}

install_aidebug_runtime() {
  log "准备 ProjectLing aidebug 调试链路"
  run_cmd mkdir -p \
    "$AIDEBUG_DIR" \
    "$AIDEBUG_DIR/bin" \
    "$AIDEBUG_DIR/logs" \
    "$AIDEBUG_DIR/notes" \
    "$AIDEBUG_DIR/state" \
    "$AIDEBUG_DIR/legacy" \
    "$AIDEBUG_DIR/tmp" \
    "$AIDEBUG_DIR/projectling/terminal output" \
    "$HOME/.local/bin"

  if [ -f "$AIDEBUG_DIR/bin/aidebug" ]; then
    run_cmd chmod 0755 "$AIDEBUG_DIR/bin/aidebug"
    run_cmd ln -sfn "$AIDEBUG_DIR/bin/aidebug" "$HOME/.local/bin/aidebug"
  else
    log "aidebug 启动器尚未就绪，将在 ProjectLing 拉取后自动补链。"
  fi
}

install_local_bin_tools() {
  local src_root="$QUICK_ROOT/deploy/local/bin"
  local src base

  [ -d "$src_root" ] || return 0
  log "安装 AITermux 本地工具"
  run_cmd mkdir -p "$HOME/.local/bin"
  while IFS= read -r src; do
    base="$(basename "$src")"
    install_file "$src" "$HOME/.local/bin/$base" 0755
  done < <(find "$src_root" -maxdepth 1 -type f | sort)
}

install_aitermux_bin_tools() {
  local src_root="$QUICK_ROOT/deploy/aitermux/bin"
  local src base

  [ -d "$src_root" ] || return 0
  log "安装 AITermux bin 工具"
  run_cmd mkdir -p "$AITERMUX_HOME/bin"
  while IFS= read -r src; do
    base="$(basename "$src")"
    install_file "$src" "$AITERMUX_HOME/bin/$base" 0755
  done < <(find "$src_root" -maxdepth 1 -type f | sort)
}

install_project_components() {
  local bootstrap="$AITERMUX_HOME/bin/aitermux-bootstrap"
  local component=""

  if (( DRY_RUN )); then
    log "将通过 bootstrap 检查/拉取 projectling 与 projectying。"
    return 0
  fi

  if [ ! -x "$bootstrap" ]; then
    log "bootstrap 缺失，跳过 projectling/projectying 拉取：$bootstrap"
    return 0
  fi

  for component in projectling projectying; do
    log "检查/拉取组件：$component"
    if "$bootstrap" --force --component "$component"; then
      log "组件就绪：$component"
    else
      log "组件补装失败：$component（可在 motd 设置菜单里稍后重试）"
    fi
  done
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --quiet) QUIET=1 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "未知参数：$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -d "$PREFIX_DIR/bin" ] || [ ! -d "$PREFIX_DIR/etc" ]; then
  echo "[install-aitermux] 未检测到有效的 Termux PREFIX：$PREFIX_DIR" >&2
  exit 1
fi

if [ ! -f "$QUICK_ROOT/deploy/termux/motd.sh" ]; then
  echo "[install-aitermux] 部署模板缺失：$QUICK_ROOT/deploy/termux/motd.sh" >&2
  exit 1
fi

log "备份目录：$BACKUP_DIR"
run_cmd mkdir -p "$BACKUP_DIR"

MANIFEST_FILE="$BACKUP_DIR/manifest.tsv"
if (( DRY_RUN == 0 )); then
  : >"$MANIFEST_FILE" 2>/dev/null || true
  printf 'mode\tpath\tsha_dst\tsha_src\n' >>"$MANIFEST_FILE" 2>/dev/null || true
  mkdir -p "$AIDEBUG_LOG_DIR" 2>/dev/null || true

  if command -v tee >/dev/null 2>&1; then
    exec > >(tee -a "$BACKUP_DIR/install.log" "$INSTALL_AIDEBUG_LOG") 2>&1
    log "安装日志：$BACKUP_DIR/install.log / $INSTALL_AIDEBUG_LOG"
  fi
fi

trap 'log "错误：安装中断（line=$LINENO）。可用备份目录回滚：$BACKUP_DIR"' ERR

run_cmd mkdir -p "$AITERMUX_HOME" "$AITERMUX_HOME/bin" "$AITERMUX_HOME/startboot" "$HOME/.termux"
install_aidebug_runtime

log "校验 zsh 登录链"
ensure_termux_shell

log "覆盖 Termux 启动链路文件"
install_file "$QUICK_ROOT/deploy/termux/motd.sh" "$HOME/.termux/motd.sh" 0755
install_file "$QUICK_ROOT/deploy/termux/termux.properties" "$HOME/.termux/termux.properties" 0644
install_file "$QUICK_ROOT/deploy/termux/login.sh" "$PREFIX_DIR/bin/login" 0755
install_file "$QUICK_ROOT/deploy/termux/etc-motd.sh" "$PREFIX_DIR/etc/motd.sh" 0755
install_file "$QUICK_ROOT/deploy/termux/termux-login.sh" "$PREFIX_DIR/etc/termux-login.sh" 0755
install_file "$QUICK_ROOT/deploy/termux/tx11start.sh" "$PREFIX_DIR/bin/tx11start" 0755

log "安装 AITermux 启动器"
install_file "$QUICK_ROOT/deploy/aitermux/aitermux" "$AITERMUX_HOME/bin/aitermux" 0755
install_file "$QUICK_ROOT/deploy/aitermux/bootstrap.sh" "$AITERMUX_HOME/bin/aitermux-bootstrap" 0755
install_aitermux_bin_tools
install_project_components
install_aidebug_runtime

install_zsh_theme

install_local_bin_tools

install_startboot_pool

log "写入 zsh 自动启动段"
ensure_zshrc_block
ensure_zsh_theme_source

if (( DRY_RUN == 0 )); then
  log "生成回滚脚本：$BACKUP_DIR/rollback.sh"
  cat >"$BACKUP_DIR/rollback.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BACKUP_DIR"

echo "[rollback] from: $BACKUP_DIR"
if [ -d ./data/data ]; then
  find ./data/data -type f -print0 | while IFS= read -r -d '' f; do
    target="/${f#./}"
    mkdir -p "$(dirname "$target")"
    cp -a "$f" "$target"
    echo "[rollback] restore: $target"
  done
fi
echo "[rollback] done."
EOF
  chmod 0755 "$BACKUP_DIR/rollback.sh" 2>/dev/null || true
fi

cleanup_home_junk_files
cleanup_old_backup_dirs

log "完成。"
log "projectying 仓库地址：$PROJECTYING_REPO"
log "projectling 仓库地址：$PROJECTLING_REPO"
log "本次部署 AITermux 启动链/样式层，并通过 bootstrap 按需拉取 projectling/projectying 源码。"
log "本次不主动安装 codex/gemini/claude；下次点击对应 Launcher 入口时按需补装。"
log "下次新开 Termux 会话将自动进入 AITermux。"
log "如需回滚，请从 $BACKUP_DIR 取回被覆盖文件。"
