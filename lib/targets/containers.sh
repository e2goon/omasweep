#!/usr/bin/env bash

target docker-build "Containers" safe 0 "Docker build cache" "docker builder prune"
target docker-images "Containers" review 0 "Unused Docker images" "every image no container uses, pulled again when needed"
target podman-images "Containers" review 0 "Unused Podman images" "every image no container uses, pulled again when needed"

declare -A ENGINE_DF ENGINE_JOB ENGINE_OUT ENGINE_MODE

DOCKER_SOCKET=/run/docker.sock
DOCKER_ROOT=/var/lib/docker
if [[ ${OMS_TEST:-} == 1 ]]; then
  DOCKER_SOCKET=${OMS_DOCKER_SOCKET:-$DOCKER_SOCKET}
  DOCKER_ROOT=${OMS_DOCKER_ROOT:-$DOCKER_ROOT}
fi

# Omarchy 4.5 leaves the user out of the docker group, so the plain CLI cannot
# reach the daemon. The first line says how it was reached: as the user,
# through sudo that needs no password right now, or not at all. "Not at all"
# is only reported for a socket the user cannot write in front of a daemon
# that has stored data; Omarchy enables the socket even where Docker never ran.
engine_df() {
  local engine=$1 cmd=("$1")
  if timeout 5 "$engine" info >/dev/null 2>&1; then
    printf 'mode\tuser\n'
  elif [[ $engine == docker ]] && timeout 5 sudo -n docker info >/dev/null 2>&1; then
    cmd=(sudo -n docker)
    printf 'mode\tsudo\n'
  else
    [[ $engine == docker && -S $DOCKER_SOCKET && ! -w $DOCKER_SOCKET && -d $DOCKER_ROOT ]] && printf 'mode\tdenied\n'
    return 0
  fi
  timeout 20 "${cmd[@]}" system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null
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
    local line=${ENGINE_DF[$engine]%%$'\n'*}
    [[ $line == mode$'\t'* ]] && ENGINE_MODE[$engine]=${line#*$'\t'}
  fi
  [[ -n ${ENGINE_MODE[$engine]:-} ]]
}

before_scan prefetch_engines

engine_reclaimable() {
  local engine=$1 type=$2 value
  engine_ready "$engine" || return 1
  [[ ${ENGINE_MODE[$engine]} == user ]] || SCAN_SUDO=1
  if [[ ${ENGINE_MODE[$engine]} == denied ]]; then
    # Unmeasurable without a password: offer it, but never preselect a sudo
    # prompt nobody asked for.
    SCAN_TIER=review
    SCAN_BYTES=-1
    SCAN_NOTE="Docker runs without the docker group, size known after pruning"
    return 0
  fi
  value=$(awk -F'\t' -v t="$type" '$1 == t { print $2 }' <<<"${ENGINE_DF[$engine]}")
  [[ -n $value ]] || return 1
  SCAN_BYTES=$(si_to_bytes "$value")
}

scan_docker-build() {
  engine_reclaimable docker "Build Cache"
}

engine_run() {
  local engine=$1 cmd=()
  shift
  [[ ${ENGINE_MODE[$engine]:-} == user ]] || cmd=(sudo -n)
  run "${cmd[@]}" "$engine" "$@"
}

clean_docker-build() {
  engine_run docker builder prune -af
}

scan_docker-images() {
  engine_reclaimable docker "Images"
}

clean_docker-images() {
  engine_run docker image prune -af
}

scan_podman-images() {
  engine_reclaimable podman "Images"
}

clean_podman-images() {
  engine_run podman image prune -af
}
