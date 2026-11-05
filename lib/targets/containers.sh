#!/usr/bin/env bash

target docker-build "Containers" safe 0 "Docker build cache" "docker builder prune"
target docker-images "Containers" review 0 "Unused Docker images" "every image no container uses, pulled again when needed"
target docker-buildx "Containers" safe 0 "Docker buildx local cache" "cache exported with --cache-to type=local" "docker-buildx"
paths docker-buildx "$HOME/.docker/buildx/cache"
target podman-images "Containers" review 0 "Unused Podman images" "every image no container uses, pulled again when needed"

declare -A ENGINE_DF ENGINE_JOB ENGINE_OUT ENGINE_MODE

DOCKER_ROOT=/var/lib/docker
[[ ${OMS_TEST:-} == 1 ]] && DOCKER_ROOT=${OMS_DOCKER_ROOT:-$DOCKER_ROOT}

# Omarchy 4.5 leaves the user out of the docker group, so the plain CLI cannot
# reach the daemon. The first line says how it was reached: as the user,
# through sudo that needs no password right now, or not at all.
engine_df() {
  local engine=$1 cmd=("$1")
  if ! timeout 5 "$engine" info >/dev/null 2>&1; then
    if [[ $engine == docker ]] && sudo -n true 2>/dev/null && timeout 5 sudo -n docker info >/dev/null 2>&1; then
      cmd=(sudo -n docker)
      printf 'mode\tsudo\n'
    else
      [[ $engine == docker && -d $DOCKER_ROOT ]] && printf 'mode\tdenied\n'
      return 0
    fi
  else
    printf 'mode\tuser\n'
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
    ENGINE_MODE[$engine]=$(awk -F'\t' '$1 == "mode" { print $2; exit }' <<<"${ENGINE_DF[$engine]}")
  fi
  [[ -n ${ENGINE_MODE[$engine]} ]]
}

before_scan prefetch_engines

engine_reclaimable() {
  local engine=$1 type=$2 id=$3 value
  engine_ready "$engine" || return 1
  case ${ENGINE_MODE[$engine]} in
    sudo) T_SUDO["$id"]=1 ;;
    denied)
      # Unmeasurable without a password: offer it, but never preselect a sudo
      # prompt nobody asked for.
      T_SUDO["$id"]=1
      T_TIER["$id"]=review
      SCAN_BYTES=-1
      SCAN_NOTE="Docker runs without the docker group, size known after pruning"
      return 0
      ;;
  esac
  value=$(awk -F'\t' -v t="$type" '$1 == t { print $2 }' <<<"${ENGINE_DF[$engine]}")
  [[ -n $value ]] || return 1
  SCAN_BYTES=$(si_to_bytes "$value")
}

scan_docker-build() {
  engine_reclaimable docker "Build Cache" docker-build
}

docker_cli() {
  if [[ ${ENGINE_MODE[docker]:-user} == user ]]; then
    run docker "$@"
  else
    run sudo -n docker "$@"
  fi
}

clean_docker-build() {
  docker_cli builder prune -af
}

scan_docker-images() {
  engine_reclaimable docker "Images" docker-images
}

clean_docker-images() {
  docker_cli image prune -af
}

scan_podman-images() {
  engine_reclaimable podman "Images" podman-images
}

clean_podman-images() {
  run podman image prune -af
}
