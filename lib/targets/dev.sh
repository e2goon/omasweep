#!/usr/bin/env bash

target mise "Developer tools" safe 0 "Old mise tool versions" "mise prune" "mise"
target mise-cache "Developer tools" safe 0 "mise download cache" "mise cache clear" "mise"
paths mise-cache "$CACHE/mise"
target ai-cli-versions "Developer tools" safe 0 "Old AI CLI versions" "keeps the active and one previous version" "claude cursor-agent"
target aur "Developer tools" safe 0 "AUR build cache" "yay, paru, and pikaur clones" "yay paru pikaur makepkg"
paths aur "$CACHE/yay" "$CACHE/paru" "$CACHE/pikaur"

target npm "Developer tools" safe 0 "npm cache" "downloaded again on install" "npm npx"
paths npm "$HOME/.npm/_cacache" "$HOME/.npm/_npx" "$HOME/.npm/_logs" "$HOME/.npm/_prebuilds"
target pnpm "Developer tools" safe 0 "pnpm metadata cache" "registry metadata" "pnpm"
paths pnpm "$CACHE/pnpm"
target pnpm-store "Developer tools" safe 0 "pnpm store" "packages no project uses" "pnpm"
target yarn "Developer tools" safe 0 "Yarn cache" "downloaded again on install" "yarn"
paths yarn "$CACHE/yarn" "$HOME/.yarn/berry/cache"
target bun "Developer tools" safe 0 "Bun cache" "downloaded again on install" "bun"
paths bun "$HOME/.bun/install/cache" "$CACHE/.bun"
target deno "Developer tools" safe 0 "Deno cache" "downloaded again on run" "deno"
paths deno "$CACHE/deno"
target corepack "Developer tools" safe 0 "Corepack cache" "package manager downloads" "corepack"
paths corepack "$CACHE/node/corepack"

target uv "Developer tools" safe 0 "uv cache" "unused entries only, up to this size" "uv"
paths uv "$CACHE/uv"
target pip "Developer tools" safe 0 "pip cache" "downloaded again on install" "pip pip3"
paths pip "$CACHE/pip"
target poetry "Developer tools" safe 0 "Poetry cache" "downloaded again on install" "poetry"
paths poetry "$CACHE/pypoetry/cache" "$CACHE/pypoetry/artifacts"

target go-build "Developer tools" safe 0 "Go build cache" "rebuilt on next build" "go"
paths go-build "$CACHE/go-build"
target go-mod "Developer tools" review 0 "Go module cache" "every module, downloaded again on build" "go"
target cargo "Developer tools" safe 0 "Cargo download cache" "crate archives, sources stay" "cargo rustc"
paths cargo "$HOME/.cargo/registry/cache"
target rustup "Developer tools" safe 0 "rustup downloads" "toolchains stay" "rustup"
paths rustup "$HOME/.rustup/downloads" "$HOME/.rustup/tmp"

target gradle "Developer tools" safe 0 "Gradle build cache" "build cache and daemon logs, dependencies stay" "match:GradleDaemon"
paths gradle "$HOME/.gradle/caches/build-cache-*" "$HOME/.gradle/daemon" "$HOME/.gradle/notifications" "$HOME/.gradle/workers"
target composer "Developer tools" safe 0 "Composer cache" "downloaded again on install" "composer"
paths composer "$CACHE/composer"
target ruby "Developer tools" safe 0 "RubyGems and Bundler cache" "downloaded gem archives" "gem bundle"
paths ruby "$HOME/.gem/ruby/*/cache" "$HOME/.bundle/cache" "$DATA/mise/installs/ruby/*/lib/ruby/gems/*/cache"
target dotnet "Developer tools" safe 0 "NuGet HTTP cache" "installed packages stay" "dotnet"
paths dotnet "$DATA/NuGet/http-cache" "$DATA/NuGet/v3-cache" "$HOME/.local/share/NuGet/plugins-cache"
target beam "Developer tools" safe 0 "Hex and rebar3 cache" "Elixir and Erlang downloads" "beam.smp"
paths beam "$HOME/.hex/packages" "$CACHE/rebar3"
target jvm-tools "Developer tools" safe 0 "Coursier cache" "Scala and Clojure downloads" "match:coursier"
paths jvm-tools "$CACHE/coursier"
target zig "Developer tools" safe 0 "Zig global cache" "rebuilt on next build" "zig"
paths zig "$CACHE/zig"
target ccache "Developer tools" safe 0 "ccache" "compiler cache" "ccache"
paths ccache "$CACHE/ccache"
target opam "Developer tools" safe 0 "opam download cache" "OCaml package archives" "opam"
paths opam "$HOME/.opam/download-cache"
target android "Developer tools" safe 0 "Android build cache" "SDK and emulators stay" "match:gradle"
paths android "$HOME/.android/cache" "$HOME/.android/build-cache"
target tool-caches "Developer tools" safe 0 "Small tool caches" "node-gyp, Electron, TypeScript, Vite, ESLint, Prettier, Ruff, mypy, pre-commit"
paths tool-caches "$CACHE/node-gyp" "$HOME/.node-gyp" "$CACHE/electron" "$CACHE/electron-builder" \
  "$CACHE/typescript" "$CACHE/vite" "$CACHE/webpack" "$CACHE/eslint" "$CACHE/prettier" \
  "$CACHE/ruff" "$CACHE/mypy" "$CACHE/pre-commit"

target test-browsers "Developer tools" review 0 "Test browsers" "Playwright, Puppeteer, Cypress, downloaded again on next run" "match:playwright match:puppeteer Cypress"
paths test-browsers "$CACHE/ms-playwright" "$CACHE/puppeteer" "$CACHE/Cypress"
target jetbrains "Developer tools" review 0 "JetBrains IDE caches" "indexes rebuild on next open" "match:com.intellij"
paths jetbrains "$CACHE/JetBrains"

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

clean_mise-cache() {
  if command -v mise >/dev/null 2>&1; then
    run mise cache clear
  else
    clean_paths mise-cache
  fi
}

OLD_VERSIONS=()

old_versions() {
  local dir=$1 link=$2 active top entry previous=""
  [[ -d $dir && -L $link ]] || return 0
  active=$(readlink -f "$link")
  [[ -e $active && $active == "$dir"/* ]] || return 0
  top=${active#"$dir"/}
  top=$dir/${top%%/*}
  while IFS= read -r entry; do
    [[ $entry == "$top" ]] && continue
    if [[ -z $previous ]]; then
      previous=$entry
      continue
    fi
    OLD_VERSIONS+=("$entry")
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
}

scan_ai-cli-versions() {
  OLD_VERSIONS=()
  old_versions "$DATA/claude/versions" "$HOME/.local/bin/claude"
  old_versions "$DATA/cursor-agent/versions" "$HOME/.local/bin/cursor-agent"
  ((${#OLD_VERSIONS[@]})) || return 1
  SCAN_BYTES=$(size_of "${OLD_VERSIONS[@]}")
  SCAN_NOTE="$(plural ${#OLD_VERSIONS[@]} version), keeps the active and one previous"
}

clean_ai-cli-versions() {
  local entry failed=0
  for entry in "${OLD_VERSIONS[@]}"; do
    remove_path "$entry" || failed=1
  done
  return "$failed"
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
    run uv cache prune
  else
    clean_paths uv
  fi
}

go_mod_dir() {
  local dir=""
  command -v go >/dev/null 2>&1 && dir=$(go env GOMODCACHE 2>/dev/null)
  printf '%s' "${dir:-$HOME/go/pkg/mod}"
}

scan_go-mod() {
  local dir
  dir=$(go_mod_dir)
  [[ -d $dir && ! -L $dir ]] && path_safe "$dir" && ! path_covered "$dir" || return 1
  SCAN_BYTES=$(size_of "$dir")
}

clean_go-mod() {
  if command -v go >/dev/null 2>&1; then
    run go clean -modcache
  else
    remove_path "$(go_mod_dir)"
  fi
}
