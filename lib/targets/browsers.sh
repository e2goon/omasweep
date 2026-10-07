#!/usr/bin/env bash

chromium_browser() {
  local id=$1 label=$2 cache_dir=$3 config_dir=$4 process=$5
  target "$id" "Browsers" safe 0 "$label cache" "web cache only, logins and history stay" "name:$label $process $(lock_token "$config_dir/SingletonLock")"
  paths "$id" "$cache_dir"
}

firefox_browser() {
  local id=$1 label=$2 cache_dir=$3 profiles=$4 process=$5
  target "$id" "Browsers" safe 0 "$label cache" "web cache only, logins and history stay" "name:$label $(lock_token "$profiles/*/lock") $process"
  paths "$id" "$cache_dir"
}

chromium_browser chromium "Chromium" "$CACHE/chromium" "$CONFIG/chromium" ""
chromium_browser chrome "Chrome" "$CACHE/google-chrome" "$CONFIG/google-chrome" ""
chromium_browser brave "Brave" "$CACHE/BraveSoftware" "$CONFIG/BraveSoftware/Brave-Browser" ""
firefox_browser firefox "Firefox" "$CACHE/mozilla" "$HOME/.mozilla/firefox" "firefox"
