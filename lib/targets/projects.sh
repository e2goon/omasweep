#!/usr/bin/env bash

target project-artifacts "Projects" review 0 "Stale project builds" "untouched for $OMS_STALE_DAYS+ days"

# Each build folder name and the project file that must sit next to it. Globs
# work. A folder only counts when one of its markers is present.
JS_MARKER=package.json
PY_MARKERS="pyproject.toml setup.py setup.cfg tox.ini noxfile.py"
declare -A ARTIFACT_MARKERS=(
  [node_modules]=$JS_MARKER [.next]=$JS_MARKER [.nuxt]=$JS_MARKER [.output]=$JS_MARKER
  [.svelte-kit]=$JS_MARKER [.astro]=$JS_MARKER [.expo]=$JS_MARKER [.turbo]=$JS_MARKER
  [.parcel-cache]=$JS_MARKER [.angular]=$JS_MARKER [coverage]=$JS_MARKER
  [.tox]=$PY_MARKERS [.nox]=$PY_MARKERS [.pytest_cache]=$PY_MARKERS
  [.mypy_cache]=$PY_MARKERS [.ruff_cache]=$PY_MARKERS
  [target]="Cargo.toml pom.xml"
  [.gradle]="build.gradle* settings.gradle*" [.cxx]="build.gradle*"
  [.zig-cache]=build.zig [zig-out]=build.zig
  [.dart_tool]=pubspec.yaml
  [vendor]=composer.json
  [.venv]="" [venv]=""
)
unset JS_MARKER PY_MARKERS

ARTIFACT_MATCH=()
for name in "${!ARTIFACT_MARKERS[@]}"; do
  ARTIFACT_MATCH+=(${ARTIFACT_MATCH[0]+-o} -name "$name")
done
unset name

ARTIFACTS=()

artifact_kind() {
  local dir=$1 parent=${1%/*} name=${1##*/} markers=() marker
  [[ -n ${ARTIFACT_MARKERS[$name]+set} ]] || return 1
  case $name in
    .venv | venv)
      [[ -f $dir/pyvenv.cfg ]]
      return
      ;;
    target)
      # Solana keeps program keys in target/deploy.
      [[ -d $dir/deploy ]] && return 1
      ;;
  esac
  read -r -a markers <<<"${ARTIFACT_MARKERS[$name]}"
  for marker in "${markers[@]}"; do
    compgen -G "$parent/$marker" >/dev/null && return 0
  done
  return 1
}

# A folder git tracks files in is part of the project, whatever its name says
# (a committed coverage report, a vendored dependency). When git cannot answer,
# keep it.
git_tracked() {
  local dir=$1 parent=${1%/*} output
  have git || return 1
  if ! output=$(LC_ALL=C git -C "$parent" rev-parse --is-inside-work-tree 2>&1); then
    # Outside any repository nothing is tracked. Any other failure (dubious
    # ownership, a broken .git) is git unable to answer.
    [[ $output == *"not a git repository"* ]] && return 1
    return 0
  fi
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
