#!/usr/bin/env bash

target project-artifacts "Projects" review 0 "Stale project builds" "untouched for $OMS_STALE_DAYS+ days"

ARTIFACT_NAMES=(node_modules target .venv venv .next .nuxt .svelte-kit .turbo .parcel-cache .angular .gradle .dart_tool vendor
  .output .astro .expo coverage .tox .nox .pytest_cache .mypy_cache .ruff_cache .zig-cache zig-out .cxx)
ARTIFACT_MATCH=(-name "${ARTIFACT_NAMES[0]}")
for name in "${ARTIFACT_NAMES[@]:1}"; do
  ARTIFACT_MATCH+=(-o -name "$name")
done
unset name

ARTIFACTS=()

artifact_kind() {
  local dir=$1 parent=${1%/*}
  case ${dir##*/} in
    node_modules | .next | .nuxt | .svelte-kit | .turbo | .parcel-cache | .angular | .output | .astro | .expo | coverage)
      [[ -f $parent/package.json ]]
      ;;
    .tox | .nox | .pytest_cache | .mypy_cache | .ruff_cache)
      [[ -f $parent/pyproject.toml || -f $parent/setup.py || -f $parent/setup.cfg || -f $parent/tox.ini || -f $parent/noxfile.py ]]
      ;;
    .zig-cache | zig-out)
      [[ -f $parent/build.zig ]]
      ;;
    .cxx)
      compgen -G "$parent/build.gradle*" >/dev/null
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

# A folder git tracks files in is part of the project, whatever its name says
# (a committed coverage report, a vendored dependency). When git cannot answer,
# keep it.
git_tracked() {
  local dir=$1 parent=${1%/*} output
  have git || return 1
  git -C "$parent" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  output=$(git -C "$parent" ls-files -- "${dir##*/}" 2>/dev/null) || return 0
  [[ -n $output ]]
}

changed_recently() {
  local found
  found=$(find "$@" -newermt "-$OMS_STALE_DAYS days" -print -quit 2>/dev/null) || return 0
  [[ -n $found ]]
}

project_active() {
  local dir=$1
  changed_recently "$dir" -maxdepth 1 ||
    changed_recently "${dir%/*}" -maxdepth 3 \( "${ARTIFACT_MATCH[@]}" \) -prune -o
}

SKIP_REASON=""

artifact_removable() {
  if project_active "$1"; then
    SKIP_REASON="the project changed recently"
    return 1
  fi
  if git_tracked "$1"; then
    SKIP_REASON="git tracks files in it"
    return 1
  fi
}

scan_project-artifacts() {
  local roots=() root dir names=() kinds=()
  IFS=: read -r -a roots <<<"$OMS_PROJECT_DIRS"
  ARTIFACTS=()
  for root in "${roots[@]}"; do
    [[ -d $root && ! -L $root && $root != "$HOME" ]] || continue
    while IFS= read -r -d '' dir; do
      [[ ${dir%/*} == "$HOME" ]] && continue
      path_covered "$dir" && continue
      artifact_kind "$dir" || continue
      artifact_removable "$dir" || continue
      ARTIFACTS+=("$dir")
    done < <(find "$root" -maxdepth 6 -type d \( "${ARTIFACT_MATCH[@]}" \) -prune -print0 2>/dev/null)
  done
  ((${#ARTIFACTS[@]})) || return 1
  SCAN_BYTES=$(size_of "${ARTIFACTS[@]}")
  for dir in "${ARTIFACTS[@]}"; do
    names+=("${dir%/*}")
    kinds+=("${dir##*/}")
  done
  names=("${names[@]##*/}")
  mapfile -t names < <(unique_names "${names[@]}")
  mapfile -t kinds < <(unique_names "${kinds[@]}")
  SCAN_NOTE="$(plural ${#names[@]} project): $(preview_list 3 "${names[@]}") · $(join_by ", " "${kinds[@]}")"
}

clean_project-artifacts() {
  local dir failed=0
  for dir in "${ARTIFACTS[@]}"; do
    if ! artifact_removable "$dir"; then
      oplog "SKIPPED $dir, $SKIP_REASON"
      continue
    fi
    remove_path "$dir" || failed=1
  done
  return "$failed"
}
