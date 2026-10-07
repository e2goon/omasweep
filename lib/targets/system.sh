#!/usr/bin/env bash

JOURNAL_DIR=${OMS_JOURNAL_DIR:-/var/log/journal}
COREDUMP_DIR=${OMS_COREDUMP_DIR:-/var/lib/systemd/coredump}
PACMAN_CACHE_DIR=${OMS_PACMAN_CACHE_DIR:-/var/cache/pacman/pkg}

target pacman "System" safe 1 "Old package versions" "keeps the newest $OMS_PACMAN_KEEP like omarchy update" "pacman yay paru"
target pacman-downloads "System" safe 1 "Partial package downloads" "download-* folders pacman left behind" "pacman yay paru"
target journal "System" safe 1 "Archived journal logs" "older than $OMS_JOURNAL_KEEP"
target coredumps "System" safe 1 "Crash dumps" "systemd-coredump archive"
target flatpak-unused "System" safe 1 "Unused Flatpak runtimes" "runtimes no installed app needs" "flatpak"
target thumbnails "System" safe 0 "Thumbnail cache" "regenerated on demand"
paths thumbnails "$CACHE/thumbnails" "$HOME/.thumbnails"
target orphans "System" review 1 "Orphaned packages" "installed as dependencies and no longer needed" "pacman yay paru"
target trash "System" review 0 "Trash" "files you deleted"
paths trash "$DATA/Trash/files" "$DATA/Trash/info" "$DATA/Trash/expunged"
target installers "System" review 0 "Old installers" "packages and disk images in Downloads, untouched for $OMS_STALE_DAYS+ days"

scan_pacman() {
  command -v paccache >/dev/null 2>&1 || return 1
  local old uninstalled
  old=$(paccache -c "$PACMAN_CACHE_DIR" -dk"$OMS_PACMAN_KEEP" 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  uninstalled=$(paccache -c "$PACMAN_CACHE_DIR" -duk0 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  SCAN_BYTES=$(($(iec_to_bytes "$old") + $(iec_to_bytes "$uninstalled")))
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
  SCAN_BYTES=$(find "$JOURNAL_DIR" -type f -name '*@*.journal*' -mtime +"$(journal_keep_days)" -printf '%s\n' 2>/dev/null |
    awk '{ s += $1 } END { print s + 0 }')
}

clean_journal() {
  run sudo -n journalctl --vacuum-time="$OMS_JOURNAL_KEEP"
}

scan_coredumps() {
  [[ -d $COREDUMP_DIR ]] || return 1
  SCAN_BYTES=$(find "$COREDUMP_DIR" -type f -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { print s + 0 }')
}

clean_coredumps() {
  run sudo -n find "$COREDUMP_DIR" -mindepth 1 -type f -delete
}

scan_flatpak-unused() {
  command -v flatpak >/dev/null 2>&1 || return 1
  [[ -n $(flatpak list --runtime --columns=application 2>/dev/null) ]] || return 1
  SCAN_BYTES=-1
  SCAN_NOTE="runtimes no installed app needs, size known after removal"
}

clean_flatpak-unused() {
  run flatpak uninstall --user --unused --noninteractive &&
    run sudo -n flatpak uninstall --system --unused --noninteractive
}

ORPHANS=()

scan_orphans() {
  command -v pacman >/dev/null 2>&1 || return 1
  mapfile -t ORPHANS < <(pacman -Qdtq 2>/dev/null)
  ((${#ORPHANS[@]})) || return 1
  SCAN_BYTES=0
  local size
  while IFS= read -r size; do
    SCAN_BYTES=$((SCAN_BYTES + $(iec_to_bytes "$size")))
  done < <(LC_ALL=C pacman -Qi "${ORPHANS[@]}" 2>/dev/null | sed -n 's/^Installed Size *: *//p')
  SCAN_NOTE="$(plural ${#ORPHANS[@]} package): $(preview_list 4 "${ORPHANS[@]}")"
}

clean_orphans() {
  ((${#ORPHANS[@]})) || return 0
  run sudo -n pacman -Rns --noconfirm "${ORPHANS[@]}"
}

INSTALLERS=()

downloads_dir() {
  local dir
  dir=$(xdg-user-dir DOWNLOAD 2>/dev/null)
  [[ -n $dir && $dir != "$HOME" ]] || dir=$HOME/Downloads
  printf '%s' "$dir"
}

scan_installers() {
  local dir
  dir=$(downloads_dir)
  [[ -d $dir ]] || return 1
  mapfile -t INSTALLERS < <(find "$dir" -maxdepth 1 -type f \
    \( -name '*.deb' -o -name '*.rpm' -o -name '*.pkg.tar.*' -o -name '*.iso' -o -name '*.dmg' \
    -o -name '*.exe' -o -name '*.msi' \) -mtime +"$OMS_STALE_DAYS" 2>/dev/null)
  ((${#INSTALLERS[@]})) || return 1
  SCAN_BYTES=$(size_of "${INSTALLERS[@]}")
  local names=() file
  for file in "${INSTALLERS[@]}"; do
    names+=("$(basename "$file")")
  done
  SCAN_NOTE="$(plural ${#INSTALLERS[@]} file): $(preview_list 2 "${names[@]}")"
}

clean_installers() {
  local file failed=0
  for file in "${INSTALLERS[@]}"; do
    remove_path "$file" || failed=1
  done
  return "$failed"
}
