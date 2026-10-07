#!/usr/bin/env bash

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OMS=$ROOT/bin/oms
WORK=$(mktemp -d)
SANDBOX=$WORK/home
OUTSIDE=$WORK/outside
STUBS=$WORK/stubs
CALLS=$WORK/calls
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

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

called() {
  grep -qxF -- "$1" "$CALLS"
}

not_called() {
  ! grep -qF -- "$1" "$CALLS"
}

oms() {
  : >"$CALLS"
  env HOME="$SANDBOX" PATH="$STUBS:$PATH" \
    XDG_CACHE_HOME="$SANDBOX/.cache" XDG_DATA_HOME="$SANDBOX/.local/share" \
    XDG_CONFIG_HOME="$SANDBOX/.config" XDG_STATE_HOME="$SANDBOX/.local/state" \
    OMS_PROJECT_DIRS="$SANDBOX/Work" OMS_JOURNAL_DIR="$SANDBOX/journal" \
    OMS_COREDUMP_DIR="$SANDBOX/coredump" OMS_TEST_CALLS="$CALLS" NO_COLOR=1 \
    "$OMS" "$@"
}

stub() {
  {
    printf '#!/usr/bin/env bash\n'
    cat
  } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

make_stubs() {
  mkdir -p "$STUBS"
  stub sudo <<'EOF'
echo "sudo $*" >>"$OMS_TEST_CALLS"
[[ ${FAKE_SUDO:-allow} == deny ]] && exit 1
[[ $1 == -n ]] && shift
[[ $1 == -v || $1 == true ]] && exit 0
exec "$@"
EOF
  stub paccache <<'EOF'
if [[ $1 == -d* ]]; then
  echo "==> finished dry run: 3 candidates (disk space saved: 1.50 MiB)"
else
  echo "paccache $*" >>"$OMS_TEST_CALLS"
fi
EOF
  stub pacman <<'EOF'
case $1 in
  -Qdtq) printf "orphan-a\norphan-b\n" ;;
  -Qi) shift; for p; do printf "Name            : %s\nInstalled Size  : 2.00 MiB\n\n" "$p"; done ;;
  *) echo "pacman $*" >>"$OMS_TEST_CALLS" ;;
esac
EOF
  stub journalctl <<'EOF'
echo "journalctl $*" >>"$OMS_TEST_CALLS"
EOF
  stub mise <<'EOF'
if [[ "$*" == "prune --dry-run" ]]; then
  echo "mise node@20.0.0 is prunable: not required by any config"
  echo "mise node@20.0.0 [dryrun]    remove ~/.local/share/mise/installs/node/20.0.0"
else
  echo "mise $*" >>"$OMS_TEST_CALLS"
fi
EOF
  stub docker <<'EOF'
case $1 in
  info) exit 0 ;;
  system) printf "Images\t1.5GB (10%%)\nBuild Cache\t2GB\n" ;;
  *) echo "docker $*" >>"$OMS_TEST_CALLS" ;;
esac
EOF
  stub uv <<'EOF'
echo "uv $*" >>"$OMS_TEST_CALLS"
EOF
  stub pnpm <<'EOF'
echo "pnpm $*" >>"$OMS_TEST_CALLS"
EOF
  stub pgrep <<'EOF'
for name in ${FAKE_RUNNING:-}; do
  [[ ${!#} == "$name" ]] && exit 0
done
exit 1
EOF
}

blob() {
  mkdir -p "$(dirname "$1")"
  head -c "$2" /dev/urandom >"$1"
}

seed() {
  chmod -R u+w "$SANDBOX" "$OUTSIDE" 2>/dev/null
  rm -rf "$SANDBOX" "$OUTSIDE"
  mkdir -p "$SANDBOX/.config/omasweep" "$SANDBOX/.local/share/pnpm/store" "$OUTSIDE"

  blob "$SANDBOX/.npm/_cacache/content/blob" 400000
  chmod 444 "$SANDBOX/.npm/_cacache/content/blob"
  chmod 555 "$SANDBOX/.npm/_cacache/content"
  blob "$SANDBOX/.npm/_cacache/keep me/file" 100000
  blob "$SANDBOX/.cache/thumbnails/large/a.png" 100000
  blob "$SANDBOX/.cache/uv/wheels/a.whl" 100000
  blob "$SANDBOX/.cache/chromium/Default/Cache/data" 100000
  blob "$SANDBOX/.local/share/Trash/files/a.txt" 10
  blob "$SANDBOX/.local/share/mise/installs/node/20.0.0/bin/node" 200000
  blob "$SANDBOX/.local/share/mise/installs/node/22.0.0/bin/node" 200000
  blob "$SANDBOX/Work/old/node_modules/pkg/index.js" 100000
  touch -d '90 days ago' "$SANDBOX/Work/old/node_modules/pkg/index.js" "$SANDBOX/Work/old/node_modules/pkg" \
    "$SANDBOX/Work/old/node_modules" "$SANDBOX/Work/old"
  blob "$SANDBOX/Work/new/node_modules/pkg/index.js" 10
  blob "$SANDBOX/journal/abc/system@0001.journal" 100000
  touch -d '60 days ago' "$SANDBOX/journal/abc/system@0001.journal"
  blob "$SANDBOX/coredump/core.app.1000.zst" 100000

  blob "$OUTSIDE/victim/keep.txt" 10
  ln -s "$OUTSIDE/victim" "$SANDBOX/.cache/thumbnails/link-dir"
  ln -s "$OUTSIDE/victim/keep.txt" "$SANDBOX/.cache/thumbnails/link-file"
  blob "$OUTSIDE/bun/cache/pkg" 10
  mkdir -p "$SANDBOX/.bun/install"
  ln -s "$OUTSIDE/bun/cache" "$SANDBOX/.bun/install/cache"

  cat >"$SANDBOX/.config/omasweep/whitelist" <<'EOF'
# comment
~/.npm/_cacache/keep*
trash
EOF
}

make_stubs

printf '\nStatic checks\n'
for file in "$OMS" "$ROOT"/lib/*.sh "$ROOT"/lib/targets/*.sh "$ROOT"/tests/*.sh; do
  check "bash -n ${file#"$ROOT"/}" bash -n "$file"
done
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -x "$OMS" "$ROOT"/lib/*.sh "$ROOT"/lib/targets/*.sh "$ROOT"/tests/*.sh
fi
if command -v omarchy >/dev/null 2>&1; then
  check "omarchy plugin validate" omarchy plugin validate "$ROOT"
fi
QMLLINT=$(command -v qmllint || command -v /usr/lib/qt6/bin/qmllint || true)
if [[ -n $QMLLINT && -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell ]]; then
  mkdir -p "$WORK/qml"
  ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$WORK/qml/qs"
  lint=$("$QMLLINT" -I "$WORK/qml" "$ROOT/BarWidget.qml" 2>&1 | grep '^Warning' | grep -vE '\[(missing-property|signal-handler-parameters)\]$')
  check "qmllint finds nothing beyond the shell's untyped bar object" test -z "$lint"
fi
check "manifest version matches oms" test "$(jq -r .version "$ROOT/manifest.json")" = "$("$OMS" version | cut -d' ' -f2)"
for fn in opened popoutSwitchClosing "function open" "function close" "function toggle" "function closeForPopoutSwitch"; do
  check "bar widget exposes ${fn#function }" grep -q "$fn" "$ROOT/BarWidget.qml"
done

printf '\nScan\n'
seed
json=$(oms scan --json)
check "scan --json is valid JSON" jq -e '.targets | type == "array"' <<<"$json"
check "npm size leaves out whitelisted paths" jq -e '.targets[] | select(.id == "npm") | .bytes < 500000 and .bytes > 300000' <<<"$json"
check "whitelisted target is hidden" jq -e '[.targets[] | select(.id == "trash")] | length == 0' <<<"$json"
check "only the stale node_modules is found" jq -e '.targets[] | select(.id == "node-modules") | .note | startswith("1 project: old")' <<<"$json"
check "symlinked cache directory is not measured" jq -e '[.targets[] | select(.id == "bun")] | length == 0' <<<"$json"
check "only the mise version no config needs is counted" jq -e '.targets[] | select(.id == "mise") | .bytes < 300000' <<<"$json"
check "docker sizes come from docker system df" jq -e '[.targets[] | select(.id == "docker-build" or .id == "docker-images") | .bytes] == [2000000000, 1500000000]' <<<"$json"
check "unused docker images need review" jq -e '.targets[] | select(.id == "docker-images") | .tier == "review"' <<<"$json"
check "orphans are measured from pacman -Qi" jq -e '.targets[] | select(.id == "orphans") | .bytes == 4194304' <<<"$json"
FAKE_RUNNING=chromium json=$(FAKE_RUNNING=chromium oms scan --json)
check "browser cache is skipped while the browser runs" jq -e '.targets[] | select(.id == "chromium") | .status == "busy"' <<<"$json"

printf '\nDry run\n'
seed
oms clean --dry-run --yes --all >/dev/null 2>&1
check "dry run keeps npm cache" test -f "$SANDBOX/.npm/_cacache/content/blob"
check "dry run keeps stale node_modules" test -d "$SANDBOX/Work/old/node_modules"
check "dry run keeps crash dumps" test -f "$SANDBOX/coredump/core.app.1000.zst"
check "dry run runs no cleanup command" test ! -s "$CALLS"
check "dry run writes no log" test ! -e "$SANDBOX/.local/state/omasweep/operations.log"

printf '\nSweep safe items\n'
seed
FAKE_RUNNING=chromium oms clean --yes >/dev/null 2>&1
check "pacman cache keeps two versions" called "paccache -rk2"
check "uninstalled packages leave the cache" called "paccache -ruk0"
check "journal is vacuumed through sudo" called "sudo -n journalctl --vacuum-time=4weeks"
check "crash dumps are removed" test ! -e "$SANDBOX/coredump/core.app.1000.zst"
check "mise prunes through its own command" called "mise prune -y"
check "docker build cache is pruned" called "docker builder prune -af"
check "uv cleans through its own command" called "uv cache clean"
check "pnpm store is pruned" called "pnpm store prune"
check "review items are not swept by default" not_called "docker image prune"
check "orphans are not removed by default" not_called "pacman -Rns"
check "read-only npm cache is removed" test ! -e "$SANDBOX/.npm/_cacache/content"
check "whitelisted glob survives" test -f "$SANDBOX/.npm/_cacache/keep me/file"
check "cache directory itself stays" test -d "$SANDBOX/.cache/thumbnails"
check "thumbnails are emptied" test ! -e "$SANDBOX/.cache/thumbnails/large"
check "symlink inside a cache is removed as a link" test ! -L "$SANDBOX/.cache/thumbnails/link-dir"
check "directory a symlink pointed to survives" test -f "$OUTSIDE/victim/keep.txt"
check "symlinked cache directory is left alone" test -f "$OUTSIDE/bun/cache/pkg"
check "running browser's cache survives" test -f "$SANDBOX/.cache/chromium/Default/Cache/data"
check "stale node_modules is not swept by default" test -d "$SANDBOX/Work/old/node_modules"
check "trash is untouched" test -f "$SANDBOX/.local/share/Trash/files/a.txt"
check "operation log records removals" grep -q REMOVED "$SANDBOX/.local/state/omasweep/operations.log"

printf '\nSweep with --all\n'
seed
oms clean --yes --all >/dev/null 2>&1
check "unused docker images are pruned" called "docker image prune -af"
check "orphans are removed by name" called "pacman -Rns --noconfirm orphan-a orphan-b"
check "stale node_modules is removed" test ! -e "$SANDBOX/Work/old/node_modules"
check "recent node_modules stays" test -f "$SANDBOX/Work/new/node_modules/pkg/index.js"
check "whitelisted target stays even with --all" test -f "$SANDBOX/.local/share/Trash/files/a.txt"

printf '\nWithout sudo\n'
seed
FAKE_SUDO=deny oms clean --yes >/dev/null 2>&1
check "sudo targets are skipped" not_called "paccache -rk"
check "crash dumps survive" test -f "$SANDBOX/coredump/core.app.1000.zst"
check "user caches are still swept" test ! -e "$SANDBOX/.cache/thumbnails/large"

printf '\nGuards\n'
seed
oms clean --yes --only thumbnails --skip thumbnails >/dev/null 2>&1
check "--skip wins over --only" test -f "$SANDBOX/.cache/thumbnails/large/a.png"
blob "$OUTSIDE/cache/thumbnails/x/f" 10
env HOME="$SANDBOX" PATH="$STUBS:$PATH" XDG_CACHE_HOME="$OUTSIDE/cache" XDG_STATE_HOME="$SANDBOX/.local/state" \
  OMS_TEST_CALLS="$CALLS" "$OMS" clean --yes --only thumbnails >/dev/null 2>&1
check "caches outside HOME are refused" test -f "$OUTSIDE/cache/thumbnails/x/f"
check "unknown target is rejected" bash -c "! env HOME='$SANDBOX' '$OMS' clean --yes --only nope"
check "sweeping without a terminal needs --yes" bash -c "! env HOME='$SANDBOX' '$OMS' clean </dev/null"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
