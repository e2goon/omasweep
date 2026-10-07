#!/usr/bin/env bash

target mise "Developer tools" safe 0 "Old mise tool versions" "mise prune" "mise"
target aur "Developer tools" safe 0 "AUR build cache" "yay and paru clones" "yay paru makepkg"
paths aur "$CACHE/yay" "$CACHE/paru"
target npm "Developer tools" safe 0 "npm cache" "downloaded again on install" "npm npx"
paths npm "$HOME/.npm/_cacache" "$HOME/.npm/_npx" "$HOME/.npm/_logs"
target pnpm "Developer tools" safe 0 "pnpm metadata cache" "registry metadata" "pnpm"
paths pnpm "$CACHE/pnpm"
target pnpm-store "Developer tools" safe 0 "pnpm store" "packages no project uses" "pnpm"
target uv "Developer tools" safe 0 "uv cache" "downloaded again on install" "uv"
paths uv "$CACHE/uv"
target pip "Developer tools" safe 0 "pip cache" "downloaded again on install" "pip pip3"
paths pip "$CACHE/pip"
target bun "Developer tools" safe 0 "Bun cache" "downloaded again on install" "bun"
paths bun "$HOME/.bun/install/cache" "$CACHE/.bun"
target go "Developer tools" safe 0 "Go build cache" "rebuilt on next build" "go"
paths go "$CACHE/go-build"
target cargo "Developer tools" safe 0 "Cargo registry cache" "downloaded again on build" "cargo"
paths cargo "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src"
target build-misc "Developer tools" safe 0 "Other build caches" "node-gyp, TypeScript, Yarn, Deno, mise downloads" "yarn deno"
paths build-misc "$CACHE/node-gyp" "$CACHE/typescript" "$CACHE/yarn" "$CACHE/deno" "$CACHE/mise"

scan_mise() {
  command -v mise >/dev/null 2>&1 || return 1
  local output count list=() path
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

scan_pnpm-store() {
  command -v pnpm >/dev/null 2>&1 || return 1
  [[ -d $DATA/pnpm/store ]] || return 1
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
