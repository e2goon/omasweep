#!/usr/bin/env bash

target chromium "Browsers" safe 0 "Chromium cache" "web cache only, logins stay" "chromium"
paths chromium "$CACHE/chromium"
target chrome "Browsers" safe 0 "Chrome cache" "web cache only, logins stay" "chrome"
paths chrome "$CACHE/google-chrome"
target brave "Browsers" safe 0 "Brave cache" "web cache only, logins stay" "brave"
paths brave "$CACHE/BraveSoftware"
target firefox "Browsers" safe 0 "Firefox cache" "web cache only, logins stay" "firefox"
paths firefox "$CACHE/mozilla"
