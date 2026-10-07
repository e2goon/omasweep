#!/usr/bin/env bash

OMS_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/omasweep
OMS_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/omasweep
OMS_WHITELIST=$OMS_CONFIG_DIR/whitelist
OMS_OPLOG=$OMS_STATE_DIR/operations.log
OMS_OPLOG_MAX=5242880

DRY_RUN=${OMS_DRY_RUN:-0}
DEBUG=${OMS_DEBUG:-0}
WHITELIST=()
DRY_ACTIONS=()

debug() {
  [[ $DEBUG == 1 ]] && printf '%s\n' "${C_DIM}  [debug] $*${C_RESET}" >&2
  return 0
}

load_whitelist() {
  WHITELIST=()
  [[ -f $OMS_WHITELIST ]] || return 0
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n $line ]] || continue
    WHITELIST+=("${line/#\~/$HOME}")
  done <"$OMS_WHITELIST"
}

target_whitelisted() {
  local id=$1 entry
  for entry in "${WHITELIST[@]}"; do
    [[ $entry == "$id" ]] && return 0
  done
  return 1
}

glob_expand() {
  compgen -G "$1" || printf '%s\n' "$1"
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
  local path=${1%/} entry
  path_covered "$path" && return 0
  for entry in "${WHITELIST[@]}"; do
    [[ $entry == "$path"/* ]] && return 0
  done
  return 1
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
  local paths=() path
  for path in "$@"; do
    [[ -e $path ]] && paths+=("$path")
  done
  ((${#paths[@]})) || {
    printf '0'
    return
  }
  du -scB1 -- "${paths[@]}" 2>/dev/null | awk 'END { print $1 + 0 }'
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

oplog() {
  [[ $DRY_RUN == 1 || -n ${OMS_NO_OPLOG:-} ]] && return 0
  mkdir -p "$OMS_STATE_DIR" || return 0
  [[ -L $OMS_OPLOG ]] && return 0
  if [[ -f $OMS_OPLOG ]] && (($(stat -c %s "$OMS_OPLOG") > OMS_OPLOG_MAX)); then
    mv -f "$OMS_OPLOG" "$OMS_OPLOG.1"
  fi
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$OMS_OPLOG"
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
    chmod -R u+w -- "$path" 2>/dev/null
    if rm -rf -- "$path" 2>/dev/null; then
      oplog "REMOVED $path"
    else
      oplog "FAILED $path"
      return 1
    fi
  fi
}

snapper_active() {
  [[ $(findmnt -no FSTYPE / 2>/dev/null) == btrfs ]] || return 1
  compgen -G "/etc/snapper/configs/*" >/dev/null
}
