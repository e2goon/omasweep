#!/usr/bin/env bash

ELECTRON_CACHE_DIRS=("Cache" "Code Cache" "GPUCache" "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache"
  "GrShaderCache" "ShaderCache" "CachedData" "CachedExtensionVSIXs" "CachedProfilesData" "Crashpad")
BROWSER_CONFIG_DIRS=" chromium google-chrome google-chrome-beta google-chrome-unstable microsoft-edge BraveSoftware vivaldi opera "

target app-caches "Apps" safe 0 "Desktop app caches" "Electron and Chromium-based apps"
target flatpak-caches "Apps" safe 0 "Flatpak app caches" "cache folders under .var/app, app data stays"
target spotify "Apps" review 0 "Spotify cache" "includes songs saved for offline listening" "spotify"
paths spotify "$CACHE/spotify"
target kdenlive "Apps" review 0 "Kdenlive render cache" "proxy clips and previews, rebuilt when a project opens" "kdenlive"
paths kdenlive "$CACHE/kdenlive"
target gpu-shaders "Apps" review 0 "GPU shader caches" "rebuilt on demand, games may stutter at first"
paths gpu-shaders "$CACHE/mesa_shader_cache" "$CACHE/mesa_shader_cache_db" "$CACHE/radv_builtin_shaders" \
  "$CACHE/nvidia/GLCache" "$HOME/.nv/GLCache" "$HOME/.nv/ComputeCache"

APP_NAMES=()

discover_app_caches() {
  local dir app name process sub
  for dir in "$CONFIG"/*/; do
    dir=${dir%/}
    app=${dir##*/}
    [[ $BROWSER_CONFIG_DIRS == *" $app "* ]] && continue
    [[ -d $dir/GPUCache || -d "$dir/Code Cache" ]] || continue
    [[ -L $dir ]] && continue
    name=${app// /%20}
    process=${app,,}
    process=${process// /-}
    for sub in "${ELECTRON_CACHE_DIRS[@]}"; do
      app_path app-caches "$dir/$sub" "$app" "name:$name $process $(lock_token "$dir/SingletonLock")"
    done
    APP_NAMES+=("$app")
  done
}

scan_app-caches() {
  scan_paths app-caches || return 1
  SCAN_NOTE=$(preview_list 3 "${APP_NAMES[@]}")
}

discover_flatpak_caches() {
  local dir app
  for dir in "$HOME"/.var/app/*/cache; do
    [[ -d $dir ]] || continue
    app=${dir%/cache}
    app=${app##*/}
    app_path flatpak-caches "$dir" "$app" "name:$app flatpak:$app"
  done
}

before_scan discover_app_caches discover_flatpak_caches
