#!/usr/bin/env bash

CACHE=${XDG_CACHE_HOME:-$HOME/.cache}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}

OMS_CONFIG_DIR=$CONFIG/omasweep
OMS_STATE_DIR=$STATE/omasweep
OMS_WHITELIST=$OMS_CONFIG_DIR/whitelist
OMS_OPLOG=$OMS_STATE_DIR/operations.log
OMS_OPLOG_MAX=5242880

DRY_RUN=${OMS_DRY_RUN:-0}
DEBUG=${OMS_DEBUG:-0}
WHITELIST=()
WHITELIST_MATCHES=()
DRY_ACTIONS=()
TEMP_FILES=()
OPLOG_STATE=new

have() {
  command -v "$1" >/dev/null 2>&1
}

debug() {
  [[ $DEBUG == 1 ]] && printf '%s\n' "${C_DIM}  [debug] $*${C_RESET}" >&2
  return 0
}

load_whitelist() {
  WHITELIST=()
  WHITELIST_MATCHES=()
  [[ -f $OMS_WHITELIST ]] || return 0
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line#"${line%%[![:space:]]*}"}
    [[ -n $line && $line != \#* ]] || continue
    line=${line%%[[:space:]]#*}
    line=${line%"${line##*[![:space:]]}"}
    line=${line/#\~/$HOME}
    WHITELIST+=("$line")
    [[ $line == /* ]] && mapfile -t -O "${#WHITELIST_MATCHES[@]}" WHITELIST_MATCHES < <(compgen -G "$line")
  done <"$OMS_WHITELIST"
  return 0
}

target_whitelisted() {
  local id=$1 entry
  for entry in "${WHITELIST[@]}"; do
    [[ $entry == "$id" ]] && return 0
  done
  return 1
}

path_covered() {
  local path=${1%/} entry
  for entry in "${WHITELIST[@]}"; do
    [[ $entry == /* ]] || continue
    entry=${entry%/}
    if [[ $path == $entry || $path == $entry/* ]]; then
      return 0
    fi
  done
  return 1
}

path_protected() {
  path_covered "$1" || protected_inside "$1"
}

path_safe() {
  local path=$1
  [[ $path == /* ]] || return 1
  [[ $path != *"/../"* && $path != *"/.." ]] || return 1
  case ${path%/} in
    "" | "$HOME" | /home | /root | /usr | /etc | /var | /boot | /opt) return 1 ;;
  esac
  [[ $path == "$HOME"/* ]]
}

size_of() {
  local paths=() path total
  for path in "$@"; do
    [[ -e $path ]] && paths+=("$path")
  done
  if ((${#paths[@]})); then
    total=$(du -scB1 -- "${paths[@]}" 2>/dev/null)
    total=${total##*$'\n'}
    total=${total%%[[:space:]]*}
  fi
  printf '%s' "${total:-0}"
  return 0
}

file_bytes() {
  find "$@" -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'
  return 0
}

protected_inside() {
  local dir=${1%/} match
  for match in "${WHITELIST_MATCHES[@]}"; do
    [[ $match == "$dir"/* ]] && return 0
  done
  return 1
}

iec_to_bytes() {
  local value=${1// /}
  value=${value%B}
  value=${value%i}
  [[ -n $value ]] || {
    printf '0'
    return
  }
  numfmt --from=iec "${value^^}" 2>/dev/null || printf '0'
}

si_to_bytes() {
  local value=${1%% *}
  value=${value%B}
  [[ -n $value ]] || {
    printf '0'
    return
  }
  value=${value/k/K}
  numfmt --from=si "$value" 2>/dev/null || printf '0'
}

free_bytes() {
  df -B1 --output=avail "$HOME" 2>/dev/null | awk 'NR == 2 { print $1 + 0 }'
}

open_oplog() {
  OPLOG_STATE=off
  mkdir -p "$OMS_STATE_DIR" 2>/dev/null || return 0
  [[ -L $OMS_OPLOG ]] && return 0
  if [[ -f $OMS_OPLOG ]] && (($(stat -c %s "$OMS_OPLOG") > OMS_OPLOG_MAX)); then
    mv -f "$OMS_OPLOG" "$OMS_OPLOG.1"
  fi
  OPLOG_STATE=on
}

oplog() {
  [[ $DRY_RUN == 1 || -n ${OMS_NO_OPLOG:-} ]] && return 0
  [[ $OPLOG_STATE == new ]] && open_oplog
  [[ $OPLOG_STATE == on ]] || return 0
  printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*" >>"$OMS_OPLOG"
}

run() {
  debug "run: $*"
  if [[ $DRY_RUN == 1 ]]; then
    DRY_ACTIONS+=("$*")
    return 0
  fi
  local output status
  output=$("$@" 2>&1)
  status=$?
  [[ -n $output ]] && debug "$output"
  if ((status == 0)); then
    oplog "RAN $*"
  else
    oplog "FAILED ($status) $*"
  fi
  return "$status"
}

clear_contents() {
  local dir=$1 child failed=0
  [[ -d $dir && ! -L $dir ]] || return 0
  path_safe "$dir" || {
    oplog "SKIPPED unsafe path $dir"
    return 1
  }
  if path_covered "$dir"; then
    oplog "SKIPPED protected $dir"
    return 0
  fi
  if [[ $DRY_RUN == 1 ]]; then
    DRY_ACTIONS+=("empty ${dir/#$HOME/\~}")
    return 0
  fi
  shopt -s nullglob dotglob
  for child in "$dir"/*; do
    if path_protected "$child"; then
      oplog "SKIPPED protected $child"
      continue
    fi
    remove_path "$child" || failed=1
  done
  shopt -u nullglob dotglob
  return "$failed"
}

remove_path() {
  local path=$1
  [[ -e $path || -L $path ]] || return 0
  path_safe "$path" || {
    oplog "SKIPPED unsafe path $path"
    return 1
  }
  if path_protected "$path"; then
    oplog "SKIPPED protected $path"
    return 0
  fi
  debug "remove: $path"
  if [[ $DRY_RUN == 1 ]]; then
    DRY_ACTIONS+=("rm -rf ${path/#$HOME/\~}")
    return 0
  fi
  if rm -rf -- "$path" 2>/dev/null; then
    oplog "REMOVED $path"
  else
    [[ -L $path ]] || chmod -R u+w -- "$path" 2>/dev/null
    if rm -rf -- "$path" 2>/dev/null; then
      oplog "REMOVED $path"
    else
      oplog "FAILED $path"
      return 1
    fi
  fi
}

remove_temp_files() {
  ((${#TEMP_FILES[@]})) && rm -f -- "${TEMP_FILES[@]}"
  return 0
}

snapper_active() {
  [[ $(findmnt -no FSTYPE / 2>/dev/null) == btrfs ]] || return 1
  compgen -G "/etc/snapper/configs/*" >/dev/null
}
