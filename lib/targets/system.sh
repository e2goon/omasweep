#!/usr/bin/env bash

JOURNAL_DIR=${OMS_JOURNAL_DIR:-/var/log/journal}
COREDUMP_DIR=${OMS_COREDUMP_DIR:-/var/lib/systemd/coredump}

target pacman "System" safe 1 "Old package versions" "keeps the newest $OMS_PACMAN_KEEP like omarchy update" "pacman yay paru"
target journal "System" safe 1 "Archived journal logs" "older than $OMS_JOURNAL_KEEP"
target coredumps "System" safe 1 "Crash dumps" "systemd-coredump archive"
target thumbnails "System" safe 0 "Thumbnail cache" "regenerated on demand"
paths thumbnails "$CACHE/thumbnails"
target orphans "System" review 1 "Orphaned packages" "installed as dependencies and no longer needed" "pacman yay paru"
target trash "System" review 0 "Trash" "files you deleted"
paths trash "$DATA/Trash/files" "$DATA/Trash/info"

scan_pacman() {
  command -v paccache >/dev/null 2>&1 || return 1
  local old uninstalled
  old=$(paccache -dk"$OMS_PACMAN_KEEP" 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  uninstalled=$(paccache -duk0 2>/dev/null | sed -n 's/.*disk space saved: \(.*\))/\1/p')
  SCAN_BYTES=$(($(iec_to_bytes "$old") + $(iec_to_bytes "$uninstalled")))
}

clean_pacman() {
  run sudo -n paccache -rk"$OMS_PACMAN_KEEP" && run sudo -n paccache -ruk0
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
