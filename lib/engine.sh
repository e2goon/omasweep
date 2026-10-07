#!/usr/bin/env bash

TARGET_IDS=()
declare -A T_SECTION T_TIER T_SUDO T_LABEL T_NOTE T_BUSY T_PATHS
declare -A R_BYTES R_STATUS R_NOTE
SCANNED=()

OMS_PACMAN_KEEP=${OMS_PACMAN_KEEP:-2}
OMS_JOURNAL_KEEP=${OMS_JOURNAL_KEEP:-4weeks}
OMS_STALE_DAYS=${OMS_STALE_DAYS:-30}
OMS_PROJECT_DIRS=${OMS_PROJECT_DIRS:-"$HOME/Work:$HOME/Projects:$HOME/projects:$HOME/Code:$HOME/code:$HOME/src:$HOME/dev"}

CACHE=${XDG_CACHE_HOME:-$HOME/.cache}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}

join_by() {
  local separator=$1 out=${2:-}
  shift 2 || return 0
  local item
  for item in "$@"; do
    out+="$separator$item"
  done
  printf '%s' "$out"
}

plural() {
  local count=$1 word=$2
  if ((count == 1)); then
    printf '1 %s' "$word"
  else
    printf '%d %ss' "$count" "$word"
  fi
}

preview_list() {
  local limit=$1
  shift
  printf '%s' "$(join_by ", " "${@:1:limit}")"
  (($# > limit)) && printf ' +%d more' $(($# - limit))
  return 0
}

target() {
  local id=$1
  TARGET_IDS+=("$id")
  T_SECTION[$id]=$2
  T_TIER[$id]=$3
  T_SUDO[$id]=$4
  T_LABEL[$id]=$5
  T_NOTE[$id]=${6:-}
  T_BUSY[$id]=${7:-}
}

paths() {
  local id=$1 pattern
  shift
  for pattern in "$@"; do
    T_PATHS[$id]+="$pattern"$'\t\t\n'
  done
}

app_path() {
  local id=$1 pattern=$2 name=$3 busy=$4
  T_PATHS[$id]+="$pattern"$'\t'"$name"$'\t'"$busy"$'\n'
}

lock_token() {
  printf 'lock:%s' "${1// /%20}"
}

declare -A LOCK_CACHE
FLATPAK_RUNNING=""

lock_alive() {
  local lock=$1 target pid
  target=$(readlink "$lock" 2>/dev/null) || return 1
  pid=${target##*[-+]}
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

token_busy() {
  local token=$1 lock
  case $token in
    lock:*)
      lock=${token#lock:}
      while IFS= read -r lock; do
        lock_alive "$lock" && return 0
      done < <(compgen -G "${lock//%20/ }" 2>/dev/null)
      return 1
      ;;
    match:*)
      lock=${token#match:}
      pgrep -u "$UID" -f -- "${lock//%20/ }" >/dev/null 2>&1
      ;;
    name:*)
      return 1
      ;;
    flatpak:*)
      if [[ -z $FLATPAK_RUNNING ]]; then
        FLATPAK_RUNNING=" $(flatpak ps --columns=application 2>/dev/null | tr '\n' ' ') "
      fi
      [[ $FLATPAK_RUNNING == *" ${token#flatpak:} "* ]]
      ;;
    *)
      pgrep -u "$UID" -x -- "$token" >/dev/null 2>&1
      ;;
  esac
}

busy_spec() {
  local spec=$1 token tokens=()
  [[ -n $spec ]] || return 1
  if [[ -n ${LOCK_CACHE[$spec]:-} ]]; then
    [[ ${LOCK_CACHE[$spec]} == 1 ]]
    return
  fi
  read -r -a tokens <<<"$spec"
  for token in "${tokens[@]}"; do
    if token_busy "$token"; then
      LOCK_CACHE[$spec]=1
      return 0
    fi
  done
  LOCK_CACHE[$spec]=0
  return 1
}

busy_label() {
  local spec=$1 token
  for token in $spec; do
    if [[ $token == name:* ]]; then
      token=${token#name:}
      printf '%s' "${token//%20/ }"
      return
    fi
  done
  for token in $spec; do
    case $token in
      lock:* | match:* | flatpak:*) continue ;;
      *)
        printf '%s' "$token"
        return
        ;;
    esac
  done
  printf 'the app'
}

PATH_LIST=()
PATH_SKIPPED=()

resolve_paths() {
  local id=$1 pattern name busy match
  PATH_LIST=()
  PATH_SKIPPED=()
  [[ -n ${T_PATHS[$id]:-} ]] || return 0
  while IFS=$'\t' read -r pattern name busy; do
    [[ -n $pattern ]] || continue
    while IFS= read -r match; do
      [[ -n $match && -e $match && ! -L $match ]] || continue
      path_covered "$match" && continue
      if [[ -n $busy ]] && busy_spec "$busy"; then
        PATH_SKIPPED+=("${name:-$match}")
        continue
      fi
      PATH_LIST+=("$match")
    done < <(glob_expand "$pattern")
  done <<<"${T_PATHS[$id]}"
}

unique_names() {
  printf '%s\n' "$@" | awk 'NF && !seen[$0]++'
}

scan_paths() {
  local id=$1 entry path kept=() open=()
  resolve_paths "$id"
  mapfile -t open < <(unique_names "${PATH_SKIPPED[@]}")
  if ((${#PATH_LIST[@]} == 0)); then
    ((${#open[@]})) || return 1
    SCAN_BYTES=0
    SCAN_BUSY=$(preview_list 2 "${open[@]}")
    return 0
  fi
  SCAN_BYTES=$(size_of "${PATH_LIST[@]}")
  for entry in "${WHITELIST[@]}"; do
    for path in "${PATH_LIST[@]}"; do
      [[ $entry == "$path"/* ]] && mapfile -t -O "${#kept[@]}" kept < <(glob_expand "$entry")
    done
  done
  ((${#kept[@]})) && SCAN_BYTES=$((SCAN_BYTES - $(size_of "${kept[@]}")))
  ((SCAN_BYTES >= 0)) || SCAN_BYTES=0
  if ((${#open[@]})); then
    SCAN_NOTE="${SCAN_NOTE:+$SCAN_NOTE · }skipping open: $(preview_list 2 "${open[@]}")"
  fi
  return 0
}

clean_paths() {
  local id=$1 path failed=0
  LOCK_CACHE=()
  resolve_paths "$id"
  for path in "${PATH_LIST[@]}"; do
    clear_contents "$path" || failed=1
  done
  return "$failed"
}

scan_target() {
  local id=$1
  SCAN_BYTES=0
  SCAN_NOTE=${T_NOTE[$id]}
  SCAN_BUSY=""
  target_whitelisted "$id" && return 1
  if declare -F "scan_$id" >/dev/null; then
    "scan_$id" || return 1
  else
    scan_paths "$id" || return 1
  fi
  if [[ -z $SCAN_BUSY && -n ${T_BUSY[$id]} ]] && busy_spec "${T_BUSY[$id]}"; then
    SCAN_BUSY=$(busy_label "${T_BUSY[$id]}")
  fi
  if [[ -n $SCAN_BUSY ]]; then
    R_STATUS[$id]=busy
    SCAN_NOTE="close $SCAN_BUSY to include this"
  elif ((SCAN_BYTES == 0)); then
    return 1
  else
    R_STATUS[$id]=ready
  fi
  R_BYTES[$id]=$SCAN_BYTES
  R_NOTE[$id]=$SCAN_NOTE
  SCANNED+=("$id")
}

CLEAN_SKIPPED=3

clean_target() {
  local id=$1
  LOCK_CACHE=()
  FLATPAK_RUNNING=""
  if [[ -n ${T_BUSY[$id]} ]] && busy_spec "${T_BUSY[$id]}"; then
    oplog "SKIPPED $id, $(busy_label "${T_BUSY[$id]}") is running"
    return "$CLEAN_SKIPPED"
  fi
  if declare -F "clean_$id" >/dev/null; then
    "clean_$id"
  else
    clean_paths "$id"
  fi
}

ranked_targets() {
  local id
  for id in "${SCANNED[@]}"; do
    local tier_rank=0 status_rank=0
    [[ ${T_TIER[$id]} == review ]] && tier_rank=1
    [[ ${R_STATUS[$id]} == busy ]] && status_rank=1
    printf '%d\t%d\t%d\t%s\n' "$status_rank" "$tier_rank" "$((-${R_BYTES[$id]}))" "$id"
  done | sort -t$'\t' -k1,1n -k2,2n -k3,3n | cut -f4
}
