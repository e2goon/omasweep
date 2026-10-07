# Contributing

Issues and pull requests are welcome. Please run `tests/run.sh` before opening a pull request and
follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `perf:`,
`docs:`, `test:`, `refactor:`).

## Layout

| Path | Purpose |
| --- | --- |
| `bin/oms` | CLI entry point: commands, the table, the picker, the sweep, and the summary |
| `lib/ui.sh` | Colors, glyphs, sizes, spinner, prompts |
| `lib/core.sh` | Whitelist, path safety, deletion, operation log |
| `lib/engine.sh` | Target registry, path and busy resolution, scan and clean dispatch, ranking |
| `lib/targets/*.sh` | Target definitions, one file per section |
| `BarWidget.qml` | Omarchy shell bar widget |
| `tests/run.sh` | Test suite with stubbed system commands |

## Adding a target

A target is declared with `target` and, when it is a set of cache folders, `paths`:

```bash
target zig "Developer tools" safe 0 "Zig global cache" "rebuilt on next build" "zig"
paths zig "$CACHE/zig"
```

The arguments are the ID, section, tier (`safe` or `review`), whether it needs `sudo` (`1` or `0`),
a label of at most 26 characters, a short note, and what marks it as in use. Busy tokens are
process names, `lock:<path>` for a Chromium or Firefox style lock symlink, `match:<pattern>` for
`pgrep -f`, `flatpak:<app id>`, and `name:<label>` for the name shown to the user.

`paths` entries may be globs. Their contents are emptied; the folders themselves stay. Symlinked
folders and anything outside `$HOME` are skipped.

When the tool has a cleanup command, or the target needs custom measuring, define
`scan_<id>` (set `SCAN_BYTES`, optionally `SCAN_NOTE`, return 1 when there is nothing to show) and
`clean_<id>` (wrap every command in `run` so dry runs and the log work). Commands that need root
go through `run sudo -n ...`.

Before proposing a target, check that:

- the data is recreated by its owner without the user doing anything, or the target is `review`
- it never contains logins, cookies, history, settings, saves, or user documents
- running apps are detected, so nothing is deleted under an open app
- `tests/run.sh` covers what is removed and what must stay
