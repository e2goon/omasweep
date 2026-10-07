#!/usr/bin/env bash

target docker-build "Containers" safe 0 "Docker build cache" "docker builder prune"
target docker-images "Containers" review 0 "Unused Docker images" "every image no container uses, pulled again when needed"
target podman-images "Containers" review 0 "Unused Podman images" "every image no container uses, pulled again when needed"

declare -A ENGINE_DF ENGINE_JOB ENGINE_OUT

engine_df() {
  timeout 5 "$1" info >/dev/null 2>&1 || return 0
  timeout 20 "$1" system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null
}

prefetch_engines() {
  local engine file
  for engine in docker podman; do
    have "$engine" || continue
    file=$(mktemp -t omasweep.XXXXXX) || continue
    TEMP_FILES+=("$file")
    ENGINE_OUT[$engine]=$file
    engine_df "$engine" >"$file" &
    ENGINE_JOB[$engine]=$!
  done
}

engine_ready() {
  local engine=$1
  have "$engine" || return 1
  if [[ -z ${ENGINE_DF[$engine]+set} ]]; then
    if [[ -n ${ENGINE_JOB[$engine]:-} ]]; then
      wait "${ENGINE_JOB[$engine]}" 2>/dev/null
      ENGINE_DF[$engine]=$(<"${ENGINE_OUT[$engine]}")
    else
      ENGINE_DF[$engine]=$(engine_df "$engine")
    fi
  fi
  [[ -n ${ENGINE_DF[$engine]} ]]
}

before_scan prefetch_engines

engine_reclaimable() {
  local engine=$1 type=$2 value
  engine_ready "$engine" || return 1
  value=$(awk -F'\t' -v t="$type" '$1 == t { print $2 }' <<<"${ENGINE_DF[$engine]}")
  [[ -n $value ]] || return 1
  SCAN_BYTES=$(si_to_bytes "$value")
}

scan_docker-build() {
  engine_reclaimable docker "Build Cache"
}

clean_docker-build() {
  run docker builder prune -af
}

scan_docker-images() {
  engine_reclaimable docker "Images"
}

clean_docker-images() {
  run docker image prune -af
}

scan_podman-images() {
  engine_reclaimable podman "Images"
}

clean_podman-images() {
  run podman image prune -af
}
