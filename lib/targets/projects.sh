#!/usr/bin/env bash

target node-modules "Projects" review 0 "Stale node_modules" "untouched for $OMS_STALE_DAYS+ days" "node npm pnpm"

STALE_MODULES=()

scan_node-modules() {
  local roots=() root dir names=()
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
  for dir in "${STALE_MODULES[@]}"; do
    names+=("$(basename "${dir%/node_modules}")")
  done
  SCAN_NOTE="$(plural ${#STALE_MODULES[@]} project): $(preview_list 3 "${names[@]}") · pnpm hard links may free less"
}

clean_node-modules() {
  local dir failed=0
  for dir in "${STALE_MODULES[@]}"; do
    remove_path "$dir" || failed=1
  done
  return "$failed"
}
