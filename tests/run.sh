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

target_is() {
  jq -e --arg id "$1" ".targets[] | select(.id == \$id) | $2" <<<"$json"
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
    OMS_COREDUMP_DIR="$SANDBOX/coredump" OMS_PACMAN_CACHE_DIR="$SANDBOX/pkg" \
    OMS_TEST=1 OMS_TEST_CALLS="$CALLS" NO_COLOR=1 \
    "$OMS" "$@"
}

rejects() {
  ! oms "$@" </dev/null >/dev/null 2>&1
}

prints_version() {
  oms "$1" | grep -q '^omasweep '
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
if [[ " $* " == *" -d"* ]]; then
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
  exit "${FAKE_MISE_EXIT:-0}"
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
  stub go <<'EOF'
if [[ "$*" == "env GOMODCACHE" ]]; then
  echo "$HOME/go/pkg/mod"
else
  echo "go $*" >>"$OMS_TEST_CALLS"
fi
EOF
  stub flatpak <<'EOF'
case $1 in
  ps) printf "%s\n" ${FAKE_FLATPAK_RUNNING:-} ;;
  list) echo org.freedesktop.Platform ;;
  *) echo "flatpak $*" >>"$OMS_TEST_CALLS" ;;
esac
EOF
  stub pnpm <<'EOF'
echo "pnpm $*" >>"$OMS_TEST_CALLS"
EOF
  stub ps <<'EOF'
if [[ -n ${FAKE_REAL_PS:-} || " $* " == *" -p "* ]]; then
  exec /usr/bin/ps "$@"
fi
case "$*" in
  *comm=*) printf "%s\n" ${FAKE_RUNNING:-} ;;
  *args=*)
    for name in ${FAKE_RUNNING:-}; do echo "100 $name"; done
    [[ -n ${FAKE_ARGS:-} ]] && echo "101 $FAKE_ARGS"
    ;;
esac
exit 0
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
  mkdir -p "$SANDBOX/journal/locked"
  chmod 000 "$SANDBOX/journal/locked"
  blob "$SANDBOX/.cache/uv/keep/pinned.whl" 10
  blob "$SANDBOX/Work/tab$(printf '\t')proj/package.json" 10
  blob "$SANDBOX/Work/tab$(printf '\t')proj/node_modules/pkg/index.js" 10
  find "$SANDBOX/Work/tab$(printf '\t')proj" -exec touch -h -d '90 days ago' {} +
  blob "$SANDBOX/coredump/core.app.1000.zst" 100000
  blob "$SANDBOX/pkg/download-abc/partial.part" 1000

  blob "$SANDBOX/.cargo/registry/cache/index/serde.crate" 100000
  blob "$SANDBOX/.cargo/registry/src/index/serde/lib.rs" 100000
  blob "$SANDBOX/.gradle/caches/build-cache-1/entry" 100000
  blob "$SANDBOX/.gradle/caches/modules-2/files/dep.jar" 100000
  blob "$SANDBOX/go/pkg/mod/example.com/m/go.mod" 100000

  blob "$SANDBOX/.config/Obsidian/GPUCache/data_0" 100000
  blob "$SANDBOX/.config/Obsidian/Local Storage/leveldb/000003.log" 10
  blob "$SANDBOX/.config/Obsidian/Cookies" 10
  blob "$SANDBOX/.config/Busy App/Code Cache/js/index" 100000
  ln -s "$(hostname)-$$" "$SANDBOX/.config/Busy App/SingletonLock"
  blob "$SANDBOX/.config/chromium/Default/GPUCache/data_0" 100000
  blob "$SANDBOX/.config/chromium/Default/History" 10
  blob "$SANDBOX/.config/chromium/Default/Login Data" 10
  blob "$SANDBOX/.var/app/org.example.Idle/cache/c" 100000
  blob "$SANDBOX/.var/app/org.example.Idle/data/keep" 10
  blob "$SANDBOX/.var/app/org.example.Open/cache/c" 100000

  blob "$SANDBOX/.local/share/claude/versions/1.0.0" 100000
  blob "$SANDBOX/.local/share/claude/versions/1.1.0" 100000
  blob "$SANDBOX/.local/share/claude/versions/1.2.0" 100000
  touch -d '3 days ago' "$SANDBOX/.local/share/claude/versions/1.0.0"
  touch -d '2 days ago' "$SANDBOX/.local/share/claude/versions/1.1.0"
  mkdir -p "$SANDBOX/.local/bin"
  ln -s "$SANDBOX/.local/share/claude/versions/1.1.0" "$SANDBOX/.local/bin/claude"

  blob "$SANDBOX/Downloads/old-tool.deb" 100000
  blob "$SANDBOX/Downloads/new-tool.deb" 100000
  blob "$SANDBOX/Downloads/notes.pdf" 100000
  touch -d '90 days ago' "$SANDBOX/Downloads/old-tool.deb" "$SANDBOX/Downloads/notes.pdf"

  blob "$SANDBOX/Work/rusty/Cargo.toml" 10
  blob "$SANDBOX/Work/rusty/target/debug/app" 100000
  blob "$SANDBOX/Work/anchor/Cargo.toml" 10
  blob "$SANDBOX/Work/anchor/target/deploy/key.json" 10
  blob "$SANDBOX/Work/py/pyproject.toml" 10
  blob "$SANDBOX/Work/py/.venv/pyvenv.cfg" 10
  blob "$SANDBOX/Work/goapp/go.mod" 10
  blob "$SANDBOX/Work/goapp/vendor/mod/x.go" 10
  blob "$SANDBOX/Work/old/package.json" 10
  blob "$SANDBOX/Work/deep/package.json" 10
  blob "$SANDBOX/Work/deep/node_modules/pkg/index.js" 10
  blob "$SANDBOX/Work/deep/src/app/old.js" 10
  find "$SANDBOX/Work/deep" -exec touch -h -d '90 days ago' {} +
  blob "$SANDBOX/Work/deep/src/app/main.js" 10
  find "$SANDBOX"/Work/{rusty,anchor,py,goapp} -exec touch -h -d '90 days ago' {} +
  touch -d '90 days ago' "$SANDBOX/Work/old/package.json" "$SANDBOX/Work/old"

  blob "$OUTSIDE/victim/keep.txt" 10
  ln -s "$OUTSIDE/victim" "$SANDBOX/.cache/thumbnails/link-dir"
  ln -s "$OUTSIDE/victim/keep.txt" "$SANDBOX/.cache/thumbnails/link-file"
  blob "$OUTSIDE/bun/cache/pkg" 10
  mkdir -p "$SANDBOX/.bun/install"
  ln -s "$OUTSIDE/bun/cache" "$SANDBOX/.bun/install/cache"

  blob "$SANDBOX/.cache/thumbnails/normal/keep/thumb.png" 10
  blob "$SANDBOX/.cache/huggingface/hub/models--x/blob" 100000
  blob "$SANDBOX/Work/c#app/package.json" 10
  blob "$SANDBOX/Work/c#app/node_modules/pkg/index.js" 10
  find "$SANDBOX/Work/c#app" -exec touch -h -d '90 days ago' {} +

  cat >"$SANDBOX/.config/omasweep/whitelist" <<'EOF'
# comment
  # indented comment
~/.npm/_cacache/keep*
~/.cache/thumbnails/*/keep   # keep pinned thumbnails
~/.cache/uv/keep
~/Work/c#app/node_modules
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
long_labels=$(bash -c 'source "$1/lib/ui.sh"; source "$1/lib/core.sh"; source "$1/lib/engine.sh"
  for module in "$1"/lib/targets/*.sh; do source "$module"; done
  for id in "${TARGET_IDS[@]}"; do ((${#T_LABEL[$id]} > 26)) && echo "$id"; done' _ "$ROOT")
check "target labels fit the table" test -z "$long_labels"
check "manifest version matches oms" test "$(jq -r .version "$ROOT/manifest.json")" = "$("$OMS" version | cut -d' ' -f2)"
for fn in opened popoutSwitchClosing "function open" "function close" "function toggle" "function closeForPopoutSwitch"; do
  check "bar widget exposes ${fn#function }" grep -q "$fn" "$ROOT/BarWidget.qml"
done

printf '\nScan\n'
seed
json=$(oms scan --json)
check "scan --json is valid JSON" jq -e '.targets | type == "array"' <<<"$json"
check "npm size leaves out whitelisted paths" target_is npm '.bytes < 500000 and .bytes > 300000'
check "whitelisted target is hidden" jq -e '[.targets[] | select(.id == "trash")] | length == 0' <<<"$json"
check "stale project artifacts are found" target_is project-artifacts '.note | startswith("4 projects:")'
check "a tab in a project name keeps the JSON intact" target_is project-artifacts '.note | contains("tab proj")'
check "an unreadable folder does not hide the journal" jq -e '[.targets[] | select(.id == "journal")] | length == 1' <<<"$json"
check "symlinked cache directory is not measured" jq -e '[.targets[] | select(.id == "bun")] | length == 0' <<<"$json"
check "only the mise version no config needs is counted" target_is mise '.bytes < 300000'
check "scan leaves no temporary files behind" test -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'omasweep.*' -newer "$CALLS" 2>/dev/null)"
check "docker sizes come from docker system df" jq -e '[.targets[] | select(.id == "docker-build" or .id == "docker-images") | .bytes] == [2000000000, 1500000000]' <<<"$json"
check "unused docker images need review" target_is docker-images '.tier == "review"'
check "orphans are measured from pacman -Qi" target_is orphans '.bytes == 4194304'
check "Electron apps are discovered from ~/.config" target_is app-caches '.note | contains("Obsidian")'
check "an app holding its SingletonLock is skipped" target_is app-caches '.note | contains("skipping open: Busy App")'
check "an installer with an old mtime but a fresh ctime is not offered" jq -e '[.targets[] | select(.id == "installers")] | length == 0' <<<"$json"
check "AI CLI keeps the active and previous version" target_is ai-cli-versions '.note | startswith("1 version")'
check "a stray chromium process does not block the browser cache" jq -e '.targets[] | select(.id == "chromium") | .status == "ready"' <<<"$(FAKE_RUNNING=chromium oms scan --json)"
ln -s "$(hostname)-$$" "$SANDBOX/.config/chromium/SingletonLock"
check "a running process marks its target busy" jq -e '.targets[] | select(.id == "uv") | .status == "busy"' <<<"$(FAKE_RUNNING=uv oms scan --json)"
check "a matching command line marks its target busy" jq -e '.targets[] | select(.id == "gradle") | .status == "busy"' <<<"$(FAKE_ARGS="java org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10" oms scan --json)"
check "browser cache is skipped while its profile is open" jq -e '.targets[] | select(.id == "chromium") | .status == "busy"' <<<"$(oms scan --json)"

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
FAKE_FLATPAK_RUNNING=org.example.Open oms clean --yes >/dev/null 2>&1
check "pacman cache keeps two versions" called "paccache -c $SANDBOX/pkg -rk2"
check "uninstalled packages leave the cache" called "paccache -c $SANDBOX/pkg -ruk0"
check "journal is vacuumed through sudo" called "sudo -n journalctl --vacuum-time=4weeks"
check "crash dumps are removed" test ! -e "$SANDBOX/coredump/core.app.1000.zst"
check "mise prunes through its own command" called "mise prune -y"
check "docker build cache is pruned" called "docker builder prune -af"
check "uv cache with a whitelisted path is emptied around it" not_called "uv cache prune"
check "whitelisted uv path survives" test -f "$SANDBOX/.cache/uv/keep/pinned.whl"
check "unprotected uv cache is emptied" test ! -e "$SANDBOX/.cache/uv/wheels"
check "interrupted pacman downloads are removed" test ! -e "$SANDBOX/pkg/download-abc"
check "unused flatpak runtimes are removed" called "flatpak uninstall --user --unused --noninteractive"
check "cargo keeps extracted sources" test -f "$SANDBOX/.cargo/registry/src/index/serde/lib.rs"
check "cargo archives are removed" test ! -e "$SANDBOX/.cargo/registry/cache/index/serde.crate"
check "gradle keeps downloaded dependencies" test -f "$SANDBOX/.gradle/caches/modules-2/files/dep.jar"
check "gradle build cache is emptied" test ! -e "$SANDBOX/.gradle/caches/build-cache-1/entry"
check "go module cache needs review" test -f "$SANDBOX/go/pkg/mod/example.com/m/go.mod"
check "Electron GPU cache is removed" test ! -e "$SANDBOX/.config/Obsidian/GPUCache/data_0"
check "Electron local storage and cookies stay" test -f "$SANDBOX/.config/Obsidian/Cookies" -a -f "$SANDBOX/.config/Obsidian/Local Storage/leveldb/000003.log"
check "an app holding its lock keeps its cache" test -f "$SANDBOX/.config/Busy App/Code Cache/js/index"
check "browser profile cache is removed" test ! -e "$SANDBOX/.config/chromium/Default/GPUCache/data_0"
check "browser history and logins stay" test -f "$SANDBOX/.config/chromium/Default/History" -a -f "$SANDBOX/.config/chromium/Default/Login Data"
check "idle flatpak app cache is removed" test ! -e "$SANDBOX/.var/app/org.example.Idle/cache/c"
check "flatpak app data stays" test -f "$SANDBOX/.var/app/org.example.Idle/data/keep"
check "running flatpak app keeps its cache" test -f "$SANDBOX/.var/app/org.example.Open/cache/c"
check "oldest AI CLI version is removed" test ! -e "$SANDBOX/.local/share/claude/versions/1.0.0"
check "active AI CLI version stays" test -f "$SANDBOX/.local/share/claude/versions/1.1.0"
check "newest other AI CLI version stays" test -f "$SANDBOX/.local/share/claude/versions/1.2.0"
check "pnpm store is pruned" called "pnpm store prune"
check "review items are not swept by default" not_called "docker image prune"
check "orphans are not removed by default" not_called "pacman -Rns"
check "read-only npm cache is removed" test ! -e "$SANDBOX/.npm/_cacache/content"
check "whitelisted glob survives" test -f "$SANDBOX/.npm/_cacache/keep me/file"
check "whitelisted glob two levels down survives" test -f "$SANDBOX/.cache/thumbnails/normal/keep/thumb.png"
check "cache directory itself stays" test -d "$SANDBOX/.cache/thumbnails"
check "thumbnails are emptied" test ! -e "$SANDBOX/.cache/thumbnails/large"
check "symlink inside a cache is removed as a link" test ! -L "$SANDBOX/.cache/thumbnails/link-dir"
check "directory a symlink pointed to survives" test -f "$OUTSIDE/victim/keep.txt"
check "symlinked cache directory is left alone" test -f "$OUTSIDE/bun/cache/pkg"
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
check "whitelisted path containing # survives" test -f "$SANDBOX/Work/c#app/node_modules/pkg/index.js"
check "stale Rust target is removed" test ! -e "$SANDBOX/Work/rusty/target"
check "target with deploy keys stays" test -f "$SANDBOX/Work/anchor/target/deploy/key.json"
check "stale virtualenv is removed" test ! -e "$SANDBOX/Work/py/.venv"
check "Go vendor directory stays" test -f "$SANDBOX/Work/goapp/vendor/mod/x.go"
check "go module cache is cleaned by go" called "go clean -modcache"
check "installers and documents stay" test -f "$SANDBOX/Downloads/old-tool.deb" -a -f "$SANDBOX/Downloads/notes.pdf"
check "a project edited deep inside keeps its node_modules" test -f "$SANDBOX/Work/deep/node_modules/pkg/index.js"
check "whitelisted target stays even with --all" test -f "$SANDBOX/.local/share/Trash/files/a.txt"

printf '\nOwn command line\n'
seed
FAKE_REAL_PS=1 oms clean --yes --only huggingface >/dev/null 2>&1
check "oms does not mistake its own arguments for a running app" test ! -e "$SANDBOX/.cache/huggingface/hub/models--x"

printf '\nFailing tool\n'
seed
FAKE_MISE_EXIT=3 oms clean --yes --only mise >"$WORK/out" 2>&1
status=$?
check "a tool exiting with 3 is reported as failed" grep -q 'failed, see oms log' "$WORK/out"
check "a failed sweep exits non-zero" test "$status" -ne 0

printf '\nWithout sudo\n'
seed
FAKE_SUDO=deny oms clean --yes >/dev/null 2>&1
check "sudo targets are skipped" not_called "paccache -rk"
check "crash dumps survive" test -f "$SANDBOX/coredump/core.app.1000.zst"
check "user caches are still swept" test ! -e "$SANDBOX/.cache/thumbnails/large"

printf '\nGuards\n'
seed
OMS_STALE_DAYS=30d check "a malformed OMS_STALE_DAYS stops the run" rejects scan --json
OMS_STALE_DAYS=30d oms clean --yes --all >/dev/null 2>&1
check "nothing is removed after a malformed setting" test -d "$SANDBOX/Work/old/node_modules"
seed
oms clean --yes --only thumbnails --skip thumbnails >/dev/null 2>&1
check "--skip wins over --only" test -f "$SANDBOX/.cache/thumbnails/large/a.png"
blob "$OUTSIDE/cache/thumbnails/x/f" 10
env HOME="$SANDBOX" PATH="$STUBS:$PATH" XDG_CACHE_HOME="$OUTSIDE/cache" XDG_STATE_HOME="$SANDBOX/.local/state" \
  OMS_TEST_CALLS="$CALLS" "$OMS" clean --yes --only thumbnails >/dev/null 2>&1
check "caches outside HOME are refused" test -f "$OUTSIDE/cache/thumbnails/x/f"
check "caches outside HOME are not offered" jq -e '[.targets[] | select(.id == "thumbnails")] | length == 0' \
  <<<"$(env HOME="$SANDBOX" PATH="$STUBS:$PATH" XDG_CACHE_HOME="$OUTSIDE/cache" OMS_TEST=1 OMS_TEST_CALLS="$CALLS" "$OMS" scan --json)"
check "unknown target is rejected" rejects clean --yes --only nope
check "--only without IDs is rejected" rejects clean --yes --only
check "--only with an empty value is rejected" rejects clean --yes --only ''
check "an empty ID in a list is rejected" rejects clean --yes --only thumbnails,,npm
check "--skip= with an unknown ID is rejected" rejects clean --yes --skip=nope
check "sweeping without a terminal needs --yes" rejects clean
check "rejected runs touch nothing" test ! -s "$CALLS" -a -f "$SANDBOX/.cache/thumbnails/large/a.png"
check "--version prints the version" prints_version --version
check "-v prints the version" prints_version -v

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
