#!/usr/bin/env bash

JOURNAL_DIR=/var/log/journal
COREDUMP_DIR=/var/lib/systemd/coredump
PACMAN_CACHE_DIR=/var/cache/pacman/pkg
if [[ ${OMS_TEST:-} == 1 ]]; then
  JOURNAL_DIR=${OMS_JOURNAL_DIR:-$JOURNAL_DIR}
  COREDUMP_DIR=${OMS_COREDUMP_DIR:-$COREDUMP_DIR}
  PACMAN_CACHE_DIR=${OMS_PACMAN_CACHE_DIR:-$PACMAN_CACHE_DIR}
fi

target pacman "System" safe 1 "Old package versions" "removed packages, plus versions past $OMS_PACMAN_KEEP (omarchy update prunes those too)" "pacman yay paru"
target pacman-downloads "System" safe 1 "Partial package downloads" "download-* folders pacman left behind" "pacman yay paru"
target journal "System" safe 1 "Archived journal logs" "older than $OMS_JOURNAL_KEEP"
target coredumps "System" safe 1 "Crash dumps" "systemd-coredump archive"
target flatpak-unused "System" safe 1 "Unused Flatpak runtimes" "runtimes no installed app needs" "flatpak"
target thumbnails "System" safe 0 "Thumbnail cache" "regenerated on demand"
paths thumbnails "$CACHE/thumbnails" "$HOME/.thumbnails"
target trash "System" review 0 "Trash" "files you deleted"
paths trash "$DATA/Trash/files" "$DATA/Trash/info" "$DATA/Trash/expunged"
PARTIAL_DAYS=7
target partial-downloads "System" safe 0 "Unfinished downloads" "browser .crdownload and .part files, untouched for $PARTIAL_DAYS+ days and not open"
target installers "System" review 0 "Old installers" "packages and disk images in Downloads, untouched for $OMS_STALE_DAYS+ days"

scan_pacman() {
  have paccache || return 1
  SCAN_BYTES=$(($(paccache_saved -dk"$OMS_PACMAN_KEEP") + $(paccache_saved -duk0) - $(paccache_saved -duk"$OMS_PACMAN_KEEP")))
  ((SCAN_BYTES >= 0)) || SCAN_BYTES=0
}

paccache_saved() {
  iec_to_bytes "$(paccache -c "$PACMAN_CACHE_DIR" "$1" 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')"
}

clean_pacman() {
  run sudo -n paccache -c "$PACMAN_CACHE_DIR" -rk"$OMS_PACMAN_KEEP" &&
    run sudo -n paccache -c "$PACMAN_CACHE_DIR" -ruk0
}

PACMAN_DOWNLOADS=()

scan_pacman-downloads() {
  [[ -d $PACMAN_CACHE_DIR ]] || return 1
  mapfile -t PACMAN_DOWNLOADS < <(find "$PACMAN_CACHE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'download-*' 2>/dev/null)
  ((${#PACMAN_DOWNLOADS[@]})) || return 1
  SCAN_BYTES=$(size_of "${PACMAN_DOWNLOADS[@]}")
  ((SCAN_BYTES > 0)) || SCAN_BYTES=4096
}

clean_pacman-downloads() {
  run sudo -n find "$PACMAN_CACHE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'download-*' -exec rm -rf -- {} +
}

journal_keep_days() {
  local value=$OMS_JOURNAL_KEEP number
  number=${value%%[!0-9]*}
  number=${number:-28}
  case $value in
    *week*) printf '%s' $((number * 7)) ;;
    *month*) printf '%s' $((number * 30)) ;;
    *) printf '%s' "$number" ;;
  esac
}

scan_journal() {
  [[ -d $JOURNAL_DIR ]] || return 1
  SCAN_BYTES=$(file_bytes "$JOURNAL_DIR" -type f -name '*@*.journal*' -mtime +"$(journal_keep_days)")
}

clean_journal() {
  run sudo -n journalctl --vacuum-time="$OMS_JOURNAL_KEEP"
}

scan_coredumps() {
  [[ -d $COREDUMP_DIR ]] || return 1
  SCAN_BYTES=$(file_bytes "$COREDUMP_DIR" -type f)
}

clean_coredumps() {
  run sudo -n find "$COREDUMP_DIR" -mindepth 1 -type f -delete
}

scan_flatpak-unused() {
  have flatpak || return 1
  [[ -n $(flatpak list --runtime --columns=application 2>/dev/null) ]] || return 1
  SCAN_BYTES=-1
  SCAN_NOTE="runtimes no installed app needs, size known after removal"
}

clean_flatpak-unused() {
  run flatpak uninstall --user --unused --noninteractive &&
    run sudo -n flatpak uninstall --system --unused --noninteractive
}

INSTALLERS=()

downloads_dir() {
  local dir
  dir=$(xdg-user-dir DOWNLOAD 2>/dev/null)
  [[ -n $dir && $dir != "$HOME" ]] || dir=$HOME/Downloads
  printf '%s' "$dir"
}

# Files directly in Downloads that match the find tests given.
downloads_find() {
  local dir
  dir=$(downloads_dir)
  [[ -d $dir ]] || return 0
  find "$dir" -maxdepth 1 -type f "$@" 2>/dev/null
}

# Whether one file still matches the find tests it was picked by.
still_found() {
  local file=$1
  shift
  [[ -n $(find "$file" -maxdepth 0 -type f "$@" 2>/dev/null) ]]
}

INSTALLER_TESTS=(\( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.*' -o -name '*.iso' -o -name '*.dmg'
  -o -name '*.exe' -o -name '*.msi' \) -mtime +"$OMS_STALE_DAYS" -ctime +"$OMS_STALE_DAYS")

scan_installers() {
  mapfile -t INSTALLERS < <(downloads_find "${INSTALLER_TESTS[@]}")
  ((${#INSTALLERS[@]})) || return 1
  SCAN_BYTES=$(size_of "${INSTALLERS[@]}")
  local names=("${INSTALLERS[@]##*/}")
  SCAN_NOTE="$(plural ${#INSTALLERS[@]} file): $(preview_list 2 "${names[@]}")"
}

clean_installers() {
  local file failed=0
  for file in "${INSTALLERS[@]}"; do
    if ! still_found "$file" "${INSTALLER_TESTS[@]}"; then
      oplog "SKIPPED $file, changed since the scan"
      continue
    fi
    remove_path "$file" || failed=1
  done
  return "$failed"
}

PARTIALS=()
PARTIAL_TESTS=(\( -name '*.crdownload' -o -name '*.part' \) -mtime +"$PARTIAL_DAYS")

scan_partial-downloads() {
  # Without fuser an open download cannot be told apart, so offer nothing.
  have fuser || return 1
  local file
  PARTIALS=()
  while IFS= read -r file; do
    fuser -s -- "$file" 2>/dev/null || PARTIALS+=("$file")
  done < <(downloads_find "${PARTIAL_TESTS[@]}")
  ((${#PARTIALS[@]})) || return 1
  SCAN_BYTES=$(size_of "${PARTIALS[@]}")
  ((SCAN_BYTES > 0)) || SCAN_BYTES=4096
  local names=("${PARTIALS[@]##*/}")
  SCAN_NOTE="$(plural ${#PARTIALS[@]} file): $(preview_list 2 "${names[@]}")"
}

clean_partial-downloads() {
  local file failed=0
  for file in "${PARTIALS[@]}"; do
    if ! still_found "$file" "${PARTIAL_TESTS[@]}" || fuser -s -- "$file" 2>/dev/null; then
      oplog "SKIPPED $file, opened or changed since the scan"
      continue
    fi
    remove_path "$file" || failed=1
  done
  return "$failed"
}
