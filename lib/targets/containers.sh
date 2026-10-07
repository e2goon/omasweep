#!/usr/bin/env bash

target docker-build "Containers" safe 0 "Docker build cache" "docker builder prune"
target docker-images "Containers" review 0 "Unused Docker images" "every image no container uses, pulled again when needed"

declare -A ENGINE_DF

engine_ready() {
  local engine=$1
  command -v "$engine" >/dev/null 2>&1 || return 1
  if [[ -z ${ENGINE_DF[$engine]+set} ]]; then
    ENGINE_DF[$engine]=""
    timeout 5 "$engine" info >/dev/null 2>&1 || return 1
    ENGINE_DF[$engine]=$(timeout 20 "$engine" system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null)
  fi
  [[ -n ${ENGINE_DF[$engine]} ]]
}

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
