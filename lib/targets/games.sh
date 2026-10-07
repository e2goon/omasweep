#!/usr/bin/env bash

STEAM_DIR=$DATA/Steam

target steam-cache "Games" safe 0 "Steam web cache and logs" "store pages and logs, games stay" "steam steamwebhelper"
paths steam-cache "$STEAM_DIR/appcache/httpcache" "$STEAM_DIR/config/htmlcache" "$STEAM_DIR/logs"
target steam-shaders "Games" review 0 "Steam shader cache" "rebuilt on next launch with some stutter" "steam"
paths steam-shaders "$STEAM_DIR/steamapps/shadercache"
target wine-caches "Games" review 0 "Wine and launcher caches" "winetricks downloads, Lutris and Heroic caches" "wine wineserver lutris heroic"
paths wine-caches "$CACHE/winetricks" "$HOME/.winetrickscache" "$CACHE/wine" "$CACHE/lutris" "$CONFIG/heroic/images-cache"
