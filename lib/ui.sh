#!/usr/bin/env bash

GLYPH_OK="✓"
GLYPH_FAIL="✗"
GLYPH_DRY="→"
GLYPH_NOTE="◎"
GLYPH_SECTION="➤"
GLYPH_ON="●"
GLYPH_OFF="○"
GLYPH_SUB="↳"

SPIN_PID=""
SPIN_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

ui_init() {
  if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
    UI_TTY=1
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m' C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
  else
    UI_TTY=0
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN=""
  fi
}

has_gum() {
  [[ $UI_TTY == 1 ]] && have gum
}

human_size() {
  local bytes=${1:-0} units=(B KB MB GB TB) i=0 scale=1 tenths
  while ((bytes >= scale * 1024 && i < 4)); do
    scale=$((scale * 1024))
    i=$((i + 1))
  done
  if ((i == 0)); then
    printf '%d B' "$bytes"
    return
  fi
  tenths=$(((bytes * 10 + scale / 2) / scale))
  if ((tenths >= 10240 && i < 4)); then
    i=$((i + 1))
    tenths=$((tenths / 1024))
  fi
  printf '%d.%d %s' $((tenths / 10)) $((tenths % 10)) "${units[i]}"
}

color_size() {
  local bytes=$1 text
  if ((bytes < 0)); then
    printf '%s' "${C_DIM}unknown${C_RESET}"
    return
  fi
  text=$(human_size "$bytes")
  if ((bytes >= 1073741824)); then
    printf '%s' "${C_BOLD}${C_YELLOW}${text}${C_RESET}"
  elif ((bytes >= 1048576)); then
    printf '%s' "$text"
  else
    printf '%s' "${C_DIM}${text}${C_RESET}"
  fi
}

pad_right() {
  local text=$1 width=$2 len
  len=${#text}
  printf '%s%*s' "$text" $((width > len ? width - len : 0)) ""
}

banner() {
  local subtitle=$1
  printf '\n'
  printf ' %s\n' "${C_BOLD}${C_MAGENTA}┏━┓┏┳┓┏━┓┏━┓╻ ╻┏━╸┏━╸┏━┓${C_RESET}"
  printf ' %s\n' "${C_BOLD}${C_BLUE}┃ ┃┃┃┃┣━┫┗━┓┃╻┃┣╸ ┣╸ ┣━┛${C_RESET}"
  printf ' %s\n' "${C_BOLD}${C_CYAN}┗━┛╹ ╹╹ ╹┗━┛┗┻┛┗━╸┗━╸╹${C_RESET}"
  printf ' %s\n' "${C_DIM}${subtitle}${C_RESET}"
}

section() {
  printf '\n%s\n' "${C_BOLD}${C_MAGENTA}${GLYPH_SECTION} $1${C_RESET}"
}

note() {
  printf '%s\n' "${C_DIM}${GLYPH_NOTE} $*${C_RESET}"
}

warn() {
  printf '%s\n' "${C_YELLOW}${GLYPH_NOTE} $*${C_RESET}"
}

die() {
  printf '%s\n' "${C_RED}${GLYPH_FAIL} $*${C_RESET}" >&2
  exit 1
}

spin_start() {
  [[ $UI_TTY == 1 ]] || return 0
  local message=$1
  (
    trap 'exit 0' TERM
    local i=0
    while :; do
      printf '\r\e[K  %s %s' "${C_MAGENTA}${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}${C_RESET}" "${C_DIM}${message}${C_RESET}"
      i=$((i + 1))
      sleep 0.08
    done
  ) &
  SPIN_PID=$!
}

spin_stop() {
  if [[ -n $SPIN_PID ]]; then
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
    printf '\r\e[K'
  fi
}

cursor_hide() {
  [[ $UI_TTY == 1 ]] && printf '\e[?25l'
  return 0
}

cursor_show() {
  [[ $UI_TTY == 1 ]] && printf '\e[?25h'
  return 0
}

confirm() {
  local prompt=$1 answer
  if has_gum; then
    gum confirm --default=false "$prompt"
  else
    read -r -p "$prompt [y/N] " answer </dev/tty
    [[ $answer =~ ^[Yy]$ ]]
  fi
}
