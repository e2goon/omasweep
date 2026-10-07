# omasweep

Reclaim disk space on [Omarchy](https://omarchy.org). omasweep is a terminal cleaner (`oms`) plus an
Omarchy shell bar widget. It knows where an Arch + Hyprland developer machine piles up space:
the pacman cache, old [mise](https://mise.jdx.dev) tool versions, Docker build cache, developer
caches, browser caches, Steam shader caches, and `node_modules` in projects you stopped touching.

```
 ┏━┓┏┳┓┏━┓┏━┓╻ ╻┏━╸┏━╸┏━┓
 ┃ ┃┃┃┃┣━┫┗━┓┃╻┃┣╸ ┣╸ ┣━┛
 ┗━┛╹ ╹╹ ╹┗━┛┗┻┛┗━╸┗━╸╹
 Sweep your Omarchy · v0.1.0

➤ Safe to sweep · 18.4 GB
   1 ● Old mise tool versions        8.7 GB       51 versions no config needs
   2 ● Docker build cache            6.6 GB       docker builder prune
   3 ● npm cache                     2.9 GB       downloaded again on install
   4 ● Old package versions        412.0 MB sudo  keeps the newest 2 like omarchy update

➤ Review first
   5 ○ Steam shader cache            3.4 GB       rebuilt on next launch with some stutter
   6 ○ Stale node_modules            1.1 GB       2 projects: old-site, demo

➤ Skipped while in use
     ○ Chromium cache                1.5 GB       close chromium to include this
```

## Highlights

- **Ranked by value.** Safe items come first, largest first, and are preselected. Items that cost
  you something (Trash, shader caches, project dependencies, orphaned packages) are listed but
  stay opt-in.
- **You pick, then it sweeps.** A checklist (via [gum](https://github.com/charmbracelet/gum)) lets
  you toggle items, then you confirm once. `--dry-run` shows exactly which commands would run and
  which directories would be emptied.
- **Uses each tool's own cleanup.** `mise prune`, `docker builder prune`, `paccache`,
  `journalctl --vacuum-time`, `uv cache prune`, and `pnpm store prune` instead of deleting their
  data behind their back.
- **Leaves running apps alone.** A browser or Steam cache is skipped while that app is open.
- **Omarchy-native.** Follows the active theme (ANSI palette and Omarchy's gum colors), keeps two
  package versions like `omarchy update` does, opens in Omarchy's floating terminal from the bar,
  and asks for `sudo` in that terminal only when a selected item needs it.
- **Honest numbers.** The summary shows what was swept and how much free space actually changed.
  When those differ (Btrfs snapshots or hard links still hold the data), it says so.

## Install

### Bar widget and CLI

```bash
omarchy plugin add https://github.com/e2goon/omasweep.git --enable
~/.config/omarchy/plugins/io.github.e2goon.omasweep/bin/oms link
```

The first command installs the widget into the bar. The second links `oms` into `~/.local/bin` so
you can run it from any terminal. `omarchy plugin update io.github.e2goon.omasweep` updates both.

### CLI only

```bash
git clone https://github.com/e2goon/omasweep.git ~/.local/share/omasweep
~/.local/share/omasweep/bin/oms link
```

Requirements: Bash 5, coreutils, findutils, and `jq` (for `oms scan --json` and the widget). `gum`
is used when present and ships with Omarchy. Tools such as `mise`, `docker`, `paccache`
(`pacman-contrib`), `uv`, or `pnpm` are only used when installed; their targets are skipped
otherwise.

## Usage

```bash
oms                         # scan, pick, confirm, sweep
oms scan                    # show what can be reclaimed, change nothing
oms clean --dry-run         # walk through a sweep without deleting anything
oms clean --yes             # sweep every safe item without prompts
oms clean --only mise,docker-build
oms clean --all --skip trash
oms whitelist               # protect paths or whole targets
oms log                     # what was removed, skipped, or failed
```

| Option | Meaning |
| --- | --- |
| `-n`, `--dry-run` | Preview the sweep. Nothing is deleted and nothing is logged. |
| `-y`, `--yes` | Do not ask. Sweeps the safe items unless `--all` or `--only` is given. |
| `-a`, `--all` | Preselect review items too. |
| `--only ID,...` | Sweep only these targets. IDs are listed by `oms scan`. |
| `--skip ID,...` | Leave these targets out. |
| `--debug` | Print each command and its output. |
| `--hold` | Wait for a key before exiting. The bar widget uses this. |

Without a terminal, `oms clean` refuses to run unless you pass `--yes` or `--dry-run`. Running it
as root is refused as well; it asks for `sudo` itself.

## What it sweeps

| ID | What | Tier | How |
| --- | --- | --- | --- |
| `pacman` | Old package versions in `/var/cache/pacman/pkg` | safe, sudo | `paccache -rk2` and `paccache -ruk0` |
| `journal` | Archived journal files older than four weeks | safe, sudo | `journalctl --vacuum-time=4weeks` |
| `coredumps` | `systemd-coredump` archive | safe, sudo | delete files in `/var/lib/systemd/coredump` |
| `thumbnails` | `~/.cache/thumbnails` | safe | empty the directory |
| `orphans` | Packages installed as dependencies that nothing needs | review, sudo | `pacman -Rns` on `pacman -Qdtq` |
| `trash` | `~/.local/share/Trash` | review | empty the directory |
| `mise` | Tool versions no mise config refers to | safe | `mise prune` |
| `docker-build` | Docker build cache | safe | `docker builder prune -af` |
| `docker-images` | Every image no container uses, including ones you pulled on purpose | review | `docker image prune -af` |
| `aur` | yay and paru build clones | safe | empty `~/.cache/yay`, `~/.cache/paru` |
| `npm` | `~/.npm/_cacache`, `_npx`, `_logs` | safe | empty the directories |
| `pnpm` | pnpm metadata cache | safe | empty `~/.cache/pnpm` |
| `pnpm-store` | Store packages no project links to | safe | `pnpm store prune` |
| `uv`, `pip`, `bun`, `go`, `cargo` | Package and build caches (Cargo keeps extracted sources) | safe | `uv cache prune` or empty the cache |
| `build-misc` | node-gyp, TypeScript, Yarn, Deno, mise downloads | safe | empty the directories |
| `chromium`, `chrome`, `brave`, `firefox` | Browser HTTP caches in `~/.cache` (profiles and logins are untouched) | safe | empty the directory |
| `steam-shaders` | Steam shader cache | review | empty the directory |
| `node-modules` | `node_modules` in projects untouched for 30 days | review | remove the directory |

Docker volumes, containers, your downloads, project sources, and anything under `~/.config` are
never touched. Btrfs snapshots are not deleted; if a sweep frees less than expected on a
snapper-managed root, omasweep tells you to review `sudo snapper list`.

## Whitelist

`oms whitelist` opens `~/.config/omasweep/whitelist`. One entry per line:

```
# Skip a whole target
docker-images

# Never delete this path or anything below it. Globs work.
~/.cache/pnpm
~/Work/keep-this/node_modules
```

## Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `OMS_PACMAN_KEEP` | `2` | Package versions kept in the pacman cache |
| `OMS_JOURNAL_KEEP` | `4weeks` | Journal age kept by `journalctl --vacuum-time` |
| `OMS_STALE_DAYS` | `30` | Days without changes before a project's `node_modules` counts as stale |
| `OMS_PROJECT_DIRS` | `~/Work:~/Projects:~/projects:~/Code:~/code:~/src:~/dev` | Where to look for `node_modules` |
| `NO_COLOR` | unset | Disable colors |

The widget has two settings. `showSize` puts the safe total next to the icon, and
`refreshIntervalMin` sets how often that total is rescanned:

```bash
omarchy bar set io.github.e2goon.omasweep showSize true --json
omarchy bar set io.github.e2goon.omasweep refreshIntervalMin 60 --json
```

## Files

| Path | Purpose |
| --- | --- |
| `~/.config/omasweep/whitelist` | Protected paths and skipped targets |
| `~/.local/state/omasweep/operations.log` | Every removal, command, skip, and failure (rotated at 5 MB) |

## Development

```bash
git clone https://github.com/e2goon/omasweep.git ~/Work/omasweep
ln -s ~/Work/omasweep ~/.config/omarchy/plugins/io.github.e2goon.omasweep
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.e2goon.omasweep
tests/run.sh
```

`tests/run.sh` never touches your system. It:

- checks syntax, runs `shellcheck` when installed (`uvx --from shellcheck-py shellcheck` works
  too), runs `qmllint` against the Omarchy shell modules, and validates the plugin manifest
- replaces `sudo`, `paccache`, `pacman`, `journalctl`, `mise`, `docker`, `uv`, `pnpm`, and `pgrep`
  with stubs that record their arguments, so every cleanup command is checked exactly
- sweeps a throwaway home directory and confirms what is removed and what survives: whitelisted
  paths, symlink targets, caches of running apps, recent projects, and anything outside `$HOME`

After editing `BarWidget.qml` through a symlinked checkout, run `omarchy restart shell` to load
the change.

The plugin follows the [Omarchy shell plugin manual](https://github.com/omacom/omarchy/blob/quattro/manual/32-shell-plugins.md)
and [shell reference](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md).

## Credits

The CLI flow (dry run, whitelist, operation log, in-use deferral, and the free-space summary) is
inspired by [Mole](https://github.com/tw93/mole), the macOS cleaner by tw93. omasweep shares no code
with Mole and is not affiliated with it.

## License

[MIT](LICENSE)
