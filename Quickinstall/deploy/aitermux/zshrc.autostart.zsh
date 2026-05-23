# launcher 已回收到 ~/.termux/motd.sh；zsh 保持普通 shell。
PROMPT_EOL_MARK=''
AITERMUX_HOME="${AITERMUX_HOME:-$HOME/AItermux}"
AITERMUX_AIDEBUG_DIR="${AITERMUX_AIDEBUG_DIR:-$AITERMUX_HOME/projectling/aidebug}"
AITERMUX_AIDEBUG_LOG_DIR="$AITERMUX_AIDEBUG_DIR/logs"

case ":${PATH:-}:" in
  *":$AITERMUX_HOME/bin:"*) ;;
  *) PATH="$AITERMUX_HOME/bin:${PATH:-}" ;;
esac
case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:${PATH:-}" ;;
esac
export PATH AITERMUX_HOME AITERMUX_AIDEBUG_DIR

aitermux_shrink_log_tail_if_over_kb() {
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
  tmp="$AITERMUX_AIDEBUG_LOG_DIR/.trim.$$.$RANDOM"
  if tail -c "$keep_bytes" "$path" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

aitermux_zsh_debug_log() {
  local ts msg
  msg="$*"
  mkdir -p "$AITERMUX_AIDEBUG_LOG_DIR" >/dev/null 2>&1 || true
  aitermux_shrink_log_tail_if_over_kb "$AITERMUX_AIDEBUG_LOG_DIR/startup.log" "${AITERMUX_STARTUP_LOG_MAX_KB:-1024}" "${AITERMUX_STARTUP_LOG_KEEP_KB:-512}" || true
  aitermux_shrink_log_tail_if_over_kb "$AITERMUX_AIDEBUG_LOG_DIR/zshrc.log" "${AITERMUX_COMPONENT_LOG_MAX_KB:-512}" "${AITERMUX_COMPONENT_LOG_KEEP_KB:-256}" || true
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%F %T' 2>/dev/null || echo unknown)"
  printf '%s zshrc %s\n' "$ts" "$msg" >>"$AITERMUX_AIDEBUG_LOG_DIR/startup.log" 2>/dev/null || true
  printf '%s %s\n' "$ts" "$msg" >>"$AITERMUX_AIDEBUG_LOG_DIR/zshrc.log" 2>/dev/null || true
}

aitermux_zsh_debug_log "source_start shell=${SHELL:-} tty=${TTY:-unknown} pwd=$PWD"
PROJECTLING_ZSH="${AITERMUX_HOME:-$HOME/AItermux}/projectling/projectling.zsh"
if [[ -f "$PROJECTLING_ZSH" ]]; then
  if source "$PROJECTLING_ZSH"; then
    aitermux_zsh_debug_log "projectling_source_ok path=$PROJECTLING_ZSH"
  else
    _aitermux_projectling_rc=$?
    aitermux_zsh_debug_log "projectling_source_fail rc=$_aitermux_projectling_rc path=$PROJECTLING_ZSH"
  fi
else
  aitermux_zsh_debug_log "projectling_source_missing path=$PROJECTLING_ZSH"
fi
aitermux_zsh_debug_log "source_done"
unset PROJECTLING_ZSH _aitermux_projectling_rc
