#!/data/data/com.termux/files/usr/bin/bash
# shellcheck source=/dev/null
set +e

[ "${AITERMUX_MOTD_DISABLE:-0}" = "1" ] && exit 0
tty >/dev/null 2>&1 || exit 0

PREFIX="/data/data/com.termux/files/usr"
export PATH="$PREFIX/bin:/system/bin:/system/xbin:${PATH:-}"

# Ensure UTF-8 width math for banner centering (█ etc.).
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

TTY_DEV="/dev/tty"

motd_has_tty() {
  [ -r "$TTY_DEV" ] 2>/dev/null && [ -w "$TTY_DEV" ] 2>/dev/null || return 1
  : <"$TTY_DEV" >/dev/null 2>&1 || return 1
}

tty_printf() {
  # shellcheck disable=SC2059
  if motd_has_tty; then
    printf "$@" 2>/dev/null >"$TTY_DEV" && return 0
  fi
  if [ -t 1 ]; then
    printf "$@"
  fi
}

motd_sync_begin() {
  tty_printf '\033[?2026h' || true
}

motd_sync_end() {
  tty_printf '\033[?2026l' || true
}

ROOT_DIR="${AITERMUX_HOME:-$HOME/AItermux}"
START_DIR="$ROOT_DIR/startboot"
AIDEBUG_DIR="${AITERMUX_AIDEBUG_DIR:-$ROOT_DIR/aidebug}"
LOG_DIR="$AIDEBUG_DIR/logs"
LEGACY_LOG_DIR="$ROOT_DIR/logs"
STATE_DIR="$ROOT_DIR/.state/motd"
LAUNCHER_ITEMS_FILE="$STATE_DIR/launchers.tsv"
BASH_BIN="/data/data/com.termux/files/usr/bin/bash"
DEBUG="${AITERMUX_MOTD_DEBUG:-0}"
STARTUP_LOG="$LOG_DIR/startup.log"
MOTD_LOG="$LOG_DIR/motd.log"
GUARD_STATE_FILE="$STATE_DIR/guard.state"
MOTD_CONF_FILE="$STATE_DIR/config.env"
MOTD_SCREEN_TOP_GAP=5
MOTD_SCREEN_BOTTOM_GAP=3
MOTD_LAUNCHER_TITLE='✲ Aitermux LUNCHER'
MOTD_SETTINGS_TITLE='✲ PROJECT凌 设置'
META_REASON=""
META_WRITTEN=0
MOTD_KEEP_SCREEN=0
MOTD_STTY_SAVED=""
MOTD_LAUNCHER_VALIDATE_ERROR=""
MOTD_INPUT_TIMEOUT="${AITERMUX_MOTD_INPUT_TIMEOUT:-0.25}"
MOTD_INPUT_MODE="launcher"
MOTD_INPUT_VALUE=""
MOTD_INPUT_ERROR_TEXT=""
MOTD_INPUT_DIRTY=1
MOTD_INPUT_ACTION="idle"
MOTD_REQUEST_SHELL_EXIT=0
MOTD_MENU_SELECTED=1
MOTD_CONFIG_SELECTED=1
MOTD_CONFIG_TOTAL=1
MOTD_LAST_CARD_TOP_ROW=0
MOTD_LAST_CARD_HEIGHT=0
MOTD_HIDDEN_CARD_TOP_ROW=0
MOTD_HIDDEN_CARD_HEIGHT=0
MOTD_LAST_MENU_TOP_ROW=0
MOTD_LAST_MENU_AFTER_ROW=0
MOTD_FORCE_COMPACT=0
MOTD_LAUNCHER_BASE_ROWS=0
MOTD_WINCH_DIRTY=0
MOTD_VISIBLE_ROWS=0
MOTD_CARD_CACHE_KEY=""
MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=0
MOTD_REDRAW_SCAN_MIN_ROWS="${AITERMUX_MOTD_REDRAW_SCAN_MIN_ROWS:-18}"
declare -ag MOTD_LAUNCHER_IDS=()
declare -ag MOTD_LAUNCHER_KINDS=()
declare -ag MOTD_LAUNCHER_LABELS=()
declare -ag MOTD_LAUNCHER_PATHS=()
declare -ag MOTD_CARD_CACHE_LINES=()

mkdir -p "$AIDEBUG_DIR" "$LOG_DIR" "$STATE_DIR" >/dev/null 2>&1 || true
if [ -d "$LEGACY_LOG_DIR" ] && [ "$LEGACY_LOG_DIR" != "$LOG_DIR" ]; then
  for old_log in "$LEGACY_LOG_DIR"/*; do
    [ -e "$old_log" ] || continue
    [ -f "$old_log" ] || continue
    old_base="$(basename "$old_log")"
    new_log="$LOG_DIR/$old_base"
    if [ -e "$new_log" ]; then
      new_log="$LOG_DIR/${old_base}.legacy-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    fi
    mv "$old_log" "$new_log" 2>/dev/null || true
  done
  rmdir "$LEGACY_LOG_DIR" 2>/dev/null || true
fi
[ -f "$MOTD_CONF_FILE" ] && . "$MOTD_CONF_FILE" >/dev/null 2>&1 || true
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash 2>/dev/null || echo bash)"

startup_log() {
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%F %T' 2>/dev/null || echo unknown)"
  printf '%s %s\n' "$ts" "$*" >>"$STARTUP_LOG" 2>/dev/null || true
  printf '%s %s\n' "$ts" "$*" >>"$MOTD_LOG" 2>/dev/null || true
}

motd_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

motd_is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

motd_is_size_spec() {
  [[ "${1:-}" =~ ^[0-9]+x[0-9]+$ ]]
}

motd_sanitize_field() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  motd_trim "$value"
}

motd_launcher_default_label() {
  case "${1:-}" in
    projectying) printf '%s\n' '启动 PROJECT 萤' ;;
    codex) printf '%s\n' '启动 CODEX' ;;
    gemini) printf '%s\n' '启动 Gemini' ;;
    claude) printf '%s\n' '启动 Claude Code' ;;
    xfce) printf '%s\n' '启动 Xfce 图形界面' ;;
    *) printf '%s\n' '启动项' ;;
  esac
}

motd_launcher_init_defaults() {
  MOTD_LAUNCHER_IDS=(projectying codex gemini claude xfce)
  MOTD_LAUNCHER_KINDS=(builtin builtin builtin builtin builtin)
  MOTD_LAUNCHER_LABELS=('启动 PROJECT 萤' '启动 CODEX' '启动 Gemini' '启动 Claude Code' '启动 Xfce 图形界面')
  MOTD_LAUNCHER_PATHS=("" "" "" "" "")
}

motd_launcher_save_items() {
  local tmp="$LAUNCHER_ITEMS_FILE.tmp"
  local i=0
  mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
  : >"$tmp"
  if [ "${#MOTD_LAUNCHER_IDS[@]}" -eq 0 ] 2>/dev/null; then
    printf '# empty\n' >"$tmp"
  else
    for ((i=0; i<${#MOTD_LAUNCHER_IDS[@]}; i++)); do
      printf '%s\t%s\t%s\t%s\n' \
        "$(motd_sanitize_field "${MOTD_LAUNCHER_IDS[$i]}")" \
        "$(motd_sanitize_field "${MOTD_LAUNCHER_KINDS[$i]}")" \
        "$(motd_sanitize_field "${MOTD_LAUNCHER_LABELS[$i]}")" \
        "$(motd_sanitize_field "${MOTD_LAUNCHER_PATHS[$i]}")" \
        >>"$tmp"
    done
  fi
  mv "$tmp" "$LAUNCHER_ITEMS_FILE"
}

motd_launcher_ensure_claude_default() {
  local i=0 insert_after=-1 inserted=0
  local -a next_ids=() next_kinds=() next_labels=() next_paths=()

  for ((i=0; i<${#MOTD_LAUNCHER_IDS[@]}; i++)); do
    if [ "${MOTD_LAUNCHER_IDS[$i]}" = "claude" ]; then
      return 0
    fi
    if [ "${MOTD_LAUNCHER_IDS[$i]}" = "gemini" ]; then
      insert_after="$i"
    fi
  done

  for ((i=0; i<${#MOTD_LAUNCHER_IDS[@]}; i++)); do
    next_ids+=("${MOTD_LAUNCHER_IDS[$i]}")
    next_kinds+=("${MOTD_LAUNCHER_KINDS[$i]}")
    next_labels+=("${MOTD_LAUNCHER_LABELS[$i]}")
    next_paths+=("${MOTD_LAUNCHER_PATHS[$i]}")
    if [ "$i" -eq "$insert_after" ] 2>/dev/null; then
      next_ids+=("claude")
      next_kinds+=("builtin")
      next_labels+=("启动 Claude Code")
      next_paths+=("")
      inserted=1
    fi
  done

  if [ "$inserted" -eq 0 ]; then
    next_ids+=("claude")
    next_kinds+=("builtin")
    next_labels+=("启动 Claude Code")
    next_paths+=("")
  fi

  MOTD_LAUNCHER_IDS=("${next_ids[@]}")
  MOTD_LAUNCHER_KINDS=("${next_kinds[@]}")
  MOTD_LAUNCHER_LABELS=("${next_labels[@]}")
  MOTD_LAUNCHER_PATHS=("${next_paths[@]}")
  motd_launcher_save_items
}

motd_launcher_load_items() {
  local id='' kind='' label='' path=''
  MOTD_LAUNCHER_IDS=()
  MOTD_LAUNCHER_KINDS=()
  MOTD_LAUNCHER_LABELS=()
  MOTD_LAUNCHER_PATHS=()

  if [ -f "$LAUNCHER_ITEMS_FILE" ]; then
    while IFS=$'\t' read -r id kind label path; do
      [ -n "${id:-}" ] || continue
      case "$id" in
        \#*) continue ;;
      esac
      kind="$(motd_sanitize_field "$kind")"
      label="$(motd_sanitize_field "$label")"
      path="$(motd_sanitize_field "$path")"
      if [ "$kind" = "builtin" ] && [ -z "$label" ]; then
        label="$(motd_launcher_default_label "$id")"
      fi
      MOTD_LAUNCHER_IDS+=("$id")
      MOTD_LAUNCHER_KINDS+=("${kind:-custom}")
      MOTD_LAUNCHER_LABELS+=("${label:-启动项}")
      MOTD_LAUNCHER_PATHS+=("$path")
    done <"$LAUNCHER_ITEMS_FILE"
    if [ "${#MOTD_LAUNCHER_IDS[@]}" -eq 0 ] 2>/dev/null; then
      motd_launcher_init_defaults
      motd_launcher_save_items
      return 0
    fi
    motd_launcher_ensure_claude_default || true
    return 0
  fi

  motd_launcher_init_defaults
  motd_launcher_save_items
}

motd_launcher_compact_label() {
  local label="$1"
  local cols="${2:-80}"
  if [ "${cols:-0}" -lt 34 ] 2>/dev/null; then
    case "$label" in
      启动\ *) label="${label#启动 }" ;;
    esac
  fi
  if [ "${cols:-0}" -lt 26 ] 2>/dev/null && [ "${#label}" -gt 14 ] 2>/dev/null; then
    label="${label:0:13}…"
  fi
  printf '%s' "$label"
}

motd_launcher_remove_indices() {
  local raw="$1"
  local part='' idx=0 i=0 want_remove=0
  local -a keep_ids=() keep_kinds=() keep_labels=() keep_paths=()
  local -a remove_flags=()

  for ((i=0; i<${#MOTD_LAUNCHER_IDS[@]}; i++)); do
    remove_flags+=(0)
  done

  raw="${raw// /}"
  IFS=',' read -r -a parts <<<"$raw"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    case "$part" in
      ''|*[!0-9]*)
        return 1
        ;;
    esac
    idx=$((10#$part))
    [ "$idx" -ge 1 ] 2>/dev/null || return 1
    [ "$idx" -le "${#MOTD_LAUNCHER_IDS[@]}" ] 2>/dev/null || return 1
    remove_flags[idx - 1]=1
    want_remove=1
  done

  [ "$want_remove" = "1" ] || return 1

  for ((i=0; i<${#MOTD_LAUNCHER_IDS[@]}; i++)); do
    [ "${remove_flags[$i]}" = "1" ] && continue
    keep_ids+=("${MOTD_LAUNCHER_IDS[$i]}")
    keep_kinds+=("${MOTD_LAUNCHER_KINDS[$i]}")
    keep_labels+=("${MOTD_LAUNCHER_LABELS[$i]}")
    keep_paths+=("${MOTD_LAUNCHER_PATHS[$i]}")
  done

  MOTD_LAUNCHER_IDS=("${keep_ids[@]}")
  MOTD_LAUNCHER_KINDS=("${keep_kinds[@]}")
  MOTD_LAUNCHER_LABELS=("${keep_labels[@]}")
  MOTD_LAUNCHER_PATHS=("${keep_paths[@]}")
  motd_launcher_save_items
  return 0
}

motd_path_resolve_abs() {
  local raw="$1"
  local dir='' base=''

  [ -n "${raw:-}" ] || return 1
  if command -v realpath >/dev/null 2>&1; then
    realpath "$raw" 2>/dev/null && return 0
  fi

  dir="$(dirname -- "$raw" 2>/dev/null || true)"
  base="$(basename -- "$raw" 2>/dev/null || true)"
  [ -n "$dir" ] && [ -n "$base" ] || return 1
  (cd -P -- "$dir" >/dev/null 2>&1 && printf '%s/%s\n' "$PWD" "$base") || return 1
}

motd_launcher_interpreter_for_path() {
  local path="${1:-}"
  local lower=''
  local runner=''

  lower="${path,,}"
  case "$lower" in
    *.sh|*.bash)
      runner="$BASH_BIN"
      ;;
    *.zsh)
      runner="$(command -v zsh 2>/dev/null || true)"
      ;;
    *.py)
      runner="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
      ;;
    *.js|*.mjs|*.cjs)
      runner="$(command -v node 2>/dev/null || true)"
      ;;
    *.lua)
      runner="$(command -v lua 2>/dev/null || true)"
      ;;
    *.rb)
      runner="$(command -v ruby 2>/dev/null || true)"
      ;;
    *.pl)
      runner="$(command -v perl 2>/dev/null || true)"
      ;;
    *.php)
      runner="$(command -v php 2>/dev/null || true)"
      ;;
    *)
      return 1
      ;;
  esac

  [ -n "$runner" ] || return 1
  printf '%s\n' "$runner"
}

motd_launcher_shebang_interpreter_for_path() {
  local path="${1:-}"
  local first_line='' raw_cmd='' runner='' token=''
  local -a shebang_parts=()

  [ -r "$path" ] || return 1
  IFS= read -r first_line <"$path" || true
  case "$first_line" in
    '#!'*)
      raw_cmd="${first_line#\#!}"
      raw_cmd="${raw_cmd#"${raw_cmd%%[![:space:]]*}"}"
      [ -n "$raw_cmd" ] || return 1
      read -r -a shebang_parts <<<"$raw_cmd"
      set -- "${shebang_parts[@]}"
      [ "$#" -gt 0 ] 2>/dev/null || return 1
      runner="$1"
      shift
      case "$runner" in
        */env|env)
          runner=''
          while [ "$#" -gt 0 ] 2>/dev/null; do
            token="$1"
            shift
            case "$token" in
              -*) continue ;;
              *=*) continue ;;
              *)
                runner="$token"
                break
                ;;
            esac
          done
          ;;
      esac
      [ -n "$runner" ] || return 1
      case "$runner" in
        /*)
          [ -x "$runner" ] || return 1
          ;;
        *)
          runner="$(command -v "$runner" 2>/dev/null || true)"
          [ -n "$runner" ] || return 1
          ;;
      esac
      printf '%s\n' "$runner"
      return 0
      ;;
  esac
  return 1
}

motd_launcher_runner_for_path() {
  local path="${1:-}"
  local runner=''

  runner="$(motd_launcher_interpreter_for_path "$path" || true)"
  if [ -n "$runner" ]; then
    printf '%s\n' "$runner"
    return 0
  fi

  runner="$(motd_launcher_shebang_interpreter_for_path "$path" || true)"
  [ -n "$runner" ] || return 1
  printf '%s\n' "$runner"
}

motd_launcher_validate_path() {
  local raw='' resolved='' lower=''

  raw="$(motd_sanitize_field "$1")"
  MOTD_LAUNCHER_VALIDATE_ERROR=''

  [ -n "$raw" ] || {
    MOTD_LAUNCHER_VALIDATE_ERROR='路径不能为空'
    return 1
  }

  case "$raw" in
    /*) ;;
    *)
      MOTD_LAUNCHER_VALIDATE_ERROR='只支持绝对路径'
      return 1
      ;;
  esac

  resolved="$(motd_path_resolve_abs "$raw" 2>/dev/null || true)"
  [ -n "$resolved" ] || {
    MOTD_LAUNCHER_VALIDATE_ERROR='路径不存在或无法解析'
    return 1
  }

  case "$resolved" in
    "$HOME"/*|"$PREFIX"/*) ;;
    *)
      MOTD_LAUNCHER_VALIDATE_ERROR='仅支持 Termux 内路径'
      return 1
      ;;
  esac

  [ -e "$resolved" ] || {
    MOTD_LAUNCHER_VALIDATE_ERROR='目标文件不存在'
    return 1
  }
  [ ! -d "$resolved" ] || {
    MOTD_LAUNCHER_VALIDATE_ERROR='不能添加目录'
    return 1
  }
  [ -f "$resolved" ] || {
    MOTD_LAUNCHER_VALIDATE_ERROR='仅支持普通文件'
    return 1
  }

  lower="${resolved,,}"
  case "$lower" in
    *.sh|*.bash|*.zsh|*.py|*.js|*.mjs|*.cjs|*.lua|*.rb|*.pl|*.php)
      if ! motd_launcher_runner_for_path "$resolved" >/dev/null 2>&1; then
        MOTD_LAUNCHER_VALIDATE_ERROR='当前 Termux 缺少对应解释器'
        return 1
      fi
      printf '%s\n' "$resolved"
      return 0
      ;;
  esac

  if motd_launcher_runner_for_path "$resolved" >/dev/null 2>&1; then
    printf '%s\n' "$resolved"
    return 0
  fi

  if [ -x "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  MOTD_LAUNCHER_VALIDATE_ERROR='后缀不支持，仅支持常见脚本后缀或可执行程序'
  return 1
}

motd_prompt_launcher_path() {
  local prompt="$1"
  local allow_blank="${2:-0}"
  local value='' resolved=''

  while :; do
    value="$(motd_prompt_tty_line "$prompt")"
    value="$(motd_sanitize_field "$value")"

    if [ -z "$value" ]; then
      if [ "$allow_blank" = "1" ]; then
        printf '\n'
        return 0
      fi
      motd_render_launcher_prompt '' '路径不能为空，请输入绝对路径'
      sleep 0.8
      continue
    fi

    resolved="$(motd_launcher_validate_path "$value" || true)"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi

    motd_render_launcher_prompt '' "${MOTD_LAUNCHER_VALIDATE_ERROR:-路径不合法}"
    sleep 1
  done
}

cleanup_state_dir() {
  rm -f \
    "$STATE_DIR"/motd-guard-* \
    "$STATE_DIR"/motd-running-* \
    2>/dev/null || true
}

motd_capture_tty_mode() {
  motd_has_tty || return 0
  [ -n "${MOTD_STTY_SAVED:-}" ] && return 0
  MOTD_STTY_SAVED="$(stty -g <"$TTY_DEV" 2>/dev/null || true)"
}

motd_set_menu_tty_mode() {
  motd_has_tty || return 0
  motd_capture_tty_mode
  stty -echo -icanon min 1 time 0 <"$TTY_DEV" >/dev/null 2>&1 || true
}

motd_restore_tty_mode() {
  motd_has_tty || return 0
  if [ -n "${MOTD_STTY_SAVED:-}" ]; then
    stty "$MOTD_STTY_SAVED" <"$TTY_DEV" >/dev/null 2>&1 || true
    return 0
  fi
  stty sane <"$TTY_DEV" >/dev/null 2>&1 || true
}

motd_flush_tty_input_early() {
  local _ch=''
  local _i=0
  local _idle=0
  motd_has_tty || return 0
  while [ "$_i" -lt 4096 ] 2>/dev/null; do
    if IFS= read -rsn1 -t 0.01 _ch <"$TTY_DEV"; then
      _i=$(( _i + 1 ))
      _idle=0
      continue
    fi
    _idle=$(( _idle + 1 ))
    [ "$_idle" -ge 2 ] && break
  done
}

prune_keep_newest_files() {
  local dir="$1"
  local keep="${2:-10}"
  [[ -d "$dir" ]] || return 0
  [[ "$keep" =~ ^[0-9]+$ ]] || return 0
  (( keep <= 0 )) && return 0

  # List newest-first without glob expansion; remove older files.
  local seen=0 name path
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    path="$dir/$name"
    [[ -f "$path" ]] || continue
    seen=$((seen + 1))
    (( seen > keep )) || continue
    rm -f -- "$path" 2>/dev/null || true
  done < <(LC_ALL=C ls -1t -- "$dir" 2>/dev/null || true)
}

shrink_file_tail_if_over_kb() {
  local path="$1"
  local max_kb="${2:-1024}"
  local keep_kb="${3:-$max_kb}"
  [[ -f "$path" ]] || return 0
  [[ "$max_kb" =~ ^[0-9]+$ ]] || return 0
  [[ "$keep_kb" =~ ^[0-9]+$ ]] || return 0
  (( max_kb <= 0 )) && return 0
  (( keep_kb <= 0 )) && return 0

  local max_bytes=$((max_kb * 1024))
  local keep_bytes=$((keep_kb * 1024))
  local size_bytes=""
  size_bytes="$(wc -c <"$path" 2>/dev/null || true)"
  [[ "$size_bytes" =~ ^[0-9]+$ ]] || return 0
  (( size_bytes <= max_bytes )) && return 0
  (( keep_bytes > max_bytes )) && keep_bytes="$max_bytes"

  local tmp="$LOG_DIR/.trim.$$.$RANDOM"
  if tail -c "$keep_bytes" "$path" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

find_delete_old_files() {
  local dir="$1"
  local days="${2:-7}"
  shift 2 || true
  [[ -d "$dir" ]] || return 0
  [[ "$days" =~ ^[0-9]+$ ]] || return 0
  (( days > 0 )) || return 0
  find "$dir" -type f -mtime +"$days" "$@" -delete 2>/dev/null || true
}

cleanup_project_log_dirs() {
  # projectying owns a separate Aidebug chain; AITermux motd must not prune it.
  find_delete_old_files "$AIDEBUG_DIR/tmp" "${AITERMUX_TMP_LOG_KEEP_DAYS:-7}" || true
  find_delete_old_files "$AIDEBUG_DIR/projectling/terminal output" "${AITERMUX_TERMINAL_LOG_KEEP_DAYS:-14}" \
    \( -name '*.log' -o -name '*.out' -o -name '*.err' -o -name '*.txt' -o -name '*.typescript' -o -name '*.launch.sh' \) || true
  find_delete_old_files "$AIDEBUG_DIR/state/projectling-auto/rounds" "${AITERMUX_STATE_LOG_KEEP_DAYS:-14}" || true
  find "$AIDEBUG_DIR" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
  find "$AIDEBUG_DIR" -type f -mtime +"${AITERMUX_TMP_LOG_KEEP_DAYS:-7}" \
    \( -name '.tmp.*' -o -name '*.tmp' -o -name '*.bak' \) -delete 2>/dev/null || true
}

cleanup_logs_dir() {
  local startup_max_kb="${AITERMUX_STARTUP_LOG_MAX_KB:-1024}"
  local startup_keep_kb="${AITERMUX_STARTUP_LOG_KEEP_KB:-512}"
  local component_max_kb="${AITERMUX_COMPONENT_LOG_MAX_KB:-512}"
  local component_keep_kb="${AITERMUX_COMPONENT_LOG_KEEP_KB:-256}"
  local jsonl_max_kb="${AITERMUX_JSONL_LOG_MAX_KB:-1024}"
  local jsonl_keep_kb="${AITERMUX_JSONL_LOG_KEEP_KB:-512}"
  local component_log jsonl_log
  shrink_file_tail_if_over_kb "$STARTUP_LOG" "$startup_max_kb" "$startup_keep_kb" || true
  for component_log in "$MOTD_LOG" "$LOG_DIR"/projectling.log "$LOG_DIR"/zshrc.log "$LOG_DIR"/bootstrap.log "$LOG_DIR"/events.log; do
    shrink_file_tail_if_over_kb "$component_log" "$component_max_kb" "$component_keep_kb" || true
  done
  for jsonl_log in "$LOG_DIR"/*.jsonl; do
    [ -e "$jsonl_log" ] || continue
    shrink_file_tail_if_over_kb "$jsonl_log" "$jsonl_max_kb" "$jsonl_keep_kb" || true
  done
  rm -f \
    "$LOG_DIR"/launcher.log \
    "$LOG_DIR"/motd-last.err \
    "$LOG_DIR"/motd-last.meta \
    "$LOG_DIR"/motd-guard-* \
    "$LOG_DIR"/motd-running-* \
    "$LOG_DIR"/ying-selfcheck.err \
    "$LOG_DIR"/ying-selfcheck.out \
    2>/dev/null || true
}

# --- Boot Guard + Log Housekeeping -----------------------------------------
TTY_ID="$(tty 2>/dev/null | tr -c 'a-zA-Z0-9' '_' | tr -s '_' '_' | sed 's/^_*//;s/_*$//')"
cleanup_state_dir || true
cleanup_logs_dir || true
cleanup_project_log_dirs || true

if [ -n "${TTY_ID:-}" ]; then
  NOW_SEC="$(date +%s 2>/dev/null || true)"
  if [ -n "${NOW_SEC:-}" ]; then
    LAST_TTY="$(sed -n 's/^last_tty=//p' "$GUARD_STATE_FILE" 2>/dev/null | head -n 1)"
    LAST_SEC="$(sed -n 's/^last_sec=//p' "$GUARD_STATE_FILE" 2>/dev/null | head -n 1)"
    # Avoid double-trigger within the same second on the same tty.
    if [ "$LAST_TTY" = "$TTY_ID" ] && [ "$LAST_SEC" = "$NOW_SEC" ]; then
      exit 0
    fi
    GUARD_TMP="$STATE_DIR/.guard.$$.$RANDOM"
    {
      printf 'last_tty=%s\n' "$TTY_ID"
      printf 'last_sec=%s\n' "$NOW_SEC"
      printf 'updated_at=%s\n' "$(date '+%F %T' 2>/dev/null || echo unknown)"
    } >"$GUARD_TMP" 2>/dev/null && mv -f "$GUARD_TMP" "$GUARD_STATE_FILE" 2>/dev/null || rm -f "$GUARD_TMP" 2>/dev/null || true
  fi
fi

if [ "$DEBUG" != "1" ]; then
  exec 2>>"$STARTUP_LOG"
fi

write_meta_once() {
  [ "$META_WRITTEN" = "1" ] && return 0
  META_WRITTEN=1
  startup_log \
    "motd reason=${META_REASON:-} tty=${TTY_ID:-} anim=${anim##*/} size=${final_size:-na} timeout=${timeout_limit:-na} fps=${FPS:-na} duration=${DURATION:-script-default} hold=${HOLD:-script-default} speed=${SPEED:-script-default} elapsed_ms=${elapsed_ms:-0} rc=${rc:-0}"
  cleanup_logs_dir || true
}

# shellcheck disable=SC2329
cleanup() {
  motd_restore_tty_mode || true
  tput cnorm >/dev/null 2>&1 || true
  tty_printf '\033[0 q' || true
  if [ -t 1 ] && [ "${MOTD_KEEP_SCREEN:-0}" != "1" ]; then
    tty_printf '\033[0m\033[?25h\033[?7h\033[?1049l' || true
    tty_printf '\033[H\033[2J\033[3J' || true
  fi
  write_meta_once || true
}
trap cleanup EXIT INT TERM

pick_random() {
  local -a pool=()
  local f base
  shopt -s nullglob
  for f in "$START_DIR"/*.sh; do
    base="${f##*/}"
    [ -x "$f" ] || continue
    pool+=("$f")
  done
  shopt -u nullglob
  [ "${#pool[@]}" -gt 0 ] || return 1
  printf '%s\n' "${pool[RANDOM % ${#pool[@]}]}"
}

[ -d "$START_DIR" ] || { META_REASON="startboot_missing"; exit 0; }
anim="$(pick_random || true)"
[ -n "${anim:-}" ] && [ -f "$anim" ] || { META_REASON="no_anim"; exit 0; }

# --- Animation Args + Terminal Sizing --------------------------------------
args=(--altscr)
if [ "${AITERMUX_MOTD_COLOR:-1}" = "0" ]; then
  args+=(--no-color)
fi
if [ -n "${AITERMUX_MOTD_ARGS:-}" ]; then
  read -r -a extra <<<"${AITERMUX_MOTD_ARGS}"
  args+=("${extra[@]}")
fi

motd_detect_tty_size() {
  local rows_raw="" cols_raw="" stty_out=""

  if motd_has_tty && stty_out="$(stty size <"$TTY_DEV" 2>/dev/null)"; then
    rows_raw="${stty_out%% *}"
    cols_raw="${stty_out##* }"
  fi

  if ! motd_is_uint "${cols_raw:-}"; then
    cols_raw="$(tput cols 2>/dev/null || echo 80)"
  fi
  if ! motd_is_uint "${rows_raw:-}"; then
    rows_raw="$(tput lines 2>/dev/null || echo 24)"
  fi

  if ! motd_is_uint "${cols_raw:-}" || [ "${cols_raw:-0}" -le 0 ] 2>/dev/null; then
    cols_raw=80
  fi
  if ! motd_is_uint "${rows_raw:-}" || [ "${rows_raw:-0}" -le 0 ] 2>/dev/null; then
    rows_raw=24
  fi
  printf '%s %s\n' "$rows_raw" "$cols_raw"
}

get_term_size_safe() {
  local cols_raw="" rows_raw="" cols_safe=""
  read -r rows_raw cols_raw <<<"$(motd_detect_tty_size)"

  cols_safe="$cols_raw"
  if [ -n "${cols_safe:-}" ] && [ "$cols_safe" -gt 2 ] 2>/dev/null; then
    cols_safe=$((cols_safe - 1))
  fi
  [ -n "${cols_safe:-}" ] || cols_safe=80
  [ -n "${rows_raw:-}" ] || rows_raw=24
  printf '%sx%s\n' "$cols_safe" "$rows_raw"
}

wait_term_size_stable() {
  local last="" same=0 key _i
  for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    key="$(get_term_size_safe)"
    if [ "$key" = "$last" ]; then
      same=$((same + 1))
    else
      same=0
      last="$key"
    fi
    if [ "$same" -ge 2 ]; then
      printf '%s\n' "$key"
      return 0
    fi
    sleep 0.05
  done
  printf '%s\n' "${last:-80x24}"
}

motd_redraw_size_key() {
  local size_in="${1:-}"
  local cols='' rows=''

  if ! motd_is_size_spec "$size_in"; then
    size_in="$(get_term_size_safe)"
  fi
  cols="${size_in%x*}"
  rows="${size_in#*x}"
  if [ "${AITERMUX_MOTD_REDRAW_ON_HEIGHT:-0}" = "1" ]; then
    printf '%sx%s\n' "$cols" "$rows"
  else
    printf '%s\n' "$cols"
  fi
}

motd_size_cols() {
  local size_in="${1:-}"
  if ! motd_is_size_spec "$size_in"; then
    size_in="$(get_term_size_safe)"
  fi
  printf '%s\n' "${size_in%x*}"
}

motd_size_rows() {
  local size_in="${1:-}"
  if ! motd_is_size_spec "$size_in"; then
    size_in="$(get_term_size_safe)"
  fi
  printf '%s\n' "${size_in#*x}"
}

motd_launcher_should_compact() {
  local rows="${1:-24}"
  local base_rows="${2:-${MOTD_LAUNCHER_BASE_ROWS:-0}}"
  local compact_rows="${AITERMUX_MOTD_COMPACT_ROWS:-28}"
  local drop_rows="${AITERMUX_MOTD_KEYBOARD_DROP_ROWS:-5}"

  [ "${AITERMUX_MOTD_FORCE_FULL:-0}" = "1" ] && return 1
  [ "${AITERMUX_MOTD_LAUNCHER_CARD:-1}" = "0" ] && return 0
  if [ "${rows:-24}" -lt "$compact_rows" ] 2>/dev/null; then
    return 0
  fi
  if [ "${base_rows:-0}" -gt 0 ] 2>/dev/null && [ "$((base_rows - rows))" -ge "$drop_rows" ] 2>/dev/null; then
    return 0
  fi
  return 1
}

motd_update_launcher_compact_state() {
  local size_in="${1:-}"
  local rows=24
  rows="$(motd_size_rows "$size_in")"

  if [ "${MOTD_LAUNCHER_BASE_ROWS:-0}" -le 0 ] 2>/dev/null || [ "${rows:-0}" -gt "${MOTD_LAUNCHER_BASE_ROWS:-0}" ] 2>/dev/null; then
    MOTD_LAUNCHER_BASE_ROWS="$rows"
  fi

  if motd_launcher_should_compact "$rows" "${MOTD_LAUNCHER_BASE_ROWS:-$rows}"; then
    MOTD_FORCE_COMPACT=1
  else
    MOTD_FORCE_COMPACT=0
  fi
}

motd_launcher_compact_value_for_size() {
  local size_in="${1:-}"
  local rows=24
  local base_rows="${MOTD_LAUNCHER_BASE_ROWS:-0}"

  if ! motd_is_size_spec "$size_in"; then
    size_in="$(get_term_size_safe)"
  fi
  rows="$(motd_size_rows "$size_in")"
  if [ "${base_rows:-0}" -le 0 ] 2>/dev/null; then
    base_rows="$rows"
  fi

  if motd_launcher_should_compact "$rows" "$base_rows"; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

motd_mark_winch_dirty() {
  MOTD_WINCH_DIRTY=1
}

motd_launcher_capture_layout_state() {
  local size_in="${1:-}"
  if ! motd_is_size_spec "$size_in"; then
    size_in="$(get_term_size_safe)"
  fi
  motd_update_launcher_compact_state "$size_in"
  MOTD_LAUNCHER_SIZE="$size_in"
  MOTD_LAUNCHER_SIZE_KEY="$(motd_redraw_size_key "$size_in")"
  MOTD_LAUNCHER_ROWS="$(motd_size_rows "$size_in")"
  MOTD_VISIBLE_ROWS="$MOTD_LAUNCHER_ROWS"
}

motd_launcher_needs_redraw() {
  local size_in="${1:-}"
  local old_compact="${MOTD_FORCE_COMPACT:-0}"
  local old_key="${MOTD_LAUNCHER_SIZE_KEY:-}"
  local old_rows="${MOTD_LAUNCHER_ROWS:-0}"

  motd_launcher_capture_layout_state "$size_in"
  [ "${MOTD_WINCH_DIRTY:-0}" = "1" ] && return 0
  [ "${MOTD_LAUNCHER_SIZE_KEY:-}" != "$old_key" ] && return 0
  [ "${AITERMUX_MOTD_REDRAW_ON_HEIGHT:-0}" = "1" ] && [ "${MOTD_LAUNCHER_ROWS:-0}" != "$old_rows" ] && return 0
  [ "${MOTD_FORCE_COMPACT:-0}" != "$old_compact" ] && return 0
  return 1
}

motd_launcher_commit_redraw_state() {
  MOTD_WINCH_DIRTY=0
}

motd_redraw_launcher_screen_static() {
  local selected="${1:-${MOTD_MENU_SELECTED:-1}}"
  local render_card="${2:-1}"
  local total=1

  motd_launcher_menu_styles_init launcher
  total="$(motd_launcher_menu_total)"
  selected="$(motd_clamp_menu_selection "$selected" "$total")"
  MOTD_MENU_SELECTED="$selected"
  MOTD_LAST_CARD_TOP_ROW=0
  MOTD_LAST_CARD_HEIGHT=0
  MOTD_LAST_MENU_TOP_ROW=0
  MOTD_LAST_MENU_AFTER_ROW=0
  MOTD_HIDDEN_CARD_TOP_ROW=0
  MOTD_HIDDEN_CARD_HEIGHT=0
  motd_render_launcher_frame final
  motd_render_launcher_menu_static "$selected" "$render_card" 1
}

motd_launcher_handle_height_resize() {
  local size_in="${1:-}"
  local selected="${2:-${MOTD_MENU_SELECTED:-1}}"
  local old_size="${MOTD_LAUNCHER_SIZE:-}"
  local old_cols='' old_rows='' new_cols='' new_rows=''
  local old_compact="${MOTD_FORCE_COMPACT:-0}"

  motd_is_size_spec "$size_in" || return 1
  motd_is_size_spec "$old_size" || return 1

  old_cols="${old_size%x*}"
  old_rows="${old_size#*x}"
  new_cols="${size_in%x*}"
  new_rows="${size_in#*x}"

  # A keyboard open/close in Termux is normally a height-only WINCH. Ignore
  # intermediate height noise, but rebuild once when the compact/full state
  # flips so stale rows and the TERMUX art cannot survive from the old layout.
  [ "$new_cols" = "$old_cols" ] || return 1
  if [ "$new_rows" = "$old_rows" ] 2>/dev/null && [ "${MOTD_WINCH_DIRTY:-0}" = "0" ]; then
    return 1
  fi

  motd_launcher_capture_layout_state "$size_in"
  if [ "$new_rows" = "$old_rows" ] 2>/dev/null && [ "${MOTD_FORCE_COMPACT:-0}" = "$old_compact" ]; then
    motd_launcher_commit_redraw_state
    return 0
  fi

  if [ "${MOTD_FORCE_COMPACT:-0}" = "$old_compact" ]; then
    motd_launcher_commit_redraw_state
    return 0
  fi

  tput civis >/dev/null 2>&1 || true
  motd_redraw_scan_transition
  motd_sync_begin
  motd_redraw_launcher_screen_static "$selected" 0
  motd_sync_end
  if [ "${MOTD_FORCE_COMPACT:-0}" = "0" ] && [ "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" -gt 0 ] 2>/dev/null; then
    motd_render_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-0}" || true
    MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
    MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
  fi
  MOTD_INPUT_DIRTY=0
  motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
  motd_launcher_capture_layout_state "$size_in"
  motd_launcher_commit_redraw_state
  return 0
}

cap_size_if_needed() {
  local size_in="$1"
  if ! motd_is_size_spec "$size_in"; then
    printf '80x24\n'
    return 0
  fi
  local cols="${size_in%x*}"
  local rows="${size_in#*x}"
  if [ "${cols:-0}" -le 0 ] 2>/dev/null; then
    cols=80
  fi
  if [ "${rows:-0}" -le 0 ] 2>/dev/null; then
    rows=24
  fi
  local max_cols="${AITERMUX_MOTD_MAX_COLS:-0}"
  local max_rows="${AITERMUX_MOTD_MAX_ROWS:-0}"

  if [ "${AITERMUX_MOTD_LIGHT:-0}" = "1" ]; then
    [ "$max_cols" = "0" ] && max_cols=70
    [ "$max_rows" = "0" ] && max_rows=24
  fi

  if motd_is_uint "$max_cols" && [ "$max_cols" -gt 0 ] 2>/dev/null; then
    if [ "$cols" -gt "$max_cols" ] 2>/dev/null; then
      cols="$max_cols"
    fi
  fi
  if motd_is_uint "$max_rows" && [ "$max_rows" -gt 0 ] 2>/dev/null; then
    if [ "$rows" -gt "$max_rows" ] 2>/dev/null; then
      rows="$max_rows"
    fi
  fi
  printf '%sx%s\n' "$cols" "$rows"
}

has_size_arg=0
for a in "${args[@]}"; do
  if [ "$a" = "--size" ] || [ "$a" = "-s" ]; then
    has_size_arg=1
    break
  fi
done
if [ "$has_size_arg" = "0" ]; then
  stable_size="$(wait_term_size_stable)"
  final_size="$(cap_size_if_needed "$stable_size")"
  args+=(--size "$final_size")
else
  final_size=""
fi

# Global animation tuning (startboot scripts honor these env vars).
# 说明：默认提升到 15 FPS，减少拖拍和卡顿感；其它节奏参数默认留空，让各动画脚本使用自己的默认值。
export FPS="${AITERMUX_MOTD_FPS:-15}"
export DURATION="${AITERMUX_MOTD_DURATION:-}"
export HOLD="${AITERMUX_MOTD_HOLD:-}"
export SPEED="${AITERMUX_MOTD_SPEED:-}"

normalize_timeout() {
  local t="$1"
  if [ -z "$t" ]; then
    printf '0'
    return 0
  fi
  if [[ "$t" =~ ^0+([.][0]+)?$ ]]; then
    printf '0'
    return 0
  fi
  if [[ "$t" =~ [a-zA-Z]$ ]]; then
    printf '%s' "$t"
  else
    printf '%ss' "$t"
  fi
}

# 默认超时要足够大：避免动画在弱机上被 timeout “腰斩”，导致抽帧/节奏错乱。
timeout_start="$(normalize_timeout "${AITERMUX_MOTD_TIMEOUT_START:-12}")"
timeout_limit="$(normalize_timeout "${AITERMUX_MOTD_TIMEOUT:-$timeout_start}")"

motd_set_menu_tty_mode || true
motd_flush_tty_input_early || true

start_ns="$(date +%s%N 2>/dev/null || echo 0)"
rc=0
if command -v timeout >/dev/null 2>&1 && [ "$timeout_limit" != "0" ]; then
  timeout_opts=()
  timeout_help="$(timeout --help 2>/dev/null || true)"
  [[ "$timeout_help" == *"--foreground"* ]] && timeout_opts+=(-f)
  timeout "${timeout_opts[@]}" -k 0.6s "$timeout_limit" "$BASH_BIN" "$anim" "${args[@]}" || rc=$?
else
  "$BASH_BIN" "$anim" "${args[@]}" || rc=$?
fi

end_ns="$(date +%s%N 2>/dev/null || echo 0)"
elapsed_ms=0
if [ "$start_ns" != "0" ] && [ "$end_ns" != "0" ] 2>/dev/null; then
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
fi

motd_term_cols() {
  local rows_raw="" cols_raw=""
  read -r rows_raw cols_raw <<<"$(motd_detect_tty_size)"

  if [ "$cols_raw" -le 20 ] 2>/dev/null; then
    cols_raw=80
  fi

  printf '%s' "$cols_raw"
}

motd_term_rows() {
  local rows_raw="" cols_raw=""
  read -r rows_raw cols_raw <<<"$(motd_detect_tty_size)"

  printf '%s' "$rows_raw"
}

motd_print_center_ascii_at() {
  local row="$1"
  local line="$2"
  local style="${3:-}"
  local clear_row="${4:-1}"
  local reset='\033[0m'
  local cols pad

  cols="$(motd_term_cols)"
  pad=$(( (cols - ${#line}) / 2 ))
  if [ "$pad" -lt 0 ] 2>/dev/null; then
    pad=0
  fi
  motd_move_cursor_to "$row" 1
  if [ "$clear_row" = "1" ]; then
    tty_printf '\033[2K\r'
  else
    tty_printf '\r'
  fi
  if [ -n "$style" ]; then
    tty_printf '%*s%b%s%b' "$pad" '' "$style" "$line" "$reset"
  else
    tty_printf '%*s%s' "$pad" '' "$line"
  fi
}

motd_print_ascii_at_col() {
  local row="$1"
  local col="$2"
  local line="$3"
  local style="${4:-}"
  local clear_row="${5:-1}"
  local reset='\033[0m'

  [ "${col:-0}" -ge 1 ] 2>/dev/null || col=1
  motd_move_cursor_to "$row" "$col"
  if [ "$clear_row" = "1" ]; then
    tty_printf '\033[2K\r\033[%sG' "$col"
  fi
  if [ -n "$style" ]; then
    tty_printf '%b%s%b' "$style" "$line" "$reset"
  else
    tty_printf '%s' "$line"
  fi
}

motd_ascii_right_pad() {
  local line="$1"
  local target_width="${2:-0}"
  local len=0
  local pad=0

  len="${#line}"
  if [ "${target_width:-0}" -gt "$len" ] 2>/dev/null; then
    pad=$((target_width - len))
    printf '%s%*s' "$line" "$pad" ''
    return 0
  fi
  printf '%s' "$line"
}

motd_launcher_art_left_col() {
  local cols="${1:-80}"
  local art_width="${2:-53}"
  local shadow_cols="${3:-1}"
  local offset="${AITERMUX_MOTD_ART_OFFSET:-0}"
  local composite_width=54
  local col=1

  motd_is_uint "$cols" || cols=80
  motd_is_uint "$art_width" || art_width=53
  motd_is_uint "$shadow_cols" || shadow_cols=1
  case "$offset" in
    -[0-9]*|[0-9]*) ;;
    *) offset=0 ;;
  esac
  composite_width=$((art_width + shadow_cols))
  col=$(( (cols - composite_width) / 2 + 1 + offset ))
  if [ "$col" -lt 1 ] 2>/dev/null; then
    col=1
  fi
  printf '%s' "$col"
}

motd_art_style() {
  local variant="$1"
  local line_no="$2"
  case "${variant}:${line_no}" in
    shadow:*)
      printf '\033[2;38;2;255;0;153m'
      ;;
    phase_a:1|phase_a:6)
      printf '\033[1;38;2;255;92;218m'
      ;;
    phase_a:2|phase_a:5)
      printf '\033[1;38;2;170;120;255m'
      ;;
    phase_a:3|phase_a:4)
      printf '\033[1;38;2;0;238;255m'
      ;;
    phase_b:1|phase_b:6)
      printf '\033[1;38;2;0;255;229m'
      ;;
    phase_b:2|phase_b:5)
      printf '\033[1;38;2;255;255;255m'
      ;;
    phase_b:3|phase_b:4)
      printf '\033[1;38;2;255;92;218m'
      ;;
    final:1)
      printf '\033[1;38;2;0;255;229m'
      ;;
    final:2)
      printf '\033[1;38;2;114;198;255m'
      ;;
    final:3)
      printf '\033[1;38;2;255;92;218m'
      ;;
    final:4)
      printf '\033[1;38;2;186;126;255m'
      ;;
    final:5)
      printf '\033[1;38;2;255;92;218m'
      ;;
    final:6)
      printf '\033[1;38;2;255;255;255m'
      ;;
    *)
      printf '\033[1;97m'
      ;;
  esac
}

motd_title_style() {
  local variant="$1"
  case "$variant" in
    shadow)
      printf '\033[2;38;2;255;0;153m'
      ;;
    phase_a)
      printf '\033[1;38;2;255;92;218m'
      ;;
    phase_b)
      printf '\033[1;38;2;0;255;229m'
      ;;
    final)
      printf '\033[1;38;2;0;255;229m'
      ;;
    *)
      printf '\033[1;97m'
      ;;
  esac
}

motd_draw_launcher_art_at() {
  local variant="$1"
  local start_row="$2"
  local with_shadow="${3:-0}"
  local clear_row="${4:-1}"
  local left_col="${5:-0}"
  local art style idx=0 row=0 line=''
  local art_width=53
  local draw_col=1

  if [ "${left_col:-0}" -lt 1 ] 2>/dev/null; then
    left_col="$(motd_launcher_art_left_col "$(motd_term_cols)" "$art_width" 0)"
  fi

  while IFS= read -r art; do
    idx=$((idx + 1))
    row=$((start_row + idx - 1))
    style="$(motd_art_style "$variant" "$idx")"
    art="$(motd_ascii_right_pad "$art" "$art_width")"
    if [ "$with_shadow" = "1" ]; then
      draw_col=$((left_col + 1))
      line="${art}"
    else
      draw_col="$left_col"
      line="${art} "
    fi
    motd_print_ascii_at_col "$row" "$draw_col" "$line" "$style" "$clear_row"
  done <<'EOF'
████████╗███████╗██████╗ ███╗   ███╗██╗   ██╗██╗  ██╗
╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║   ██║╚██╗██╔╝
   ██║   █████╗  ██████╔╝██╔████╔██║██║   ██║ ╚███╔╝
   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║   ██║ ██╔██╗
   ██║   ███████╗██║  ██║██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
EOF
}

motd_draw_launcher_art_stack_at() {
  local variant="$1"
  local start_row="$2"
  local cols=80
  local left_col=1

  cols="$(motd_term_cols)"
  left_col="$(motd_launcher_art_left_col "$cols" 53 0)"
  motd_draw_launcher_art_at shadow "$start_row" 1 1 "$left_col"
  motd_draw_launcher_art_at "$variant" "$start_row" 0 0 "$left_col"
}

motd_print_launcher_title_at() {
  local variant="$1"
  local title="${2:-$MOTD_LAUNCHER_TITLE}"
  local row="${3:-1}"
  local main_style reset='\033[0m'
  main_style="$(motd_title_style "$variant")"
  motd_move_cursor_to "$row" 1
  tty_printf '\033[2K\r  %b%s%b\033[K' "$main_style" "$title" "$reset"
}

motd_normalize_terminal_state() {
  tty_printf '\033[0m\033[?25h\033[?7h\033[r\033[?6l' || true
}

motd_force_exit_altscr() {
  # 防御：若开屏动画被 timeout SIGKILL 打断，可能来不及执行 trap 清理，从而卡在备用屏。
  # 在进入 Launcher 画面前强制回到主屏，避免“整体下沉/错位/花屏”。
  tty_printf '\033[?1049l\033[?1047l\033[?47l' || true
}

motd_prepare_screen_canvas() {
  motd_force_exit_altscr
  motd_normalize_terminal_state
  tty_printf '\033[H\033[2J\033[3J'
}

motd_redraw_scan_transition() {
  local cols=80 rows=24 start_row=2 end_row=0 span=0 row=0 i=0
  local delay="${AITERMUX_MOTD_REDRAW_SCAN_DELAY:-0.006}"
  local style=$'\033[2;38;2;0;255;229m'
  local reset=$'\033[0m'
  local line='  ▪▪▪───────── ───── ───  - - · ·'

  [ "${AITERMUX_MOTD_REDRAW_SCAN:-1}" != "0" ] || return 0
  motd_has_tty || return 0
  rows="$(motd_term_rows)"
  cols="$(motd_term_cols)"
  [ "${rows:-0}" -ge "${MOTD_REDRAW_SCAN_MIN_ROWS:-18}" ] 2>/dev/null || return 0
  [ "${cols:-0}" -ge 38 ] 2>/dev/null || return 0
  motd_force_exit_altscr
  motd_normalize_terminal_state
  tty_printf '\033[H\033[2J\033[3J'

  if [ "${MOTD_LAST_CARD_TOP_ROW:-0}" -gt 0 ] 2>/dev/null; then
    start_row="$MOTD_LAST_CARD_TOP_ROW"
  elif [ "${MOTD_MENU_RENDER_TOP_ROW:-0}" -gt 0 ] 2>/dev/null; then
    start_row="$MOTD_MENU_RENDER_TOP_ROW"
  elif [ "${MOTD_FRAME_TITLE_ROW:-0}" -gt 0 ] 2>/dev/null; then
    start_row="$MOTD_FRAME_TITLE_ROW"
  fi

  end_row="${MOTD_LAST_MENU_AFTER_ROW:-0}"
  if [ "${end_row:-0}" -le "$start_row" ] 2>/dev/null; then
    end_row=$((rows - MOTD_SCREEN_BOTTOM_GAP))
  fi
  if [ "$end_row" -gt "$rows" ] 2>/dev/null; then
    end_row="$rows"
  fi
  span=$((end_row - start_row))
  [ "$span" -gt 2 ] 2>/dev/null || return 0

  if [ "$cols" -lt 48 ] 2>/dev/null; then
    line='  ▪▪▪──── ─── ──  · ·'
  fi

  for i in 0 1 2; do
    row=$((start_row + (span * i) / 2))
    [ "$row" -ge 1 ] 2>/dev/null && [ "$row" -le "$rows" ] 2>/dev/null || continue
    motd_move_cursor_to "$row" 1
    tty_printf '\033[2K\r%b%s%b' "$style" "$line" "$reset"
    sleep "$delay"
  done
}

motd_render_launcher_frame() {
  local variant="$1"
  local title="${2:-$MOTD_LAUNCHER_TITLE}"
  motd_prepare_screen_canvas
  if [ "${MOTD_FRAME_ART_ENABLED:-0}" = "1" ] 2>/dev/null && [ "${MOTD_FRAME_ART_TOP_ROW:-0}" -gt 0 ] 2>/dev/null; then
    motd_draw_launcher_art_stack_at "$variant" "${MOTD_FRAME_ART_TOP_ROW}"
  fi
  motd_print_launcher_title_at "$variant" "$title" "${MOTD_FRAME_TITLE_ROW:-2}"
}

motd_path_prepend_once() {
  local dir="$1"
  [ -n "${dir:-}" ] || return 0
  case ":${PATH:-}:" in
    *":$dir:"*) ;;
    *) PATH="$dir:${PATH:-}" ;;
  esac
}

motd_refresh_launcher_env() {
  motd_path_prepend_once "$ROOT_DIR/bin"
  motd_path_prepend_once "$HOME/.local/bin"
}

motd_projectling_runner() {
  printf '%s\n' "$ROOT_DIR/projectling/run.sh"
}

motd_has_projectling() {
  [ -x "$ROOT_DIR/projectling/run.sh" ]
}

motd_ensure_projectling_now() {
  motd_has_projectling && return 0
  motd_bootstrap_component_now projectling || return 1
  motd_has_projectling
}

motd_reroll_projectling_card() {
  local runner=""

  motd_ensure_projectling_now || return 1
  runner="$(motd_projectling_runner)"
  [ -x "$runner" ] || return 1
  "$runner" reroll-role >/dev/null 2>&1 || return 1
  MOTD_LAUNCHER_CARD_SEED=''
  MOTD_CARD_CACHE_KEY=''
  MOTD_CARD_CACHE_LINES=()
  return 0
}

motd_open_projectling_settings() {
  local tab="${1:-root}"
  local runner=""
  if ! motd_ensure_projectling_now; then
    tty_printf '[launcher] 未找到 projectling settings 入口。\n'
    return 0
  fi
  runner="$(motd_projectling_runner)"
  [ -x "$runner" ] || {
    tty_printf '[launcher] 未找到 projectling settings 入口。\n'
    return 0
  }

  motd_restore_tty_mode || true
  tty_printf '\n'
  motd_tty_run "$ROOT_DIR/projectling" "$runner" shell-settings --tab "$tab"
  return $?
}

motd_render_launcher_card_lines() {
  local top_row="$1"
  shift
  local row="$top_row"
  local printed=0
  local line=''
  local max_height="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
  local buffer=''
  local segment=''

  for line in "$@"; do
    if [ "$max_height" -gt 0 ] 2>/dev/null && [ "$printed" -ge "$max_height" ] 2>/dev/null; then
      break
    fi
    if motd_row_visible "$row"; then
      printf -v segment '\033[%s;1H\033[2K\r%s' "$row" "$line"
      buffer+="$segment"
    fi
    row=$((row + 1))
    printed=$((printed + 1))
  done

  while [ "$printed" -lt "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" ] 2>/dev/null; do
    if motd_row_visible "$row"; then
      printf -v segment '\033[%s;1H\033[2K\r' "$row"
      buffer+="$segment"
    fi
    row=$((row + 1))
    printed=$((printed + 1))
  done

  [ -n "$buffer" ] && tty_printf '%s' "$buffer"
}

motd_render_launcher_card_fallback() {
  local top_row="$1"
  local row="$top_row"
  local printed=0

  motd_render_launcher_menu_text_row "$row" '  ● AI   ◈  为你分配终端伙伴'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '  ● PEN  ⟡  SIGNAL LINK'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" ''
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '  ✧ 角色池待装填  /  Roster Pending'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" ''
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '  ✧ projectling 未接入，当前展示回退占位卡。'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '    启动链路已切到稳定模式，不会阻塞进入主页。'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '    等角色池恢复后，这里会重新展示完整人物志。'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '    当前仍会优先保证菜单交互与进入主页的稳定性。'
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" ''
  row=$((row + 1))
  motd_render_launcher_menu_text_row "$row" '  ● 稳定回退模式 剩余 -- 分钟'
  row=$((row + 1))
  printed=11

  while [ "$printed" -lt "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" ] 2>/dev/null; do
    motd_clear_row_at "$row"
    row=$((row + 1))
    printed=$((printed + 1))
  done
}

motd_render_launcher_card() {
  local top_row="$1"
  local reroll="${2:-0}"
  local cols=80
  local card_height=0
  local runner=""
  local line=''
  local cache_key=''
  local -a card_cmd=()
  local -a card_lines=()

  cols="$(motd_term_cols)"
  card_height="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
  runner="$(motd_projectling_runner)"
  cache_key="${cols}:${card_height}:${MOTD_LAUNCHER_CARD_SEED:-current}"

  if [ "$reroll" != "1" ] && [ "$cache_key" = "${MOTD_CARD_CACHE_KEY:-}" ] && [ "${#MOTD_CARD_CACHE_LINES[@]}" -gt 0 ] 2>/dev/null; then
    motd_sync_begin
    motd_render_launcher_card_lines "$top_row" "${MOTD_CARD_CACHE_LINES[@]}"
    motd_sync_end
    return 0
  fi

  if [ -x "$runner" ] && [ "$card_height" -gt 0 ] 2>/dev/null; then
    card_cmd=("$runner" render-motd-card --width "$cols")
    card_cmd+=(--max-lines "$card_height" --settings-label '')
    if [ "$reroll" = "1" ]; then
      card_cmd+=(--reroll)
    elif [ -n "${MOTD_LAUNCHER_CARD_SEED:-}" ]; then
      card_cmd+=(--seed "$MOTD_LAUNCHER_CARD_SEED")
    fi
    while IFS= read -r line; do
      card_lines+=("$line")
    done < <("${card_cmd[@]}" 2>/dev/null || true)
  fi

  if [ "${#card_lines[@]}" -gt 0 ] 2>/dev/null; then
    MOTD_LAUNCHER_CARD_SEED=''
    MOTD_CARD_CACHE_KEY="$cache_key"
    MOTD_CARD_CACHE_LINES=("${card_lines[@]}")
    motd_sync_begin
    motd_render_launcher_card_lines "$top_row" "${card_lines[@]}"
    motd_sync_end
    return 0
  fi

  MOTD_CARD_CACHE_KEY=''
  MOTD_CARD_CACHE_LINES=()
  motd_sync_begin
  motd_render_launcher_card_fallback "$top_row"
  motd_sync_end
}

motd_animate_launcher_card() {
  local top_row="$1"
  local reroll="${2:-0}"
  local final_card="${3:-0}"
  local cols=80
  local current_cols=0
  local runner=""
  local line=''
  local delay="${AITERMUX_MOTD_LAUNCHER_CARD_DELAY:-0.022}"
  local frames="${AITERMUX_MOTD_LAUNCHER_CARD_FRAMES:-5}"
  local rendered=0
  local initial_compact="${MOTD_FORCE_COMPACT:-0}"
  local current_compact=0
  local current_size=''
  local -a anim_cmd=()
  local -a frame_lines=()

  MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=0
  cols="$(motd_term_cols)"
  runner="$(motd_projectling_runner)"
  [ -x "$runner" ] || return 1
  anim_cmd=("$runner" animate-motd-card --width "$cols" --frames "$frames")
  if [ "$reroll" = "1" ]; then
    anim_cmd+=(--reroll)
  elif [ -n "${MOTD_LAUNCHER_CARD_SEED:-}" ]; then
    anim_cmd+=(--seed "$MOTD_LAUNCHER_CARD_SEED")
  fi
  if [ "$final_card" = "1" ]; then
    anim_cmd+=(--final-card --max-lines "${MOTD_LAUNCHER_CARD_HEIGHT:-12}" --settings-label '')
  fi

  while IFS= read -r line; do
    if [ "$line" = $'\f' ]; then
      if [ "${#frame_lines[@]}" -gt 0 ] 2>/dev/null; then
        if [ "${MOTD_WINCH_DIRTY:-0}" = "1" ]; then
          current_cols="$(motd_term_cols)"
          if [ "$current_cols" != "$cols" ]; then
            MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=1
            return 1
          fi
          current_size="$(get_term_size_safe)"
          current_compact="$(motd_launcher_compact_value_for_size "$current_size")"
          if [ "$current_compact" != "$initial_compact" ]; then
            MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=1
            return 1
          fi
        fi
        motd_render_launcher_card_lines "$top_row" "${frame_lines[@]}"
        frame_lines=()
        rendered=1
        sleep "$delay"
      fi
      continue
    fi
    frame_lines+=("$line")
  done < <("${anim_cmd[@]}" 2>/dev/null || true)

  if [ "${#frame_lines[@]}" -gt 0 ] 2>/dev/null; then
    if [ "${MOTD_WINCH_DIRTY:-0}" = "1" ]; then
      current_cols="$(motd_term_cols)"
      if [ "$current_cols" != "$cols" ]; then
        MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=1
        return 1
      fi
      current_size="$(get_term_size_safe)"
      current_compact="$(motd_launcher_compact_value_for_size "$current_size")"
      if [ "$current_compact" != "$initial_compact" ]; then
        MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=1
        return 1
      fi
    fi
    motd_render_launcher_card_lines "$top_row" "${frame_lines[@]}"
    if [ "$final_card" = "1" ]; then
      MOTD_LAUNCHER_CARD_SEED=''
      MOTD_CARD_CACHE_KEY="${cols}:${MOTD_LAUNCHER_CARD_HEIGHT:-0}:current"
      MOTD_CARD_CACHE_LINES=("${frame_lines[@]}")
    fi
    rendered=1
  fi

  [ "$rendered" = "1" ]
}

motd_show_launcher_intro() {
  local selected="${1:-1}"
  local total=1

  motd_launcher_menu_styles_init launcher
  total="$(motd_launcher_menu_total)"
  selected="$(motd_clamp_menu_selection "$selected" "$total")"
  MOTD_MENU_SELECTED="$selected"
  motd_render_launcher_frame final
  if [ "${AITERMUX_MOTD_LAUNCHER_CARD_ANIM:-1}" != "0" ] && [ "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" -ge 8 ] 2>/dev/null; then
    motd_render_launcher_menu_static "$selected" 0
    if motd_animate_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-1}" 0 1; then
      MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
      MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
      return 0
    fi
    motd_render_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-1}" || true
    MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
    MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
    return 0
  fi
  motd_render_launcher_menu_static "$selected" 1
}

motd_launcher_log() {
  startup_log "launcher $*"
  cleanup_logs_dir || true
}

motd_bootstrap_path() {
  printf '%s\n' "$ROOT_DIR/bin/aitermux-bootstrap"
}

motd_bootstrap_component_label() {
  case "${1:-}" in
    codex) printf '%s\n' 'CODEX' ;;
    gemini) printf '%s\n' 'Gemini' ;;
    claude) printf '%s\n' 'Claude Code' ;;
    projectying) printf '%s\n' 'PROJECT 萤' ;;
    projectling) printf '%s\n' 'PROJECT 凌' ;;
    *) printf '%s\n' "${1:-组件}" ;;
  esac
}

motd_bootstrap_state_reason() {
  local component="$1"
  local state_file="$ROOT_DIR/.state/bootstrap/${component}.state"
  [ -f "$state_file" ] || return 1
  sed -n 's/^reason=//p' "$state_file" 2>/dev/null | head -n 1
}

motd_bootstrap_latest_line() {
  local log_file="$1"
  local line=""
  [ -f "$log_file" ] || return 1
  line="$(awk 'NF { line=$0 } END { print line }' "$log_file" 2>/dev/null | tail -n 1)"
  line="$(printf '%s' "$line" | sed -E $'s/\033\\[[0-9;?]*[ -/]*[@-~]//g' 2>/dev/null)"
  line="$(printf '%s' "$line" | tr -d '\000-\010\013\014\016-\037\177' 2>/dev/null)"
  motd_sanitize_field "$line"
}

motd_clip_status_text() {
  local text="${1:-}"
  local cols max
  cols="$(motd_term_cols)"
  max=$((cols - 4))
  [ "$max" -ge 20 ] 2>/dev/null || max=76
  if [ "${#text}" -gt "$max" ] 2>/dev/null; then
    text="${text:0:$((max - 3))}..."
  fi
  printf '%s' "$text"
}

motd_render_launcher_status() {
  local text="${1:-}"
  local style="${2:-${MOTD_MENU_FG_CYAN:-}}"
  local row="${MOTD_MENU_STATUS_ROW:-1}"
  local reset="${MOTD_MENU_RESET:-}"

  text="$(motd_clip_status_text "$text")"
  if [ -n "$style" ]; then
    motd_render_launcher_menu_text_row "$row" "  ${style}${text}${reset}"
  else
    motd_render_launcher_menu_text_row "$row" "  $text"
  fi
}

motd_bootstrap_component_now() {
  local component="$1"
  local mode="${2:-install}"
  local bootstrap=""
  local label=""
  local action_label="安装"
  local run_dir="" run_log="" rc_file=""
  local pid=0 rc=1 tick=0 spinner='-' latest="" reason="" summary=""

  [ -n "${component:-}" ] || return 1
  case "$mode" in
    update) action_label="更新" ;;
    *) mode="install"; action_label="安装" ;;
  esac
  label="$(motd_bootstrap_component_label "$component")"
  bootstrap="$(motd_bootstrap_path)"
  if [ ! -x "$bootstrap" ]; then
    motd_launcher_log "bootstrap_missing component=$component path=$bootstrap"
    motd_render_launcher_status "$label 安装器缺失：$bootstrap" "${MOTD_MENU_FG_MAGENTA:-}"
    return 1
  fi

  run_dir="$STATE_DIR/bootstrap-runs"
  mkdir -p "$run_dir" >/dev/null 2>&1 || true
  run_log="$run_dir/${component}.$$.$RANDOM.log"
  rc_file="$run_log.rc"
  : >"$run_log" 2>/dev/null || true

  motd_launcher_log "bootstrap_run_background force=1 mode=$mode component=$component log=$run_log"
  motd_render_launcher_status "$label 准备后台${action_label}..."
  (
    if [ "$mode" = "update" ]; then
      "$bootstrap" --force --update --component "$component" >"$run_log" 2>&1
    else
      "$bootstrap" --force --component "$component" >"$run_log" 2>&1
    fi
    rc=$?
    printf '%s\n' "$rc" >"$rc_file" 2>/dev/null || true
    exit "$rc"
  ) &
  pid=$!

  while kill -0 "$pid" >/dev/null 2>&1; do
    case $((tick % 4)) in
      0) spinner='-' ;;
      1) spinner='\' ;;
      2) spinner='|' ;;
      *) spinner='/' ;;
    esac
    latest="$(motd_bootstrap_latest_line "$run_log" || true)"
    [ -n "$latest" ] || latest="正在解析依赖与安装环境"
    motd_render_launcher_status "$spinner $label ${action_label}中：$latest"
    tick=$((tick + 1))
    sleep 0.25
  done

  wait "$pid"
  rc=$?
  if [ -f "$rc_file" ]; then
    rc="$(cat "$rc_file" 2>/dev/null || printf '%s' "$rc")"
  fi

  if [ "$rc" = "0" ]; then
    motd_refresh_launcher_env || true
    motd_launcher_log "bootstrap_ok mode=$mode component=$component"
    if [ "$mode" = "update" ]; then
      reason="$(motd_bootstrap_state_reason "$component" || true)"
      case "$reason" in
        up-to-date) motd_render_launcher_status "$label 已是最新版本。" ;;
        updated) motd_render_launcher_status "$label 更新完成。" ;;
        *) motd_render_launcher_status "$label 更新检查完成。" ;;
      esac
    else
      motd_render_launcher_status "$label 安装完成，准备启动。"
    fi
    rm -f "$run_log" "$rc_file" 2>/dev/null || true
    return 0
  fi

  latest="$(motd_bootstrap_latest_line "$run_log" || true)"
  reason="$(motd_bootstrap_state_reason "$component" || true)"
  summary="$label ${action_label}失败"
  [ -n "$reason" ] && summary="$summary：$reason"
  [ -n "$latest" ] && summary="$summary / $latest"
  motd_launcher_log "bootstrap_fail component=$component rc=$rc reason=$(motd_sanitize_field "$reason") latest=$(motd_sanitize_field "$latest")"
  motd_render_launcher_status "$summary" "${MOTD_MENU_FG_MAGENTA:-}"
  return 1
}

motd_has_projectying() {
  [ -x "$ROOT_DIR/projectying/run.sh" ]
}

motd_has_codex() {
  [ -x "$PREFIX/bin/codex" ] || return 1
  [ -f "$PREFIX/lib/node_modules/@openai/codex/bin/codex.js" ]
}

motd_has_gemini() {
  if [ ! -x "$HOME/.local/bin/gemini" ] && [ ! -x "$PREFIX/bin/gemini" ]; then
    return 1
  fi
  [ -f "$PREFIX/lib/node_modules/@google/gemini-cli/bundle/gemini.js" ] || \
    [ -f "$PREFIX/lib/node_modules/@google/gemini-cli/dist/index.js" ]
}

motd_has_claude() {
  if [ ! -x "$HOME/.local/bin/claude" ] && [ ! -x "$PREFIX/bin/claude" ]; then
    return 1
  fi
  [ -f "$PREFIX/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" ]
}

motd_projectying_cmd() {
  if [ -x "$ROOT_DIR/bin/aitermux" ]; then
    printf '%s\n' "$ROOT_DIR/bin/aitermux"
    return 0
  fi
  if [ -x "$ROOT_DIR/projectying/run.sh" ]; then
    printf '%s\n' "$ROOT_DIR/projectying/run.sh"
    return 0
  fi
  return 1
}

motd_codex_cmd() {
  if [ -x "$HOME/.local/bin/codex" ]; then
    printf '%s\n' "$HOME/.local/bin/codex"
    return 0
  fi
  if [ -x "$PREFIX/bin/codex" ]; then
    printf '%s\n' "$PREFIX/bin/codex"
    return 0
  fi
  return 1
}

motd_gemini_cmd() {
  if [ -x "$HOME/.local/bin/gemini" ]; then
    printf '%s\n' "$HOME/.local/bin/gemini"
    return 0
  fi
  if [ -x "$PREFIX/bin/gemini" ]; then
    printf '%s\n' "$PREFIX/bin/gemini"
    return 0
  fi
  return 1
}

motd_claude_cmd() {
  if [ -x "$HOME/.local/bin/claude" ]; then
    printf '%s\n' "$HOME/.local/bin/claude"
    return 0
  fi
  if [ -x "$PREFIX/bin/claude" ]; then
    printf '%s\n' "$PREFIX/bin/claude"
    return 0
  fi
  return 1
}

motd_tty_run() {
  local cwd="$1"
  shift
  local rc=0

  motd_launcher_log "launch cwd=${cwd:-$PWD} cmd=$*"
  if [ -n "${cwd:-}" ]; then
    if motd_has_tty; then
      # shellcheck disable=SC2094
      (cd "$cwd" && "$@" <"$TTY_DEV" >"$TTY_DEV" 2>"$TTY_DEV")
    else
      (cd "$cwd" && "$@")
    fi
  else
    if motd_has_tty; then
      # shellcheck disable=SC2094
      ("$@" <"$TTY_DEV" >"$TTY_DEV" 2>"$TTY_DEV")
    else
      ("$@")
    fi
  fi
  rc=$?
  motd_launcher_log "exit rc=$rc cwd=${cwd:-$PWD} cmd=$*"
  return $rc
}

motd_launch_custom_path() {
  local raw_path="$1"
  local resolved='' runner='' cwd=''

  resolved="$(motd_launcher_validate_path "$raw_path" || true)"
  if [ -z "$resolved" ]; then
    tty_printf '[launcher] %s\n' "${MOTD_LAUNCHER_VALIDATE_ERROR:-启动项路径无效}"
    return 0
  fi

  cwd="$(dirname -- "$resolved" 2>/dev/null || printf '%s' "$HOME")"
  runner="$(motd_launcher_runner_for_path "$resolved" || true)"

  if [ -n "$runner" ]; then
    motd_tty_run "$cwd" "$runner" "$resolved"
    return $?
  fi

  motd_tty_run "$cwd" "$resolved"
  return $?
}

motd_launch_choice() {
  local choice="$1"
  local idx=0
  local item_id='' item_kind='' item_label='' item_path=''
  local cmd=""
  local rc=0

  motd_refresh_launcher_env || true
  motd_launcher_load_items
  case "$choice" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  idx=$((10#$choice))
  [ "$idx" -ge 1 ] 2>/dev/null || return 1
  [ "$idx" -le "${#MOTD_LAUNCHER_IDS[@]}" ] 2>/dev/null || return 1
  item_id="${MOTD_LAUNCHER_IDS[$((idx - 1))]}"
  item_kind="${MOTD_LAUNCHER_KINDS[$((idx - 1))]}"
  item_label="${MOTD_LAUNCHER_LABELS[$((idx - 1))]}"
  item_path="${MOTD_LAUNCHER_PATHS[$((idx - 1))]}"
  motd_launcher_log "choice=${choice:-invalid} id=${item_id:-unknown} kind=${item_kind:-unknown} label=$(motd_sanitize_field "$item_label") source=motd-menu"

  if [ -n "$item_path" ]; then
    motd_launch_custom_path "$item_path"
    return $?
  fi

  case "$item_id" in
    projectying)
      if ! motd_has_projectying; then
        motd_bootstrap_component_now projectying || true
      fi
      cmd="$(motd_projectying_cmd || true)"
      if [ -n "${cmd:-}" ]; then
        motd_tty_run "$HOME" "$cmd"
        rc=$?
      else
        tty_printf '[launcher] 未找到 Project 萤启动入口。\n'
        rc=0
      fi
      ;;
    codex)
      if ! motd_has_codex; then
        motd_bootstrap_component_now codex || true
      fi
      cmd="$(motd_codex_cmd || true)"
      if [ -n "${cmd:-}" ] && motd_has_codex; then
        motd_tty_run "$HOME" "$cmd"
        rc=$?
      else
        tty_printf '[launcher] 未找到 codex 命令。\n'
        rc=0
      fi
      ;;
    gemini)
      if ! motd_has_gemini; then
        motd_bootstrap_component_now gemini || true
      fi
      cmd="$(motd_gemini_cmd || true)"
      if [ -n "${cmd:-}" ] && motd_has_gemini; then
        motd_tty_run "$HOME" "$cmd"
        rc=$?
      else
        tty_printf '[launcher] 未找到 gemini 命令。\n'
        rc=0
      fi
      ;;
    claude)
      if ! motd_has_claude; then
        motd_bootstrap_component_now claude || true
      fi
      cmd="$(motd_claude_cmd || true)"
      if [ -n "${cmd:-}" ] && motd_has_claude; then
        motd_tty_run "$HOME" "$cmd"
        rc=$?
      else
        tty_printf '[launcher] 未找到 Claude Code 命令。\n'
        rc=0
      fi
      ;;
    xfce)
      if command -v tx11start >/dev/null 2>&1; then
        motd_tty_run "$HOME" tx11start
        rc=$?
      else
        tty_printf '[launcher] 未找到 tx11start 命令。\n'
        rc=0
      fi
      ;;
    *)
      if [ "$item_kind" = "custom" ]; then
        tty_printf '[launcher] 启动项路径为空：%s\n' "$item_label"
        rc=0
      else
        tty_printf '[launcher] 未知启动项：%s\n' "$item_id"
        rc=0
      fi
      ;;
  esac

  return "$rc"
}

motd_print_launcher_menu_item() {
  local selected="$1"
  local idx="$2"
  local label="$3"
  local reset="$4"
  local bold="$5"
  local fg_white="$6"
  local fg_cyan="$7"
  local fg_cyan_dim="$8"
  local fg_magenta="$9"
  local pointer=' '
  local pointer_style="$fg_cyan_dim"
  local badge_style="$fg_magenta"
  local label_style="${bold}${fg_white}"

  if [ "$selected" = "$idx" ]; then
    pointer='›'
    pointer_style="$fg_cyan"
    badge_style="$fg_cyan"
    label_style="${bold}${fg_cyan}"
  fi

  tty_printf '  %b%s%b %b[%s]%b  %b%s%b' \
    "$pointer_style" "$pointer" "$reset" \
    "$badge_style" "$idx" "$reset" \
    "$label_style" "$label" "$reset"
}

motd_print_launcher_menu_item_static() {
  local idx="$1"
  local label="$2"
  local reset="$3"
  local bold="$4"
  local fg_white="$5"
  local fg_magenta="$6"

  tty_printf '    %b[%s]%b  %b%s%b' \
    "$fg_magenta" "$idx" "$reset" \
    "${bold}${fg_white}" "$label" "$reset"
}

motd_launcher_menu_styles_init() {
  local mode="${1:-launcher}"
  local reset='' bold='' dim=''
  local fg_white='' fg_cyan='' fg_cyan_dim='' fg_magenta='' fg_violet='' fg_blue=''
  local cols=80
  local rows=24
  local hint=''
  local menu_top_row=4
  local item_count=0
  local layout_item_count=0
  local prompt_row=0
  local divider_row=0
  local hint_row=0
  local safe_top_row=1
  local safe_bottom_row=0
  local title_row=0
  local content_top_row=0
  local max_card_height=0
  local art_enabled=0
  local card_enabled=0
  local art_top_row=0
  local card_top_row=0
  local card_height=12

  if [ "${AITERMUX_MOTD_COLOR:-1}" != "0" ]; then
    reset=$'\033[0m'
    bold=$'\033[1m'
    dim=$'\033[2m'
    fg_white=$'\033[97m'
    fg_cyan=$'\033[38;2;0;255;229m'
    fg_cyan_dim=$'\033[38;2;105;190;210m'
    fg_magenta=$'\033[38;2;255;92;218m'
    fg_violet=$'\033[38;2;170;120;255m'
    fg_blue=$'\033[38;2;114;198;255m'
  fi

  motd_launcher_load_items
  cols="$(motd_term_cols)"
  rows="$(motd_term_rows)"
  MOTD_VISIBLE_ROWS="$rows"
  item_count="${#MOTD_LAUNCHER_IDS[@]}"
  layout_item_count=$((item_count + 1))
  [ "$layout_item_count" -ge 1 ] 2>/dev/null || layout_item_count=1
  hint="  ${fg_cyan_dim}↑↓ 选择  ·  输入序号  ·  Enter 启动  ·  Esc 返回 Shell${reset}"
  if [ "${cols:-0}" -lt 56 ] 2>/dev/null; then
    hint="  ${fg_cyan_dim}↑↓ 选择 · 序号+Enter · Esc 返回${reset}"
  fi
  if [ "${cols:-0}" -lt 44 ] 2>/dev/null; then
    hint="  ${fg_cyan_dim}↑↓ 选择 · Enter · Esc${reset}"
  fi
  if [ "${cols:-0}" -lt 28 ] 2>/dev/null; then
    hint=''
  fi

  if [ "$mode" = "launcher" ] && { [ "${rows:-24}" -lt "${AITERMUX_MOTD_COMPACT_ROWS:-28}" ] 2>/dev/null || [ "${MOTD_FORCE_COMPACT:-0}" = "1" ]; }; then
    hint="  ${fg_cyan_dim}↑↓ 选择  ·  输入序号  ·  Enter 启动  ·  Esc 返回 Shell${reset}"
    if [ "${cols:-0}" -lt 56 ] 2>/dev/null; then
      hint="  ${fg_cyan_dim}↑↓ 选择 · 序号+Enter · Esc 返回${reset}"
    fi
    if [ "${cols:-0}" -lt 44 ] 2>/dev/null; then
      hint="  ${fg_cyan_dim}↑↓ 选择 · Enter · Esc${reset}"
    fi
  fi

  MOTD_MENU_RESET="$reset"
  MOTD_MENU_BOLD="$bold"
  MOTD_MENU_FG_WHITE="$fg_white"
  MOTD_MENU_FG_CYAN="$fg_cyan"
  MOTD_MENU_FG_CYAN_DIM="$fg_cyan_dim"
  MOTD_MENU_FG_MAGENTA="$fg_magenta"
  MOTD_MENU_DECO="  ${fg_violet}▪▪▪${fg_magenta}───────── ${fg_blue}───── ${fg_cyan}───${dim}${fg_white}  - - · ·${reset}"
  if [ "${cols:-0}" -lt 40 ] 2>/dev/null; then
    MOTD_MENU_DECO="  ${fg_violet}▪▪▪${fg_magenta}──── ${fg_blue}─── ${fg_cyan}──${dim}${fg_white}  · ·${reset}"
  fi
  if [ "${cols:-0}" -lt 28 ] 2>/dev/null; then
    MOTD_MENU_DECO="  ${fg_violet}▪▪▪${fg_blue}── ${fg_cyan}──${reset}"
  fi
  MOTD_MENU_HINT="$hint"
  MOTD_MENU_LAYOUT_ITEM_COUNT="$layout_item_count"
  MOTD_MENU_PROMPT_PREFIX="  ${bold}${fg_cyan}>${reset} "
  MOTD_MENU_PROMPT_INPUT_COL=5
  MOTD_LAUNCHER_CARD_HEIGHT=0
  MOTD_LAUNCHER_CARD_TOP_ROW=0
  safe_top_row=$((MOTD_SCREEN_TOP_GAP + 1))
  if [ "${rows:-24}" -le 18 ] 2>/dev/null; then
    safe_top_row=2
  elif [ "${rows:-24}" -le 20 ] 2>/dev/null; then
    safe_top_row=4
  fi
  safe_bottom_row=$((rows - MOTD_SCREEN_BOTTOM_GAP))
  if [ "$safe_bottom_row" -lt 6 ] 2>/dev/null; then
    safe_bottom_row="$rows"
  fi

  if [ "$mode" = "config" ]; then
    menu_top_row=$((safe_top_row + 4))
    MOTD_FRAME_ART_ENABLED=0
    MOTD_FRAME_ART_TOP_ROW=0
    MOTD_FRAME_TITLE_ROW="$safe_top_row"
    if [ "${cols:-0}" -ge 64 ] 2>/dev/null && [ "${rows:-0}" -ge 32 ] 2>/dev/null; then
      MOTD_FRAME_ART_ENABLED=1
      MOTD_FRAME_ART_TOP_ROW="$safe_top_row"
      MOTD_FRAME_TITLE_ROW=$((safe_top_row + 9))
      menu_top_row=$((MOTD_FRAME_TITLE_ROW + 4))
    fi
    MOTD_MENU_TOP_ROW="$menu_top_row"
    MOTD_MENU_RENDER_TOP_ROW="$menu_top_row"
    MOTD_MENU_FIRST_ITEM_ROW=$((MOTD_MENU_RENDER_TOP_ROW + 2))
    MOTD_MENU_HINT_ROW=$((MOTD_MENU_FIRST_ITEM_ROW + 5))
    MOTD_MENU_DIVIDER_ROW=$((MOTD_MENU_HINT_ROW - 1))
    MOTD_MENU_STATUS_ROW=$((MOTD_MENU_HINT_ROW + 1))
    MOTD_MENU_PROMPT_ROW=$((MOTD_MENU_STATUS_ROW + 1))
    if [ "${MOTD_MENU_STATUS_ROW:-0}" -lt "${MOTD_MENU_FIRST_ITEM_ROW:-0}" ] 2>/dev/null; then
      MOTD_MENU_STATUS_ROW="${MOTD_MENU_FIRST_ITEM_ROW}"
      MOTD_MENU_PROMPT_ROW=$((MOTD_MENU_STATUS_ROW + 1))
    fi
    if [ "${MOTD_MENU_PROMPT_ROW:-0}" -gt "$safe_bottom_row" ] 2>/dev/null; then
      MOTD_MENU_PROMPT_ROW="$safe_bottom_row"
      MOTD_MENU_STATUS_ROW=$((MOTD_MENU_PROMPT_ROW - 1))
      MOTD_MENU_HINT_ROW=$((MOTD_MENU_STATUS_ROW - 1))
      MOTD_MENU_DIVIDER_ROW=$((MOTD_MENU_HINT_ROW - 1))
    fi
    MOTD_MENU_AFTER_ROW=$((MOTD_MENU_PROMPT_ROW + 1))
    if [ "${MOTD_MENU_AFTER_ROW:-0}" -gt "${rows:-24}" ] 2>/dev/null; then
      MOTD_MENU_AFTER_ROW="$rows"
    fi
    if [ "${MOTD_MENU_DIVIDER_ROW:-0}" -lt "$((MOTD_MENU_FIRST_ITEM_ROW + 1))" ] 2>/dev/null; then
      MOTD_MENU_DIVIDER_ROW=$((MOTD_MENU_FIRST_ITEM_ROW + 1))
      MOTD_MENU_HINT_ROW=$((MOTD_MENU_DIVIDER_ROW + 1))
      MOTD_MENU_STATUS_ROW=$((MOTD_MENU_HINT_ROW + 1))
      MOTD_MENU_PROMPT_ROW=$((MOTD_MENU_STATUS_ROW + 1))
    fi
    MOTD_MENU_CURSOR_ROW="$MOTD_MENU_PROMPT_ROW"
    return 0
  fi

  art_enabled=0
  art_top_row=0
  title_row="$safe_top_row"
  if [ "${cols:-0}" -ge 64 ] 2>/dev/null && [ "${rows:-0}" -ge 32 ] 2>/dev/null; then
    art_enabled=1
    art_top_row="$safe_top_row"
    title_row=$((safe_top_row + 9))
  fi

  content_top_row=$((title_row + 4))

  card_enabled=0
  card_top_row=0
  card_height=0
  menu_top_row="$content_top_row"

  if [ "${AITERMUX_MOTD_LAUNCHER_CARD:-1}" != "0" ] && [ "${MOTD_FORCE_COMPACT:-0}" != "1" ] && [ "${rows:-24}" -ge "${AITERMUX_MOTD_COMPACT_ROWS:-28}" ] 2>/dev/null && [ "${cols:-0}" -ge 44 ] 2>/dev/null; then
    max_card_height=$((safe_bottom_row - content_top_row - layout_item_count - 6))
    if [ "$max_card_height" -gt 12 ] 2>/dev/null; then
      max_card_height=12
    fi
    if [ "$max_card_height" -ge 4 ] 2>/dev/null; then
      card_enabled=1
      card_height="$max_card_height"
      card_top_row="$content_top_row"
      menu_top_row=$((card_top_row + card_height + 1))
    fi
  fi

  divider_row=$((menu_top_row + layout_item_count + 1))
  hint_row=$((divider_row + 1))
  prompt_row=$((hint_row + 2))
  if [ "$prompt_row" -gt "$safe_bottom_row" ] 2>/dev/null; then
    prompt_row="$safe_bottom_row"
    hint_row=$((prompt_row - 2))
    divider_row=$((hint_row - 1))
    menu_top_row=$((divider_row - layout_item_count - 1))
    if [ "$card_enabled" = "1" ] && [ "$menu_top_row" -le "$card_top_row" ] 2>/dev/null; then
      card_enabled=0
      card_top_row=0
      card_height=0
      menu_top_row="$content_top_row"
      divider_row=$((menu_top_row + layout_item_count + 1))
      hint_row=$((divider_row + 1))
      prompt_row=$((hint_row + 2))
    fi
  fi
  MOTD_MENU_PROMPT_ROW="$prompt_row"
  MOTD_MENU_STATUS_ROW=$((prompt_row - 1))
  if [ "${MOTD_MENU_STATUS_ROW:-0}" -lt 1 ] 2>/dev/null; then
    MOTD_MENU_STATUS_ROW=1
  fi
  MOTD_MENU_AFTER_ROW=$((prompt_row + 1))
  if [ "${MOTD_MENU_AFTER_ROW:-0}" -gt "$rows" ] 2>/dev/null; then
    MOTD_MENU_AFTER_ROW="$rows"
  fi
  MOTD_MENU_CURSOR_ROW="$prompt_row"

  if [ "$prompt_row" -gt "$safe_bottom_row" ] 2>/dev/null && [ "$art_enabled" = "1" ]; then
    art_enabled=0
    art_top_row=0
    title_row="$safe_top_row"
    content_top_row=$((title_row + 4))
    menu_top_row="$content_top_row"
    card_enabled=0
    card_top_row=0
    card_height=0
    if [ "${AITERMUX_MOTD_LAUNCHER_CARD:-1}" != "0" ] && [ "${MOTD_FORCE_COMPACT:-0}" != "1" ] && [ "${rows:-24}" -ge "${AITERMUX_MOTD_COMPACT_ROWS:-28}" ] 2>/dev/null && [ "${cols:-0}" -ge 44 ] 2>/dev/null; then
      max_card_height=$((safe_bottom_row - content_top_row - layout_item_count - 6))
      if [ "$max_card_height" -gt 12 ] 2>/dev/null; then
        max_card_height=12
      fi
      if [ "$max_card_height" -ge 4 ] 2>/dev/null; then
        card_enabled=1
        card_height="$max_card_height"
        card_top_row="$content_top_row"
        menu_top_row=$((card_top_row + card_height + 1))
      fi
    fi
    divider_row=$((menu_top_row + layout_item_count + 1))
    hint_row=$((divider_row + 1))
    prompt_row=$((hint_row + 2))
    MOTD_MENU_PROMPT_ROW="$prompt_row"
    MOTD_MENU_STATUS_ROW=$((prompt_row - 1))
    MOTD_MENU_AFTER_ROW=$((prompt_row + 1))
    MOTD_MENU_CURSOR_ROW="$prompt_row"
  fi

  MOTD_FRAME_ART_ENABLED="$art_enabled"
  MOTD_FRAME_ART_TOP_ROW="$art_top_row"
  MOTD_FRAME_TITLE_ROW="$title_row"
  MOTD_MENU_RENDER_TOP_ROW="$menu_top_row"
  MOTD_MENU_TOP_ROW="$MOTD_MENU_RENDER_TOP_ROW"
  MOTD_MENU_FIRST_ITEM_ROW=$((MOTD_MENU_RENDER_TOP_ROW + 1))
  MOTD_MENU_HINT_ROW="$hint_row"
  MOTD_MENU_DIVIDER_ROW="$divider_row"
  if [ "$card_enabled" = "1" ]; then
    MOTD_LAUNCHER_CARD_HEIGHT="$card_height"
    MOTD_LAUNCHER_CARD_TOP_ROW="$card_top_row"
  fi
}

motd_move_cursor_to() {
  local row="$1"
  local col="${2:-1}"
  [ -n "${row:-}" ] || return 0
  [ -n "${col:-}" ] || col=1
  tty_printf '\033[%s;%sH' "$row" "$col"
}

motd_row_visible() {
  local row="${1:-0}"
  local rows="${MOTD_VISIBLE_ROWS:-0}"
  if ! motd_is_uint "$rows" || [ "$rows" -le 0 ] 2>/dev/null; then
    rows="$(motd_term_rows)"
  fi
  [ "$row" -ge 1 ] 2>/dev/null && [ "$row" -le "$rows" ] 2>/dev/null
}

motd_set_prompt_cursor_style() {
  tty_printf '\033[5 q' || true
}

motd_place_input_cursor() {
  local value="${1:-${MOTD_INPUT_VALUE:-}}"
  local row="${MOTD_MENU_CURSOR_ROW:-${MOTD_MENU_PROMPT_ROW:-1}}"
  local col="${MOTD_MENU_PROMPT_INPUT_COL:-5}"

  col=$((col + ${#value}))
  motd_move_cursor_to "$row" "$col"
  motd_set_prompt_cursor_style
}

motd_hide_menu_cursor() {
  motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
}

motd_clear_row_at() {
  local row="$1"
  motd_row_visible "$row" || return 0
  motd_move_cursor_to "$row" 1
  tty_printf '\033[2K\r'
}

motd_clear_row_range() {
  local start_row="${1:-1}"
  local end_row="${2:-$start_row}"
  local row=0

  if [ "$end_row" -lt "$start_row" ] 2>/dev/null; then
    return 0
  fi

  for ((row=start_row; row<=end_row; row++)); do
    motd_clear_row_at "$row"
  done
}

motd_render_launcher_menu_text_row() {
  local row="$1"
  local text="$2"
  motd_row_visible "$row" || return 0
  motd_move_cursor_to "$row" 1
  tty_printf '\033[2K\r%s' "$text"
}

motd_render_launcher_menu_item_row() {
  local selected="$1"
  local idx="$2"
  local row="$3"
  local label="$4"
  motd_row_visible "$row" || return 0
  [ "$row" -gt 0 ] 2>/dev/null && motd_move_cursor_to "$row" 1
  tty_printf '\033[2K\r'
  if [ "$selected" = "0" ]; then
    motd_print_launcher_menu_item_static "$idx" "$label" "$MOTD_MENU_RESET" "$MOTD_MENU_BOLD" "$MOTD_MENU_FG_WHITE" "$MOTD_MENU_FG_MAGENTA"
  else
    motd_print_launcher_menu_item "$selected" "$idx" "$label" "$MOTD_MENU_RESET" "$MOTD_MENU_BOLD" "$MOTD_MENU_FG_WHITE" "$MOTD_MENU_FG_CYAN" "$MOTD_MENU_FG_CYAN_DIM" "$MOTD_MENU_FG_MAGENTA"
  fi
}

motd_render_launcher_menu_items() {
  local selected="${1:-1}"
  local row="${MOTD_MENU_FIRST_ITEM_ROW:-1}"
  local idx=0
  local settings_idx=1
  local label=''
  local cols=80

  cols="$(motd_term_cols)"
  for ((idx=0; idx<${#MOTD_LAUNCHER_LABELS[@]}; idx++)); do
    label="$(motd_launcher_compact_label "${MOTD_LAUNCHER_LABELS[$idx]}" "$cols")"
    motd_render_launcher_menu_item_row "$selected" "$((idx + 1))" "$row" "$label"
    row=$((row + 1))
  done
  settings_idx=$(( ${#MOTD_LAUNCHER_LABELS[@]} + 1 ))
  motd_render_launcher_menu_item_row "$selected" "$settings_idx" "$row" "PROJECT凌设置"
}

motd_launcher_label_for_index() {
  local idx="${1:-0}"
  local settings_idx=0
  local cols=80
  cols="$(motd_term_cols)"
  settings_idx=$(( ${#MOTD_LAUNCHER_LABELS[@]} + 1 ))
  if [ "$idx" -eq "$settings_idx" ] 2>/dev/null; then
    printf '%s\n' 'PROJECT凌设置'
    return 0
  fi
  if [ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le "${#MOTD_LAUNCHER_LABELS[@]}" ] 2>/dev/null; then
    motd_launcher_compact_label "${MOTD_LAUNCHER_LABELS[$((idx - 1))]}" "$cols"
    return 0
  fi
  printf '%s\n' ''
}

motd_render_launcher_selection_delta() {
  local old_selected="${1:-1}"
  local new_selected="${2:-1}"
  local row=0
  local label=''
  [ "$old_selected" = "$new_selected" ] && return 0
  motd_launcher_load_items
  row=$((MOTD_MENU_FIRST_ITEM_ROW + old_selected - 1))
  label="$(motd_launcher_label_for_index "$old_selected")"
  [ -n "$label" ] && motd_render_launcher_menu_item_row 0 "$old_selected" "$row" "$label"
  row=$((MOTD_MENU_FIRST_ITEM_ROW + new_selected - 1))
  label="$(motd_launcher_label_for_index "$new_selected")"
  [ -n "$label" ] && motd_render_launcher_menu_item_row "$new_selected" "$new_selected" "$row" "$label"
  motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
}

motd_config_label_for_index() {
  case "${1:-0}" in
    1) printf '%s\n' '启动项管理' ;;
    2) printf '%s\n' '开屏动画速度' ;;
    3) printf '%s\n' 'PROJECT凌设置' ;;
    *) printf '%s\n' '' ;;
  esac
}

motd_render_config_menu_item_row() {
  local selected="$1"
  local idx="$2"
  local row="$3"
  local label="$4"

  motd_render_launcher_menu_item_row "$selected" "$idx" "$row" "$label"
}

motd_config_item_line() {
  local selected="${1:-1}"
  local idx="${2:-1}"
  local label="${3:-}"
  local pointer=' '
  local pointer_style="${MOTD_MENU_FG_CYAN_DIM:-}"
  local badge_style="${MOTD_MENU_FG_MAGENTA:-}"
  local label_style="${MOTD_MENU_BOLD:-}${MOTD_MENU_FG_WHITE:-}"

  if [ "$selected" = "$idx" ]; then
    pointer='›'
    pointer_style="${MOTD_MENU_FG_CYAN:-}"
    badge_style="${MOTD_MENU_FG_CYAN:-}"
  fi
  printf '  %b%s%b %b[%s]%b  %b%s%b\n' \
    "$pointer_style" "$pointer" "$MOTD_MENU_RESET" \
    "$badge_style" "$idx" "$MOTD_MENU_RESET" \
    "$label_style" "$label" "$MOTD_MENU_RESET"
}

motd_render_config_selection_delta() {
  local old_selected="${1:-1}"
  local new_selected="${2:-1}"
  local row=0
  local label=''
  [ "$old_selected" = "$new_selected" ] && return 0

  row=$((MOTD_MENU_FIRST_ITEM_ROW + old_selected - 1))
  label="$(motd_config_label_for_index "$old_selected")"
  [ -n "$label" ] && motd_render_config_menu_item_row 0 "$old_selected" "$row" "$label"

  row=$((MOTD_MENU_FIRST_ITEM_ROW + new_selected - 1))
  label="$(motd_config_label_for_index "$new_selected")"
  [ -n "$label" ] && motd_render_config_menu_item_row "$new_selected" "$new_selected" "$row" "$label"
  motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
}

motd_selector_total() {
  case "${1:-launcher}" in
    launcher)
      printf '%s\n' "$(( ${#MOTD_LAUNCHER_IDS[@]} + 1 ))"
      ;;
    config_select)
      printf '%s\n' "${MOTD_CONFIG_TOTAL:-1}"
      ;;
    *)
      printf '1\n'
      ;;
  esac
}

motd_selector_get_selected() {
  case "${1:-launcher}" in
    launcher)
      printf '%s\n' "${MOTD_MENU_SELECTED:-1}"
      ;;
    config_select)
      printf '%s\n' "${MOTD_CONFIG_SELECTED:-1}"
      ;;
    *)
      printf '1\n'
      ;;
  esac
}

motd_selector_set_selected() {
  local mode="${1:-launcher}"
  local selected="${2:-1}"

  case "$mode" in
    launcher)
      MOTD_MENU_SELECTED="$selected"
      ;;
    config_select)
      MOTD_CONFIG_SELECTED="$selected"
      ;;
  esac
}

motd_selector_render_delta() {
  local mode="${1:-launcher}"
  local old_selected="${2:-1}"
  local new_selected="${3:-1}"

  case "$mode" in
    launcher)
      motd_render_launcher_selection_delta "$old_selected" "$new_selected"
      ;;
    config_select)
      motd_render_config_selection_delta "$old_selected" "$new_selected"
      ;;
  esac
}

motd_read_selector_input() {
  local mode="${1:-launcher}"
  local allow_r="${2:-0}"
  local key='' seq='' _discard=''
  local selected=1
  local previous_selected=1
  local total=1
  local value="${MOTD_INPUT_VALUE:-}"
  local submit_value=''

  MOTD_INPUT_ACTION='idle'
  if ! motd_has_tty; then
    MOTD_INPUT_ACTION='command:quit'
    return 0
  fi
  total="$(motd_selector_total "$mode")"
  selected="$(motd_clamp_menu_selection "$(motd_selector_get_selected "$mode")" "$total")"
  motd_selector_set_selected "$mode" "$selected"
  if ! IFS= read -rsn1 -t "${MOTD_INPUT_TIMEOUT:-0.25}" key <"$TTY_DEV" 2>/dev/null; then
    return 0
  fi

  case "$key" in
    ''|$'\n'|$'\r')
      if [ -n "$value" ]; then
        submit_value="$(motd_trim "$value")"
        motd_input_reset "$mode"
        case "${submit_value,,}" in
          /settings|/setting)
            MOTD_INPUT_ACTION='command:settings'
            ;;
          /quit)
            MOTD_INPUT_ACTION='command:quit'
            ;;
          *)
            MOTD_INPUT_ACTION="submit:${submit_value}"
            ;;
        esac
      else
        MOTD_INPUT_ACTION="submit:${selected}"
      fi
      return 0
      ;;
    $'\003')
      MOTD_INPUT_ACTION='esc'
      return 0
      ;;
    $'\033')
      if IFS= read -rsn1 -t 0.05 seq <"$TTY_DEV" 2>/dev/null; then
        case "$seq" in
          '['|'O')
            if IFS= read -rsn1 -t 0.05 _discard <"$TTY_DEV" 2>/dev/null; then
              case "$_discard" in
                A|k|K)
                  if [ -n "$value" ]; then
                    motd_input_reset "$mode"
                    value=''
                  fi
                  previous_selected="$selected"
                  selected=$((selected - 1))
                  [ "$selected" -ge 1 ] 2>/dev/null || selected="$total"
                  motd_selector_set_selected "$mode" "$selected"
                  motd_selector_render_delta "$mode" "$previous_selected" "$selected"
                  ;;
                B|j|J)
                  if [ -n "$value" ]; then
                    motd_input_reset "$mode"
                    value=''
                  fi
                  previous_selected="$selected"
                  selected=$((selected + 1))
                  [ "$selected" -le "$total" ] 2>/dev/null || selected=1
                  motd_selector_set_selected "$mode" "$selected"
                  motd_selector_render_delta "$mode" "$previous_selected" "$selected"
                  ;;
              esac
            fi
            ;;
        esac
        while IFS= read -rsn1 -t 0.01 _discard <"$TTY_DEV" 2>/dev/null; do :; done
          return 0
        fi
      if [ -n "$value" ]; then
        motd_input_reset "$mode"
      else
        MOTD_INPUT_ACTION='esc'
      fi
      return 0
      ;;
    [kK])
      if [ -n "$value" ]; then
        motd_input_reset "$mode"
        value=''
      fi
      previous_selected="$selected"
      selected=$((selected - 1))
      [ "$selected" -ge 1 ] 2>/dev/null || selected="$total"
      motd_selector_set_selected "$mode" "$selected"
      motd_selector_render_delta "$mode" "$previous_selected" "$selected"
      return 0
      ;;
    [jJ])
      if [ -n "$value" ]; then
        motd_input_reset "$mode"
        value=''
      fi
      previous_selected="$selected"
      selected=$((selected + 1))
      [ "$selected" -le "$total" ] 2>/dev/null || selected=1
      motd_selector_set_selected "$mode" "$selected"
      motd_selector_render_delta "$mode" "$previous_selected" "$selected"
      return 0
      ;;
    $'\177'|$'\010')
      if [ -n "$value" ]; then
        value="${value%?}"
        MOTD_INPUT_VALUE="$value"
        MOTD_INPUT_ERROR_TEXT=''
        MOTD_INPUT_DIRTY=1
        motd_input_render
      fi
      return 0
      ;;
    [rR])
      if [ "$allow_r" = "1" ] && [ -z "$value" ]; then
        MOTD_INPUT_ACTION='submit:r'
      else
        value="${value}${key}"
        MOTD_INPUT_VALUE="$value"
        MOTD_INPUT_ERROR_TEXT=''
        MOTD_INPUT_DIRTY=1
        motd_input_render
      fi
      return 0
      ;;
    *)
      case "$key" in
        [[:print:]])
          value="${value}${key}"
          MOTD_INPUT_VALUE="$value"
          MOTD_INPUT_ERROR_TEXT=''
          MOTD_INPUT_DIRTY=1
          motd_input_render
          ;;
      esac
      return 0
      ;;
  esac
}

motd_render_launcher_prompt() {
  local value="${1:-}"
  local error_text="${2:-}"

  motd_render_launcher_menu_text_row "${MOTD_MENU_PROMPT_ROW:-1}" "${MOTD_MENU_PROMPT_PREFIX}${value}"
  if [ -n "$error_text" ]; then
    motd_render_launcher_menu_text_row "${MOTD_MENU_STATUS_ROW:-1}" "  ${MOTD_MENU_FG_MAGENTA}${error_text}${MOTD_MENU_RESET}"
  else
    motd_clear_row_at "${MOTD_MENU_STATUS_ROW:-1}"
  fi
}

motd_clear_launcher_card_area() {
  local row="${1:-${MOTD_LAUNCHER_CARD_TOP_ROW:-0}}"
  local remaining="${2:-${MOTD_LAUNCHER_CARD_HEIGHT:-0}}"

  while [ "$remaining" -gt 0 ] 2>/dev/null; do
    motd_clear_row_at "$row"
    row=$((row + 1))
    remaining=$((remaining - 1))
  done
}

motd_clear_launcher_card_area_visible() {
  local row="${1:-${MOTD_LAUNCHER_CARD_TOP_ROW:-0}}"
  local remaining="${2:-${MOTD_LAUNCHER_CARD_HEIGHT:-0}}"
  local rows=24

  rows="$(motd_term_rows)"
  while [ "$remaining" -gt 0 ] 2>/dev/null; do
    if [ "$row" -ge 1 ] 2>/dev/null && [ "$row" -le "$rows" ] 2>/dev/null; then
      motd_clear_row_at "$row"
    fi
    row=$((row + 1))
    remaining=$((remaining - 1))
  done
}

motd_clear_launcher_previous_layout() {
  local top=0
  local bottom=0
  local card_top="${MOTD_LAST_CARD_TOP_ROW:-0}"
  local card_bottom=0
  local menu_top="${MOTD_LAST_MENU_TOP_ROW:-0}"
  local menu_bottom="${MOTD_LAST_MENU_AFTER_ROW:-0}"

  if [ "$card_top" -gt 0 ] 2>/dev/null && [ "${MOTD_LAST_CARD_HEIGHT:-0}" -gt 0 ] 2>/dev/null; then
    card_bottom=$((card_top + MOTD_LAST_CARD_HEIGHT + 1))
    top="$card_top"
    bottom="$card_bottom"
  fi
  if [ "$menu_top" -gt 0 ] 2>/dev/null && [ "$menu_bottom" -ge "$menu_top" ] 2>/dev/null; then
    if [ "$top" -eq 0 ] 2>/dev/null || [ "$menu_top" -lt "$top" ] 2>/dev/null; then
      top="$menu_top"
    fi
    if [ "$menu_bottom" -gt "$bottom" ] 2>/dev/null; then
      bottom="$menu_bottom"
    fi
  fi
  if [ "$top" -gt 0 ] 2>/dev/null && [ "$bottom" -ge "$top" ] 2>/dev/null; then
    motd_clear_row_range "$top" "$bottom"
  fi
  MOTD_LAST_CARD_TOP_ROW=0
  MOTD_LAST_CARD_HEIGHT=0
  MOTD_LAST_MENU_TOP_ROW=0
  MOTD_LAST_MENU_AFTER_ROW=0
}

motd_render_launcher_menu_static() {
  local selected="${1:-1}"
  local render_card="${2:-1}"
  local preserve_layout="${3:-0}"
  local top_row=4
  local divider_row=0
  local hint_row=0
  if [ "$preserve_layout" != "1" ]; then
    motd_launcher_menu_styles_init launcher
  fi

  if [ -n "${MOTD_MENU_RENDER_TOP_ROW:-}" ] && [ "${MOTD_MENU_RENDER_TOP_ROW:-0}" -gt 0 ] 2>/dev/null; then
    top_row="$MOTD_MENU_RENDER_TOP_ROW"
  fi
  divider_row="${MOTD_MENU_DIVIDER_ROW:-$((MOTD_MENU_FIRST_ITEM_ROW + MOTD_MENU_LAYOUT_ITEM_COUNT + 1))}"
  hint_row="${MOTD_MENU_HINT_ROW:-$((divider_row + 1))}"

  if [ "${MOTD_LAST_MENU_TOP_ROW:-0}" -gt 0 ] 2>/dev/null && [ "${MOTD_LAST_MENU_AFTER_ROW:-0}" -ge "${MOTD_LAST_MENU_TOP_ROW:-0}" ] 2>/dev/null; then
    if [ "${MOTD_LAST_MENU_TOP_ROW:-0}" != "$top_row" ] || [ "${MOTD_LAST_MENU_AFTER_ROW:-0}" != "${MOTD_MENU_AFTER_ROW:-$((top_row + 12))}" ]; then
      motd_clear_launcher_previous_layout
    fi
  fi

  if [ "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$render_card" = "1" ]; then
      motd_render_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-$((top_row - MOTD_LAUNCHER_CARD_HEIGHT - 2))}"
      MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
      MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
    else
      motd_clear_launcher_card_area
      MOTD_LAST_CARD_TOP_ROW=0
      MOTD_LAST_CARD_HEIGHT=0
    fi
  elif [ "${MOTD_LAST_CARD_HEIGHT:-0}" -gt 0 ] 2>/dev/null; then
    motd_clear_launcher_card_area "${MOTD_LAST_CARD_TOP_ROW:-0}" "${MOTD_LAST_CARD_HEIGHT:-0}"
    MOTD_LAST_CARD_TOP_ROW=0
    MOTD_LAST_CARD_HEIGHT=0
  fi

  motd_render_launcher_menu_text_row "$top_row" "$MOTD_MENU_DECO"
  if [ "$divider_row" -gt "$top_row" ] 2>/dev/null; then
    motd_clear_row_range "$((top_row + 1))" "$((divider_row - 1))"
  fi
  motd_render_launcher_menu_items "$selected"
  motd_render_launcher_menu_text_row "$divider_row" "$MOTD_MENU_DECO"
  if [ -n "$MOTD_MENU_HINT" ]; then
    motd_render_launcher_menu_text_row "$hint_row" "$MOTD_MENU_HINT"
  else
    motd_clear_row_at "$hint_row"
  fi
  if [ "${MOTD_MENU_STATUS_ROW:-0}" -gt "$hint_row" ] 2>/dev/null; then
    motd_clear_row_range "$((hint_row + 1))" "${MOTD_MENU_STATUS_ROW:-$((hint_row + 1))}"
  fi
  motd_render_launcher_prompt "${MOTD_INPUT_VALUE:-}" "${MOTD_INPUT_ERROR_TEXT:-}"
  motd_clear_row_at "${MOTD_MENU_AFTER_ROW:-$((top_row + 12))}"
  if { [ "${MOTD_INPUT_MODE:-launcher}" = "launcher" ] || [ "${MOTD_INPUT_MODE:-launcher}" = "config_select" ]; }; then
    motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
  elif [ "${MOTD_INPUT_MODE:-launcher}" != "launcher" ]; then
    motd_place_input_cursor ''
  else
    tput civis >/dev/null 2>&1 || true
  fi
  MOTD_LAST_MENU_TOP_ROW="$top_row"
  MOTD_LAST_MENU_AFTER_ROW="${MOTD_MENU_AFTER_ROW:-$((top_row + 12))}"
}

motd_launcher_menu_total() {
  motd_launcher_load_items
  printf '%s\n' "$(( ${#MOTD_LAUNCHER_IDS[@]} + 1 ))"
}

motd_clamp_menu_selection() {
  local selected="${1:-1}"
  local total="${2:-1}"
  [ "$total" -ge 1 ] 2>/dev/null || total=1
  case "$selected" in ''|*[!0-9]*) selected=1 ;; esac
  [ "$selected" -ge 1 ] 2>/dev/null || selected=1
  [ "$selected" -le "$total" ] 2>/dev/null || selected="$total"
  printf '%s\n' "$selected"
}

motd_move_cursor_below_menu() {
  return 0
}

motd_prepare_shell_resume() {
  local row="${MOTD_MENU_PROMPT_ROW:-1}"
  local next_row="${MOTD_MENU_AFTER_ROW:-$((row + 1))}"

  tty_printf '\033[0 q' || true
  motd_clear_row_at "$row"
  motd_clear_row_at "${MOTD_MENU_STATUS_ROW:-$row}"
  motd_clear_row_at "$next_row"
  motd_move_cursor_to "$next_row" 1
  tty_printf '\n'
}

motd_flush_tty_input() {
  local _ch=''
  local _i=0
  local _idle=0
  if ! motd_has_tty; then
    MOTD_INPUT_ACTION='command:quit'
    return 0
  fi
  while [ "$_i" -lt 4096 ] 2>/dev/null; do
    if IFS= read -rsn1 -t 0.01 _ch <"$TTY_DEV"; then
      _i=$(( _i + 1 ))
      _idle=0
      continue
    fi
    _idle=$(( _idle + 1 ))
    [ "$_idle" -ge 2 ] && break
  done
}

motd_input_clear_popup_if_any() {
  return 0
}

motd_input_reset() {
  MOTD_INPUT_MODE="${1:-launcher}"
  MOTD_INPUT_VALUE=''
  MOTD_INPUT_ERROR_TEXT=''
  MOTD_INPUT_ACTION='idle'
  motd_input_clear_popup_if_any || true
  MOTD_INPUT_DIRTY=1
}

motd_input_render() {
  local value="${MOTD_INPUT_VALUE:-}"
  local error_text="${MOTD_INPUT_ERROR_TEXT:-}"

  motd_render_launcher_prompt "$value" "$error_text"
  motd_input_clear_popup_if_any || true
  MOTD_INPUT_DIRTY=0
  if { [ "${MOTD_INPUT_MODE:-launcher}" = "launcher" ] || [ "${MOTD_INPUT_MODE:-launcher}" = "config_select" ]; }; then
    motd_place_input_cursor "$value"
  elif [ "${MOTD_INPUT_MODE:-launcher}" != "launcher" ]; then
    motd_place_input_cursor "$value"
  else
    tput civis >/dev/null 2>&1 || true
  fi
}

motd_read_launcher_input() {
  local key='' seq='' _discard=''
  local value="${MOTD_INPUT_VALUE:-}"
  local invalid_text=' 请输入有效序号'

  MOTD_INPUT_ACTION='idle'

  if [ "${MOTD_INPUT_DIRTY:-0}" = "1" ]; then
    motd_input_render
  fi

  if [ "${MOTD_INPUT_MODE:-launcher}" = "launcher" ]; then
    motd_read_selector_input launcher 1
    return 0
  fi

  if [ "${MOTD_INPUT_MODE:-launcher}" = "config_select" ]; then
    motd_read_selector_input config_select 0
    return 0
  fi

  case "${MOTD_INPUT_MODE:-launcher}" in
    launcher) invalid_text='主界面使用 ↑↓ 选择或输入序号，Enter 启动，Esc 返回 Shell' ;;
    config) invalid_text='请输入设置项序号' ;;
  esac

  motd_has_tty || return 0
  if ! IFS= read -rsn1 -t "${MOTD_INPUT_TIMEOUT:-0.25}" key <"$TTY_DEV" 2>/dev/null; then
    return 0
  fi

  case "$key" in
    ''|$'\n'|$'\r')
      motd_input_reset "${MOTD_INPUT_MODE:-launcher}"
      MOTD_INPUT_ACTION="submit:${value}"
      return 0
      ;;
    $'\003')
      motd_input_reset "${MOTD_INPUT_MODE:-launcher}"
      MOTD_INPUT_ACTION='esc'
      return 0
      ;;
    $'\033')
      # Try to distinguish a real ESC key from an escape sequence (arrows etc).
      if IFS= read -rsn1 -t 0.05 seq <"$TTY_DEV" 2>/dev/null; then
        if [ "$seq" = "[" ] || [ "$seq" = "O" ]; then
          IFS= read -rsn1 -t 0.05 _discard <"$TTY_DEV" 2>/dev/null || true
        fi
        while IFS= read -rsn1 -t 0.01 _discard <"$TTY_DEV" 2>/dev/null; do :; done
        return 0
      fi

      # Plain ESC
      motd_input_reset "${MOTD_INPUT_MODE:-launcher}"
      MOTD_INPUT_ACTION='esc'
      return 0
      ;;
    $'\177'|$'\010')
      if [ -n "$value" ]; then
        value="${value%?}"
        MOTD_INPUT_VALUE="$value"
        MOTD_INPUT_ERROR_TEXT=''
        MOTD_INPUT_DIRTY=1
        motd_input_render
      fi
      return 0
      ;;
    *)
      case "$key" in
        [0-9])
          value="${value}${key}"
          MOTD_INPUT_VALUE="$value"
          MOTD_INPUT_ERROR_TEXT=''
          MOTD_INPUT_DIRTY=1
          motd_input_render
          ;;
        [rR])
          if [ "${MOTD_INPUT_MODE:-launcher}" = "launcher" ] && [ -z "$value" ]; then
            MOTD_INPUT_VALUE='r'
            MOTD_INPUT_ERROR_TEXT=''
            MOTD_INPUT_DIRTY=1
            motd_input_render
          else
            MOTD_INPUT_ERROR_TEXT="$invalid_text"
            MOTD_INPUT_DIRTY=1
            motd_input_render
          fi
          ;;
        [[:print:]])
          MOTD_INPUT_ERROR_TEXT="$invalid_text"
          MOTD_INPUT_DIRTY=1
          motd_input_render
          ;;
      esac
      return 0
      ;;
  esac
}

motd_render_config_menu_screen() {
  local title="$1"
  local hint="$2"
  shift 2
  local rows=24
  local top_row=4
  local content_start_row=0
  local divider_row=0
  local hint_row=0
  local row=0
  local line=''
  local max_body_lines=1
  local hidden_lines=0
  local idx=0
  local -a content_lines=("$@")
  local -a visible_lines=()

  motd_launcher_menu_styles_init config
  rows="$(motd_term_rows)"
  motd_render_launcher_frame final "$title"
  top_row="${MOTD_MENU_TOP_ROW:-4}"
  content_start_row="${MOTD_MENU_FIRST_ITEM_ROW:-$((top_row + 2))}"
  divider_row="${MOTD_MENU_DIVIDER_ROW:-$((rows - 5))}"
  hint_row="${MOTD_MENU_HINT_ROW:-$((rows - 3))}"
  max_body_lines=$((divider_row - content_start_row))
  if [ "$max_body_lines" -lt 1 ] 2>/dev/null; then
    max_body_lines=1
  fi

  if [ "${#content_lines[@]}" -gt "$max_body_lines" ] 2>/dev/null; then
    if [ "$max_body_lines" -ge 2 ] 2>/dev/null; then
      for ((idx=0; idx<max_body_lines-1; idx++)); do
        visible_lines+=("${content_lines[$idx]}")
      done
      hidden_lines=$(( ${#content_lines[@]} - max_body_lines + 1 ))
      visible_lines+=("  ${MOTD_MENU_FG_CYAN_DIM}… 窗口高度不足，已隐藏 ${hidden_lines} 行${MOTD_MENU_RESET}")
    else
      visible_lines=("  ${MOTD_MENU_FG_CYAN_DIM}… 内容过多，请缩减后重试${MOTD_MENU_RESET}")
    fi
  else
    visible_lines=("${content_lines[@]}")
  fi

  motd_render_launcher_menu_text_row "$top_row" "$MOTD_MENU_DECO"
  motd_clear_row_at $((top_row + 1))
  motd_clear_row_range "$content_start_row" "$divider_row"
  motd_clear_row_range "$((divider_row + 1))" "${MOTD_MENU_AFTER_ROW:-$rows}"
  row="$content_start_row"
  for line in "${visible_lines[@]}"; do
    motd_render_launcher_menu_text_row "$row" "$line"
    row=$((row + 1))
  done
  motd_render_launcher_menu_text_row "$divider_row" "$MOTD_MENU_DECO"
  if [ -n "$hint" ]; then
    motd_render_launcher_menu_text_row "$hint_row" "$hint"
  else
    motd_clear_row_at "$hint_row"
  fi
  motd_render_launcher_prompt "${MOTD_INPUT_VALUE:-}" "${MOTD_INPUT_ERROR_TEXT:-}"
  motd_clear_row_at "$MOTD_MENU_AFTER_ROW"
  if { [ "${MOTD_INPUT_MODE:-config}" = "launcher" ] || [ "${MOTD_INPUT_MODE:-config}" = "config_select" ]; }; then
    motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
  else
    motd_place_input_cursor ''
  fi
}

motd_prompt_tty_line() {
  local prompt="$1"
  local value=''
  motd_has_tty || return 0
  motd_restore_tty_mode || true
  motd_move_cursor_to "${MOTD_MENU_AFTER_ROW:-1}" 1
  tty_printf '\033[2K\r%s' "$prompt"
  IFS= read -r value <"$TTY_DEV" || value=''
  motd_set_menu_tty_mode || true
  motd_flush_tty_input || true
  printf '%s' "$(motd_sanitize_field "$value")"
}

motd_save_speed_config() {
  local fps="${1:-}"
  local duration="${2:-}"
  local hold="${3:-}"
  local speed="${4:-}"
  mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
  cat >"$MOTD_CONF_FILE" <<EOF
# AITERMUX MOTD local config
AITERMUX_MOTD_FPS=${fps}
AITERMUX_MOTD_DURATION=${duration}
AITERMUX_MOTD_HOLD=${hold}
AITERMUX_MOTD_SPEED=${speed}
EOF
  export AITERMUX_MOTD_FPS="${fps}"
  export AITERMUX_MOTD_DURATION="${duration}"
  export AITERMUX_MOTD_HOLD="${hold}"
  export AITERMUX_MOTD_SPEED="${speed}"
}

motd_run_speed_menu() {
  local action='' last_size='' last_key='' current_size='' current_key='' redraw_needed=1
  local selected=1

  MOTD_CONFIG_TOTAL=5
  MOTD_CONFIG_SELECTED="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
  motd_input_reset config_select
  while :; do
    current_size="$(get_term_size_safe)"
    current_key="$(motd_redraw_size_key "$current_size")"
    if [ "$redraw_needed" = "1" ] || [ "$current_key" != "$last_key" ]; then
      motd_input_reset config_select
      selected="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
      MOTD_CONFIG_SELECTED="$selected"
      motd_render_config_menu_screen "$MOTD_SETTINGS_TITLE" \
        "  ${MOTD_MENU_FG_CYAN_DIM}↑↓ 选择  ·  Enter 应用  ·  Esc 返回上一层${MOTD_MENU_RESET}" \
        "$(motd_config_item_line "$selected" 1 '柔和速度')" \
        "$(motd_config_item_line "$selected" 2 '标准速度')" \
        "$(motd_config_item_line "$selected" 3 '高速模式')"
      motd_hide_menu_cursor
      last_size="$current_size"
      last_key="$current_key"
      redraw_needed=0
      MOTD_INPUT_DIRTY=0
    fi

    motd_read_launcher_input || true
    action="${MOTD_INPUT_ACTION:-idle}"
    case "$action" in
      idle)
        continue
        ;;
      submit:1)
        motd_save_speed_config 12 '' 0.2 0.9
        return 0
        ;;
      submit:2)
        motd_save_speed_config 15 '' '' 1.0
        return 0
        ;;
      submit:3)
        motd_save_speed_config 18 '' 0 1.2
        return 0
        ;;
      submit:|esc)
        return 0
        ;;
      command:settings)
        return 0
        ;;
      command:quit)
        MOTD_REQUEST_SHELL_EXIT=1
        return 0
        ;;
      *)
        motd_hide_menu_cursor
        ;;
    esac
  done
}

motd_run_launcher_items_menu() {
  local action='' label='' path='' item_total=0 idx=0
  local last_size='' last_key='' current_size='' current_key='' redraw_needed=1
  local -a lines=()
  local selected=1

  MOTD_CONFIG_TOTAL=2
  MOTD_CONFIG_SELECTED="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
  motd_input_reset config_select
  while :; do
    current_size="$(get_term_size_safe)"
    current_key="$(motd_redraw_size_key "$current_size")"
    if [ "$redraw_needed" = "1" ] || [ "$current_key" != "$last_key" ]; then
      motd_launcher_load_items
      item_total="${#MOTD_LAUNCHER_LABELS[@]}"
      selected="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
      MOTD_CONFIG_SELECTED="$selected"
      lines=(
        "$(motd_config_item_line "$selected" 1 '添加启动项')"
        "$(motd_config_item_line "$selected" 2 '移除启动项')"
      )
      if [ "$item_total" -gt 0 ] 2>/dev/null; then
        lines+=("")
        lines+=("  ${MOTD_MENU_FG_CYAN_DIM}当前启动项（${item_total}项）：${MOTD_MENU_RESET}")
        for ((idx=0; idx<item_total; idx++)); do
          label="$(motd_launcher_compact_label "${MOTD_LAUNCHER_LABELS[$idx]}" "$(motd_term_cols)")"
          lines+=("    ${MOTD_MENU_FG_CYAN_DIM}[$((idx + 1))] ${label}${MOTD_MENU_RESET}")
        done
      fi

      motd_input_reset config_select
      motd_render_config_menu_screen "$MOTD_SETTINGS_TITLE" \
        "  ${MOTD_MENU_FG_CYAN_DIM}↑↓ 选择  ·  Enter 进入  ·  Esc 返回上一层${MOTD_MENU_RESET}" \
        "${lines[@]}"
      motd_hide_menu_cursor
      last_size="$current_size"
      last_key="$current_key"
      redraw_needed=0
      MOTD_INPUT_DIRTY=0
    fi

    motd_read_launcher_input || true
    action="${MOTD_INPUT_ACTION:-idle}"
    case "$action" in
      idle)
        continue
        ;;
      submit:1)
        label="$(motd_prompt_tty_line '启动项名称 > ')"
        [ -n "$label" ] || { redraw_needed=1; continue; }
        path="$(motd_prompt_launcher_path '启动项路径（绝对路径）> ' 1)"
        [ -n "$path" ] || { redraw_needed=1; continue; }
        MOTD_LAUNCHER_IDS+=("custom-$(date +%s)-$(( ${#MOTD_LAUNCHER_IDS[@]} + 1 ))")
        MOTD_LAUNCHER_KINDS+=("custom")
        MOTD_LAUNCHER_LABELS+=("$label")
        MOTD_LAUNCHER_PATHS+=("$path")
        motd_launcher_save_items
        redraw_needed=1
        ;;
      submit:2)
        MOTD_LAUNCHER_REMOVE_RESULT='back'
        motd_run_launcher_remove_menu || true
        if [ "${MOTD_LAUNCHER_REMOVE_RESULT:-back}" = "main" ]; then
          return 0
        fi
        redraw_needed=1
        ;;
      submit:|esc)
        return 0
        ;;
      command:settings)
        return 0
        ;;
      command:quit)
        MOTD_REQUEST_SHELL_EXIT=1
        return 0
        ;;
      submit:*)
        motd_hide_menu_cursor
        ;;
    esac
  done
}

motd_run_launcher_remove_menu() {
  local action='' idx=0 item_total=0
  local last_size='' last_key='' current_size='' current_key='' redraw_needed=1
  local -a lines=()
  local selected=1

  MOTD_LAUNCHER_REMOVE_RESULT='back'
  MOTD_CONFIG_TOTAL=1
  MOTD_CONFIG_SELECTED=1
  motd_input_reset config_select
  while :; do
    current_size="$(get_term_size_safe)"
    current_key="$(motd_redraw_size_key "$current_size")"
    if [ "$redraw_needed" = "1" ] || [ "$current_key" != "$last_key" ]; then
      motd_launcher_load_items
      item_total="${#MOTD_LAUNCHER_LABELS[@]}"
      MOTD_CONFIG_TOTAL=$(( item_total > 0 ? item_total : 1 ))
      selected="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
      MOTD_CONFIG_SELECTED="$selected"
      lines=()
      if [ "$item_total" -gt 0 ] 2>/dev/null; then
        for ((idx=0; idx<item_total; idx++)); do
          lines+=("$(motd_config_item_line "$selected" "$((idx + 1))" "${MOTD_LAUNCHER_LABELS[$idx]}")")
        done
      else
        lines+=("    ${MOTD_MENU_FG_CYAN_DIM}当前没有可移除的启动项${MOTD_MENU_RESET}")
      fi

      motd_input_reset config_select
      motd_render_config_menu_screen "✲ 当前 //" \
        "  ${MOTD_MENU_FG_CYAN_DIM}↑↓ 选择  ·  Enter 删除  ·  Esc 返回上一层${MOTD_MENU_RESET}" \
        "${lines[@]}"
      motd_hide_menu_cursor
      last_size="$current_size"
      last_key="$current_key"
      redraw_needed=0
      MOTD_INPUT_DIRTY=0
    fi

    motd_read_launcher_input || true
    action="${MOTD_INPUT_ACTION:-idle}"
    case "$action" in
      idle)
        continue
        ;;
      submit:*)
        if [ "$item_total" -le 0 ] 2>/dev/null; then
          MOTD_LAUNCHER_REMOVE_RESULT='back'
          return 0
        fi
        idx=$((10#${action#submit:}))
        if [ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le "$item_total" ] 2>/dev/null; then
          if motd_launcher_remove_indices "$idx"; then
            redraw_needed=1
            if [ "$idx" -gt 1 ] 2>/dev/null; then
              MOTD_CONFIG_SELECTED=$((idx - 1))
            else
              MOTD_CONFIG_SELECTED=1
            fi
          else
            motd_render_launcher_prompt '' '移除失败，请稍后再试'
          fi
        else
          motd_hide_menu_cursor
        fi
        ;;
      esc)
        return 0
        ;;
      command:settings)
        return 0
        ;;
      command:quit)
        MOTD_REQUEST_SHELL_EXIT=1
        return 0
        ;;
      *)
        motd_hide_menu_cursor
        ;;
    esac
  done
}

motd_run_project_update() {
  local component="$1"

  motd_bootstrap_component_now "$component" update || true
  sleep 0.8
}

motd_run_system_menu() {
  local action='' last_size='' last_key='' current_size='' current_key='' redraw_needed=1
  local selected=1

  MOTD_REQUEST_SHELL_EXIT=0
  MOTD_CONFIG_TOTAL=5
  MOTD_CONFIG_SELECTED="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
  motd_input_reset config_select
  while :; do
    current_size="$(get_term_size_safe)"
    current_key="$(motd_redraw_size_key "$current_size")"
    if [ "$redraw_needed" = "1" ] || [ "$current_key" != "$last_key" ]; then
      motd_input_reset config_select
      selected="$(motd_clamp_menu_selection "${MOTD_CONFIG_SELECTED:-1}" "$MOTD_CONFIG_TOTAL")"
      MOTD_CONFIG_SELECTED="$selected"
      motd_render_config_menu_screen "$MOTD_SETTINGS_TITLE" \
        "  ${MOTD_MENU_FG_CYAN_DIM}↑↓ 选择  ·  输入序号  ·  Enter 进入  ·  Esc 返回主界面${MOTD_MENU_RESET}" \
        "$(motd_config_item_line "$selected" 1 '启动项管理')" \
        "$(motd_config_item_line "$selected" 2 '开屏动画速度')" \
        "$(motd_config_item_line "$selected" 3 'PROJECT凌设置')" \
        "$(motd_config_item_line "$selected" 4 '检测 PROJECT萤 更新')" \
        "$(motd_config_item_line "$selected" 5 '检测 PROJECT凌 更新')"
      motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
      last_size="$current_size"
      last_key="$current_key"
      redraw_needed=0
      MOTD_INPUT_DIRTY=0
    fi

    motd_read_launcher_input || true
    action="${MOTD_INPUT_ACTION:-idle}"
    case "$action" in
      idle)
        continue
        ;;
      submit:1)
        motd_run_launcher_items_menu || true
        if [ "${MOTD_REQUEST_SHELL_EXIT:-0}" = "1" ]; then
          return 0
        fi
        motd_input_reset config_select
        redraw_needed=1
        ;;
      submit:2)
        motd_run_speed_menu || true
        if [ "${MOTD_REQUEST_SHELL_EXIT:-0}" = "1" ]; then
          return 0
        fi
        motd_input_reset config_select
        redraw_needed=1
        ;;
      submit:3)
        motd_launcher_log "menu_enter projectling_settings"
        motd_move_cursor_below_menu
        tty_printf '\n'
        motd_restore_tty_mode || true
        tput cnorm >/dev/null 2>&1 || true
        motd_open_projectling_settings root || true
        motd_set_menu_tty_mode || true
        motd_input_reset config_select
        redraw_needed=1
        ;;
      submit:4)
        motd_run_project_update projectying
        motd_input_reset config_select
        redraw_needed=1
        ;;
      submit:5)
        motd_run_project_update projectling
        motd_input_reset config_select
        redraw_needed=1
        ;;
      command:settings)
        motd_input_reset config_select
        redraw_needed=1
        ;;
      command:quit)
        MOTD_REQUEST_SHELL_EXIT=1
        return 0
        ;;
      submit:0)
        return 0
        ;;
      submit:|esc)
        return 0
        ;;
      *)
        motd_hide_menu_cursor
        ;;
    esac
  done
}

motd_show_launcher_screen() {
  local selected="${1:-1}"
  local total=1
  motd_launcher_menu_styles_init launcher
  total="$(motd_launcher_menu_total)"
  selected="$(motd_clamp_menu_selection "$selected" "$total")"
  MOTD_MENU_SELECTED="$selected"
  motd_render_launcher_frame final
  motd_render_launcher_menu_static "$selected" 1
}

motd_run_launcher_menu() {
  local action=''
  local choice=''
  local item_count=0
  local current_size=''
  local layout_changed=1
  local redraw_needed=1
  local selected=1
  local total_count=1
  local settings_choice=1

  MOTD_KEEP_SCREEN=1
  MOTD_REQUEST_SHELL_EXIT=0
  motd_refresh_launcher_env || true
  current_size="$(get_term_size_safe)"
  motd_launcher_capture_layout_state "$current_size"
  motd_set_menu_tty_mode || true
  trap 'motd_mark_winch_dirty' WINCH
  motd_flush_tty_input || true
  motd_input_reset launcher
  tput civis >/dev/null 2>&1 || true
  motd_show_launcher_intro 1
  MOTD_INPUT_DIRTY=0
  selected="${MOTD_MENU_SELECTED:-1}"
  current_size="$(get_term_size_safe)"
  motd_launcher_capture_layout_state "$current_size"
  motd_launcher_commit_redraw_state
  redraw_needed=0
  motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"

  while :; do
    if [ "$redraw_needed" = "1" ] || [ "${MOTD_WINCH_DIRTY:-0}" = "1" ]; then
      current_size="$(get_term_size_safe)"
      if [ "$redraw_needed" != "1" ] && [ "${MOTD_WINCH_DIRTY:-0}" = "1" ] && motd_launcher_handle_height_resize "$current_size" "${MOTD_MENU_SELECTED:-$selected}"; then
        selected="${MOTD_MENU_SELECTED:-$selected}"
      else
        layout_changed=1
        motd_launcher_needs_redraw "$current_size" && layout_changed=0
        if [ "$redraw_needed" = "1" ] || [ "$layout_changed" = "0" ]; then
          if [ "$layout_changed" != "0" ]; then
            motd_launcher_capture_layout_state "$current_size"
          fi
          tput civis >/dev/null 2>&1 || true
          motd_redraw_scan_transition
          motd_input_reset launcher
          motd_clear_launcher_previous_layout
          total_count="$(motd_launcher_menu_total)"
          selected="$(motd_clamp_menu_selection "${MOTD_MENU_SELECTED:-$selected}" "$total_count")"
          motd_show_launcher_screen "$selected"
          MOTD_INPUT_DIRTY=0
          motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
          motd_launcher_capture_layout_state "$current_size"
          motd_launcher_commit_redraw_state
          redraw_needed=0
        fi
      fi
    fi
    motd_read_launcher_input || true
    action="${MOTD_INPUT_ACTION:-idle}"
    item_count="${#MOTD_LAUNCHER_IDS[@]}"
    settings_choice=$((item_count + 1))

    case "$action" in
      submit:[0-9]*)
        choice="${action#submit:}"
        case "$choice" in
          ''|*[!0-9]*)
            motd_render_launcher_prompt '' '请使用 ↑↓ 选择，Enter 启动，Esc 返回 Shell'
            ;;
          *)
            if [ "$choice" -eq "$settings_choice" ] 2>/dev/null; then
              motd_run_system_menu || true
              if [ "${MOTD_REQUEST_SHELL_EXIT:-0}" = "1" ]; then
                motd_launcher_log "menu_shell source=command:quit"
                motd_prepare_shell_resume
                trap - WINCH
                motd_restore_tty_mode || true
                return 0
              fi
              motd_input_reset launcher
              redraw_needed=1
              continue
            fi
            if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$item_count" ] 2>/dev/null; then
              break
            fi
            motd_render_launcher_prompt '' '请使用 ↑↓ 选择，Enter 启动，Esc 返回 Shell'
            ;;
        esac
        ;;
      command:settings)
        motd_run_system_menu || true
        if [ "${MOTD_REQUEST_SHELL_EXIT:-0}" = "1" ]; then
          motd_launcher_log "menu_shell source=command:quit"
          motd_prepare_shell_resume
          trap - WINCH
          motd_restore_tty_mode || true
          return 0
        fi
        motd_input_reset launcher
        redraw_needed=1
        continue
        ;;
      command:quit)
        motd_launcher_log "menu_shell source=command:quit"
        motd_prepare_shell_resume
        trap - WINCH
        motd_restore_tty_mode || true
        return 0
        ;;
      submit:r)
        if [ "${MOTD_LAUNCHER_CARD_HEIGHT:-0}" -gt 0 ] 2>/dev/null && [ "${MOTD_LAUNCHER_CARD_TOP_ROW:-0}" -gt 0 ] 2>/dev/null; then
          tput civis >/dev/null 2>&1 || true
          motd_input_reset launcher
          MOTD_CARD_CACHE_KEY=''
          MOTD_CARD_CACHE_LINES=()
          MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT=0
          if [ "${AITERMUX_MOTD_LAUNCHER_CARD_ANIM:-1}" != "0" ] && motd_animate_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-1}" 1 1; then
            MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
            MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
            MOTD_INPUT_DIRTY=0
            motd_launcher_capture_layout_state "$(get_term_size_safe)"
            motd_launcher_commit_redraw_state
            redraw_needed=0
            motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
            continue
          fi
          if [ "${MOTD_LAUNCHER_ANIM_ABORTED_LAYOUT:-0}" = "1" ]; then
            redraw_needed=1
            continue
          fi
          if motd_render_launcher_card "${MOTD_LAUNCHER_CARD_TOP_ROW:-1}" 1; then
            MOTD_LAST_CARD_TOP_ROW="${MOTD_LAUNCHER_CARD_TOP_ROW:-0}"
            MOTD_LAST_CARD_HEIGHT="${MOTD_LAUNCHER_CARD_HEIGHT:-0}"
            MOTD_INPUT_DIRTY=0
            motd_launcher_capture_layout_state "$(get_term_size_safe)"
            motd_launcher_commit_redraw_state
            redraw_needed=0
            motd_place_input_cursor "${MOTD_INPUT_VALUE:-}"
            continue
          fi
        elif motd_reroll_projectling_card; then
          redraw_needed=1
          continue
        fi
        motd_render_launcher_prompt '' '重新抽卡失败，请稍后再试'
        ;;
      submit:|esc)
        motd_launcher_log "menu_shell source=${action%%:*}"
        motd_prepare_shell_resume
        trap - WINCH
        motd_restore_tty_mode || true
        return 0
        ;;
      submit:*)
        motd_render_launcher_prompt '' '请使用 ↑↓ 选择，Enter 启动，Esc 返回 Shell'
        ;;
      idle)
        ;;
    esac
  done

  motd_launcher_log "menu_enter choice=$choice"
  motd_move_cursor_below_menu
  tty_printf '\n'
  trap - WINCH
  motd_restore_tty_mode || true
  tput cnorm >/dev/null 2>&1 || true
  motd_launch_choice "$choice" || true
  return 0
}

motd_prompt_after_anim() {
  motd_run_launcher_menu || true
  return 0
}

META_REASON="done"
write_meta_once || true
motd_prompt_after_anim || true

exit 0
