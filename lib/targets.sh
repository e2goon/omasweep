#!/usr/bin/env bash

TARGET_IDS=()
declare -A T_SECTION T_TIER T_SUDO T_LABEL T_NOTE T_BUSY T_PATHS

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
  ((count == 1)) && printf '1 %s' "$word" || printf '%d %ss' "$count" "$word"
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
  local id=$1
  shift
  T_PATHS[$id]=$(printf '%s\n' "$@")
}

target_paths() {
  local id=$1
  [[ -n ${T_PATHS[$id]:-} ]] || return 0
  printf '%s\n' "${T_PATHS[$id]}"
}

scan_paths() {
  local id=$1 list=() path
  while IFS= read -r path; do
    [[ -n $path && -e $path ]] && ! path_covered "$path" && list+=("$path")
  done < <(target_paths "$id")
  ((${#list[@]})) || return 1
  SCAN_BYTES=$(size_of "${list[@]}")
  local entry kept=()
  for entry in "${WHITELIST[@]}"; do
    for path in "${list[@]}"; do
      [[ $entry == "$path"/* ]] && mapfile -t -O "${#kept[@]}" kept < <(glob_expand "$entry")
    done
  done
  ((${#kept[@]})) && SCAN_BYTES=$((SCAN_BYTES - $(size_of "${kept[@]}")))
  ((SCAN_BYTES >= 0)) || SCAN_BYTES=0
}

clean_paths() {
  local id=$1 path failed=0
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    clear_contents "$path" || failed=1
  done < <(target_paths "$id")
  return "$failed"
}

OMS_PACMAN_KEEP=${OMS_PACMAN_KEEP:-2}
OMS_JOURNAL_KEEP=${OMS_JOURNAL_KEEP:-4weeks}
OMS_STALE_DAYS=${OMS_STALE_DAYS:-30}
OMS_PROJECT_DIRS=${OMS_PROJECT_DIRS:-"$HOME/Work:$HOME/Projects:$HOME/projects:$HOME/Code:$HOME/code:$HOME/src:$HOME/dev"}

cache=${XDG_CACHE_HOME:-$HOME/.cache}
data=${XDG_DATA_HOME:-$HOME/.local/share}

target pacman "System" safe 1 "Old package versions" "keeps the newest $OMS_PACMAN_KEEP like omarchy update" "pacman yay paru"
target journal "System" safe 1 "Archived journal logs" "older than $OMS_JOURNAL_KEEP"
target coredumps "System" safe 1 "Crash dumps" "systemd-coredump archive"
target thumbnails "System" safe 0 "Thumbnail cache" "regenerated on demand"
paths thumbnails "$cache/thumbnails"
target orphans "System" review 1 "Orphaned packages" "installed as dependencies and no longer needed" "pacman yay paru"
target trash "System" review 0 "Trash" "files you deleted"
paths trash "$data/Trash/files" "$data/Trash/info"

target mise "Tools" safe 0 "Old mise tool versions" "mise prune" "mise"

target docker-build "Containers" safe 0 "Docker build cache" "docker builder prune"
target docker-images "Containers" review 0 "Unused Docker images" "every image no container uses, pulled again when needed"

target aur "Developer caches" safe 0 "AUR build cache" "yay and paru clones" "yay paru makepkg"
paths aur "$cache/yay" "$cache/paru"
target npm "Developer caches" safe 0 "npm cache" "downloaded again on install" "npm npx"
paths npm "$HOME/.npm/_cacache" "$HOME/.npm/_npx" "$HOME/.npm/_logs"
target pnpm "Developer caches" safe 0 "pnpm metadata cache" "registry metadata" "pnpm"
paths pnpm "$cache/pnpm"
target pnpm-store "Developer caches" safe 0 "pnpm store" "packages no project uses" "pnpm"
target uv "Developer caches" safe 0 "uv cache" "downloaded again on install" "uv"
paths uv "$cache/uv"
target pip "Developer caches" safe 0 "pip cache" "downloaded again on install" "pip pip3"
paths pip "$cache/pip"
target bun "Developer caches" safe 0 "Bun cache" "downloaded again on install" "bun"
paths bun "$HOME/.bun/install/cache" "$cache/.bun"
target go "Developer caches" safe 0 "Go build cache" "rebuilt on next build" "go"
paths go "$cache/go-build"
target cargo "Developer caches" safe 0 "Cargo registry cache" "downloaded again on build" "cargo"
paths cargo "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src"
target build-misc "Developer caches" safe 0 "Other build caches" "node-gyp, TypeScript, Yarn, Deno, mise downloads" "yarn deno"
paths build-misc "$cache/node-gyp" "$cache/typescript" "$cache/yarn" "$cache/deno" "$cache/mise"

target chromium "Browsers" safe 0 "Chromium cache" "web cache only, logins stay" "chromium"
paths chromium "$cache/chromium"
target chrome "Browsers" safe 0 "Chrome cache" "web cache only, logins stay" "chrome"
paths chrome "$cache/google-chrome"
target brave "Browsers" safe 0 "Brave cache" "web cache only, logins stay" "brave"
paths brave "$cache/BraveSoftware"
target firefox "Browsers" safe 0 "Firefox cache" "web cache only, logins stay" "firefox"
paths firefox "$cache/mozilla"

target steam-shaders "Games" review 0 "Steam shader cache" "rebuilt on next launch with some stutter" "steam"
paths steam-shaders "$data/Steam/steamapps/shadercache"

target node-modules "Projects" review 0 "Stale node_modules" "untouched for $OMS_STALE_DAYS+ days" "node npm pnpm"

unset cache data

scan_pacman() {
  command -v paccache >/dev/null 2>&1 || return 1
  local old uninstalled
  old=$(paccache -dk"$OMS_PACMAN_KEEP" 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  uninstalled=$(paccache -duk0 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  SCAN_BYTES=$(($(iec_to_bytes "$old") + $(iec_to_bytes "$uninstalled")))
}

clean_pacman() {
  run sudo -n paccache -rk"$OMS_PACMAN_KEEP" && run sudo -n paccache -ruk0
}

scan_journal() {
  [[ -d /var/log/journal ]] || return 1
  local days
  days=$(journal_keep_days)
  SCAN_BYTES=$(find /var/log/journal -type f -name '*@*.journal*' -mtime +"$days" -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
}

journal_keep_days() {
  local value=$OMS_JOURNAL_KEEP number
  number=${value%%[!0-9]*}
  number=${number:-28}
  case $value in
    *week*) printf '%s' $((number * 7)) ;;
    *month*) printf '%s' $((number * 30)) ;;
    *) printf '%s' "$number" ;;
  esac
}

clean_journal() {
  run sudo -n journalctl --vacuum-time="$OMS_JOURNAL_KEEP"
}

scan_coredumps() {
  [[ -d /var/lib/systemd/coredump ]] || return 1
  SCAN_BYTES=$(find /var/lib/systemd/coredump -type f -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
}

clean_coredumps() {
  run sudo -n find /var/lib/systemd/coredump -mindepth 1 -type f -delete
}

ORPHANS=()

scan_orphans() {
  command -v pacman >/dev/null 2>&1 || return 1
  mapfile -t ORPHANS < <(pacman -Qdtq 2>/dev/null)
  ((${#ORPHANS[@]})) || return 1
  SCAN_BYTES=0
  local size
  while IFS= read -r size; do
    SCAN_BYTES=$((SCAN_BYTES + $(iec_to_bytes "$size")))
  done < <(LC_ALL=C pacman -Qi "${ORPHANS[@]}" 2>/dev/null | sed -n 's/^Installed Size *: *//p')
  SCAN_NOTE="$(plural ${#ORPHANS[@]} package): $(join_by ", " "${ORPHANS[@]:0:4}")"
  ((${#ORPHANS[@]} > 4)) && SCAN_NOTE+=" +$((${#ORPHANS[@]} - 4)) more"
  return 0
}

clean_orphans() {
  ((${#ORPHANS[@]})) || return 0
  run sudo -n pacman -Rns --noconfirm "${ORPHANS[@]}"
}

scan_mise() {
  command -v mise >/dev/null 2>&1 || return 1
  local output count list=()
  output=$(mise prune --dry-run 2>&1) || return 1
  count=$(grep -c 'is prunable' <<<"$output")
  ((count > 0)) || return 1
  while IFS= read -r path; do
    list+=("${path/#\~/$HOME}")
  done < <(sed -n 's/.*\[dryrun\] *remove \(.*\)$/\1/p' <<<"$output")
  SCAN_BYTES=$(size_of "${list[@]}")
  SCAN_NOTE="$(plural "$count" version) no config needs"
}

clean_mise() {
  run mise prune -y
}

DOCKER_DF=""

docker_reclaimable() {
  docker_ready || return 1
  local value
  [[ -n $DOCKER_DF ]] || DOCKER_DF=$(timeout 20 docker system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null)
  value=$(awk -F'\t' -v t="$1" '$1 == t { print $2 }' <<<"$DOCKER_DF")
  [[ -n $value ]] || return 1
  SCAN_BYTES=$(si_to_bytes "$value")
}

scan_docker-build() {
  docker_reclaimable "Build Cache"
}

clean_docker-build() {
  run docker builder prune -af
}

scan_docker-images() {
  docker_reclaimable "Images"
}

clean_docker-images() {
  run docker image prune -af
}

scan_pnpm-store() {
  command -v pnpm >/dev/null 2>&1 || return 1
  [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/pnpm/store ]] || return 1
  SCAN_BYTES=-1
  SCAN_NOTE="unreferenced packages only, size known after pruning"
}

clean_pnpm-store() {
  run pnpm store prune
}

clean_uv() {
  if command -v uv >/dev/null 2>&1; then
    run uv cache clean
  else
    clean_paths uv
  fi
}

STALE_MODULES=()

scan_node-modules() {
  local roots=() root
  IFS=: read -r -a roots <<<"$OMS_PROJECT_DIRS"
  STALE_MODULES=()
  for root in "${roots[@]}"; do
    [[ -d $root ]] || continue
    while IFS= read -r -d '' dir; do
      path_covered "$dir" && continue
      [[ -n $(find "$dir" -maxdepth 1 -newermt "-$OMS_STALE_DAYS days" -print -quit 2>/dev/null) ]] && continue
      [[ -n $(find "${dir%/node_modules}" -maxdepth 1 -newermt "-$OMS_STALE_DAYS days" -print -quit 2>/dev/null) ]] && continue
      STALE_MODULES+=("$dir")
    done < <(find "$root" -maxdepth 4 -type d -name node_modules -prune -print0 2>/dev/null)
  done
  ((${#STALE_MODULES[@]})) || return 1
  SCAN_BYTES=$(size_of "${STALE_MODULES[@]}")
  local names=() dir
  for dir in "${STALE_MODULES[@]:0:3}"; do
    names+=("$(basename "${dir%/node_modules}")")
  done
  SCAN_NOTE="$(plural ${#STALE_MODULES[@]} project): $(join_by ", " "${names[@]}")"
  ((${#STALE_MODULES[@]} > 3)) && SCAN_NOTE+=" +$((${#STALE_MODULES[@]} - 3)) more"
  SCAN_NOTE+=" · pnpm hard links may free less"
}

clean_node-modules() {
  local dir failed=0
  for dir in "${STALE_MODULES[@]}"; do
    remove_path "$dir" || failed=1
  done
  return "$failed"
}

declare -A R_BYTES R_STATUS R_NOTE
SCANNED=()

scan_target() {
  local id=$1
  SCAN_BYTES=0
  SCAN_NOTE=${T_NOTE[$id]}
  BUSY_NAME=""
  if target_whitelisted "$id"; then
    return 1
  fi
  if declare -F "scan_$id" >/dev/null; then
    "scan_$id" || return 1
  else
    scan_paths "$id" || return 1
  fi
  local busy=()
  read -r -a busy <<<"${T_BUSY[$id]}"
  if ((${#busy[@]})) && process_running "${busy[@]}"; then
    R_STATUS[$id]=busy
    SCAN_NOTE="close $BUSY_NAME to include this"
  elif ((SCAN_BYTES == 0)); then
    return 1
  else
    R_STATUS[$id]=ready
  fi
  R_BYTES[$id]=$SCAN_BYTES
  R_NOTE[$id]=$SCAN_NOTE
  SCANNED+=("$id")
}

clean_target() {
  local id=$1
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
