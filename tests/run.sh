#!/usr/bin/env bash

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OMS=$ROOT/bin/oms
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

passed=0
failed=0

ok() {
  printf '  \e[32m✓\e[0m %s\n' "$1"
  passed=$((passed + 1))
}

fail() {
  printf '  \e[31m✗\e[0m %s\n' "$1"
  failed=$((failed + 1))
}

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}

oms() {
  env HOME="$SANDBOX" \
    XDG_CACHE_HOME="$SANDBOX/.cache" XDG_DATA_HOME="$SANDBOX/.local/share" \
    XDG_CONFIG_HOME="$SANDBOX/.config" XDG_STATE_HOME="$SANDBOX/.local/state" \
    OMS_PROJECT_DIRS="$SANDBOX/Work" NO_COLOR=1 "$OMS" "$@"
}

seed() {
  rm -rf "${SANDBOX:?}"/{.npm,.cache,.local,.config,Work}
  mkdir -p "$SANDBOX/.npm/_cacache/content" "$SANDBOX/.npm/_cacache/keep me" \
    "$SANDBOX/.cache/thumbnails/large" "$SANDBOX/.local/share/Trash/files" \
    "$SANDBOX/.config/omasweep" "$SANDBOX/Work/old/node_modules/pkg" "$SANDBOX/Work/new/node_modules/pkg"
  head -c 400000 /dev/urandom >"$SANDBOX/.npm/_cacache/content/blob"
  chmod 444 "$SANDBOX/.npm/_cacache/content/blob"
  chmod 555 "$SANDBOX/.npm/_cacache/content"
  head -c 100000 /dev/urandom >"$SANDBOX/.npm/_cacache/keep me/file"
  head -c 100000 /dev/urandom >"$SANDBOX/.cache/thumbnails/large/a.png"
  echo trash >"$SANDBOX/.local/share/Trash/files/a.txt"
  head -c 100000 /dev/urandom >"$SANDBOX/Work/old/node_modules/pkg/index.js"
  touch -d '90 days ago' "$SANDBOX/Work/old/node_modules/pkg/index.js" "$SANDBOX/Work/old/node_modules/pkg" \
    "$SANDBOX/Work/old/node_modules" "$SANDBOX/Work/old"
  echo new >"$SANDBOX/Work/new/node_modules/pkg/index.js"
  cat >"$SANDBOX/.config/omasweep/whitelist" <<'EOF'
# comment
~/.npm/_cacache/keep*
trash
EOF
}

printf '\nStatic checks\n'
for file in "$OMS" "$ROOT"/lib/*.sh "$ROOT"/tests/*.sh; do
  check "bash -n ${file#"$ROOT"/}" bash -n "$file"
done
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -x "$OMS" "$ROOT"/lib/*.sh
fi
if command -v omarchy >/dev/null 2>&1; then
  check "omarchy plugin validate" omarchy plugin validate "$ROOT"
fi
check "manifest version matches oms" test "$(jq -r .version "$ROOT/manifest.json")" = "$("$OMS" version | cut -d' ' -f2)"

printf '\nScan\n'
seed
json=$(oms scan --json)
check "scan --json is valid JSON" jq -e '.targets | type == "array"' <<<"$json"
check "npm size leaves out whitelisted paths" jq -e '.targets[] | select(.id == "npm") | .bytes < 500000 and .bytes > 300000' <<<"$json"
check "whitelisted target is hidden" jq -e '[.targets[] | select(.id == "trash")] | length == 0' <<<"$json"
check "only the stale node_modules is found" jq -e '.targets[] | select(.id == "node-modules") | .note | startswith("1 project: old")' <<<"$json"

printf '\nDry run\n'
oms clean --dry-run --yes --only npm,thumbnails,node-modules >/dev/null 2>&1
check "dry run keeps npm cache" test -f "$SANDBOX/.npm/_cacache/content/blob"
check "dry run keeps stale node_modules" test -d "$SANDBOX/Work/old/node_modules"
check "dry run writes no log" test ! -e "$SANDBOX/.local/state/omasweep/operations.log"

printf '\nSweep\n'
oms clean --yes --only npm,thumbnails,node-modules >/dev/null 2>&1
check "read-only npm cache is removed" test ! -e "$SANDBOX/.npm/_cacache/content"
check "whitelisted glob survives" test -f "$SANDBOX/.npm/_cacache/keep me/file"
check "cache directory itself stays" test -d "$SANDBOX/.cache/thumbnails"
check "thumbnails are emptied" test ! -e "$SANDBOX/.cache/thumbnails/large"
check "stale node_modules is removed" test ! -e "$SANDBOX/Work/old/node_modules"
check "recent node_modules stays" test -f "$SANDBOX/Work/new/node_modules/pkg/index.js"
check "trash is untouched" test -f "$SANDBOX/.local/share/Trash/files/a.txt"
check "operation log records removals" grep -q REMOVED "$SANDBOX/.local/state/omasweep/operations.log"

printf '\nGuards\n'
check "unknown target is rejected" bash -c "! env HOME='$SANDBOX' '$OMS' clean --yes --only nope"
check "sweeping without a terminal needs --yes" bash -c "! env HOME='$SANDBOX' '$OMS' clean </dev/null"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
