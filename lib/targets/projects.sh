#!/usr/bin/env bash

target project-artifacts "Projects" review 0 "Stale project builds" "untouched for $OMS_STALE_DAYS+ days"

ARTIFACTS=()

artifact_kind() {
  local dir=$1 name parent
  name=$(basename "$dir")
  parent=$(dirname "$dir")
  case $name in
    node_modules | .next | .nuxt | .svelte-kit | .turbo | .parcel-cache | .angular)
      [[ -f $parent/package.json ]]
      ;;
    target)
      [[ -f $parent/Cargo.toml || -f $parent/pom.xml ]] && [[ ! -d $dir/deploy ]]
      ;;
    .venv | venv)
      [[ -f $dir/pyvenv.cfg ]]
      ;;
    .gradle)
      compgen -G "$parent/build.gradle*" >/dev/null || compgen -G "$parent/settings.gradle*" >/dev/null
      ;;
    .dart_tool)
      [[ -f $parent/pubspec.yaml ]]
      ;;
    vendor)
      [[ -f $parent/composer.json ]]
      ;;
    *) return 1 ;;
  esac
}

recently_touched() {
  [[ -n $(find "$1" -maxdepth 1 -newermt "-$OMS_STALE_DAYS days" -print -quit 2>/dev/null) ]]
}

scan_project-artifacts() {
  local roots=() root dir names=() kinds=()
  IFS=: read -r -a roots <<<"$OMS_PROJECT_DIRS"
  ARTIFACTS=()
  for root in "${roots[@]}"; do
    [[ -d $root && ! -L $root && $root != "$HOME" ]] || continue
    while IFS= read -r -d '' dir; do
      [[ $(dirname "$dir") == "$HOME" ]] && continue
      path_covered "$dir" && continue
      artifact_kind "$dir" || continue
      recently_touched "$dir" && continue
      recently_touched "$(dirname "$dir")" && continue
      ARTIFACTS+=("$dir")
    done < <(find "$root" -maxdepth 6 -type d \( -name node_modules -o -name target -o -name .venv -o -name venv \
      -o -name .next -o -name .nuxt -o -name .svelte-kit -o -name .turbo -o -name .parcel-cache -o -name .angular \
      -o -name .gradle -o -name .dart_tool -o -name vendor \) -prune -print0 2>/dev/null)
  done
  ((${#ARTIFACTS[@]})) || return 1
  SCAN_BYTES=$(size_of "${ARTIFACTS[@]}")
  for dir in "${ARTIFACTS[@]}"; do
    names+=("$(basename "$(dirname "$dir")")")
    kinds+=("$(basename "$dir")")
  done
  mapfile -t names < <(unique_names "${names[@]}")
  mapfile -t kinds < <(unique_names "${kinds[@]}")
  SCAN_NOTE="$(plural ${#names[@]} project): $(preview_list 3 "${names[@]}") · $(join_by ", " "${kinds[@]}")"
}

clean_project-artifacts() {
  local dir failed=0
  for dir in "${ARTIFACTS[@]}"; do
    if recently_touched "$dir" || recently_touched "$(dirname "$dir")"; then
      oplog "SKIPPED $dir, changed since the scan"
      continue
    fi
    remove_path "$dir" || failed=1
  done
  return "$failed"
}
