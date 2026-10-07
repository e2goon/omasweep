#!/usr/bin/env bash

CHROMIUM_CACHE_DIRS=("GrShaderCache" "ShaderCache" "GraphiteDawnCache" "component_crx_cache" "Crash Reports" "*/Code Cache" "*/GPUCache" "*/DawnCache" "*/DawnGraphiteCache" "*/DawnWebGPUCache")

chromium_browser() {
  local id=$1 label=$2 cache_dir=$3 config_dir=$4 process=$5 name
  target "$id" "Browsers" safe 0 "$label cache" "web cache only, logins and history stay" "name:$label $process $(lock_token "$config_dir/SingletonLock")"
  paths "$id" "$cache_dir"
  for name in "${CHROMIUM_CACHE_DIRS[@]}"; do
    paths "$id" "$config_dir/$name"
  done
}

firefox_browser() {
  local id=$1 label=$2 cache_dir=$3 profiles=$4 process=$5
  target "$id" "Browsers" safe 0 "$label cache" "web cache only, logins and history stay" "name:$label $(lock_token "$profiles/*/lock") $process"
  paths "$id" "$cache_dir"
}

chromium_browser chromium "Chromium" "$CACHE/chromium" "$CONFIG/chromium" ""
chromium_browser chrome "Chrome" "$CACHE/google-chrome" "$CONFIG/google-chrome" ""
chromium_browser edge "Edge" "$CACHE/microsoft-edge" "$CONFIG/microsoft-edge" ""
chromium_browser brave "Brave" "$CACHE/BraveSoftware" "$CONFIG/BraveSoftware/Brave-Browser" ""
chromium_browser vivaldi "Vivaldi" "$CACHE/vivaldi" "$CONFIG/vivaldi" ""
chromium_browser opera "Opera" "$CACHE/opera" "$CONFIG/opera" "opera"
firefox_browser firefox "Firefox" "$CACHE/mozilla" "$HOME/.mozilla/firefox" "firefox"
firefox_browser zen "Zen" "$CACHE/zen" "$HOME/.zen" "zen zen-bin"
firefox_browser librewolf "LibreWolf" "$CACHE/librewolf" "$HOME/.librewolf" "librewolf"
