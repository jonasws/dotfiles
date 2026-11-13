# Fish setup improvements

Checkup of the fish 4.9.3 setup (Homebrew, login shell). Interactive login
startup: 0.24 s → **0.18 s**. PATH: 179 entries (130 unique) → 123, all unique.
Universal variables: 186 → 12.

- [x] **Duplicate `brew shellenv`.** Moved out of the interactive-only block in
  `30-interactive.fish` to the top of `00-environment.fish`, run once per shell
  tree (guarded by the inherited `HOMEBREW_PREFIX`).
- [x] **Hand-rolled PATH removed.** System directories come from fish's own
  macOS login init (`/etc/paths`, `/etc/paths.d`). `~/.local/bin`, the terminal
  CLIs and keg-only curl are added with `fish_add_path --global --move --path`.
  Nix directories dropped.
- [x] **Dead and duplicate `fish_user_paths` entries.** Removed `per-user/jonasws/bin`,
  `opt/bison`, `opt/avr-gcc@8`, `opt/make/libexec/gnubin`, `/opt/homebrew/bin`,
  `opt/curl/bin`, `opt/fzf/bin`.
- [x] **mise activated twice.** `MISE_FISH_AUTO_ACTIVATE=0` turns off Homebrew's
  `vendor_conf.d/mise-activate.fish`; `30-interactive.fish` activates it, the
  shims in `fish_user_paths` serve non-interactive shells.
- [x] **Stale universal variables.** 170 Tide variables and the fisher records
  for dracula, nix-env, mock and plugin-direnv erased. Backup:
  `/private/tmp/claude-501/-Users-jonasws-dotfiles/d5d1407c-4e7c-4633-baf4-2ea9a319591d/scratchpad/fish_variables.bak`.
- [x] **Leftover `fishd.tmp.*` files** moved to the graveyard (`rip -u`).
- [x] **`batman --export-env`** (25 ms per interactive start) written out as
  `MANPAGER` and `MANROFFOPT` in `00-environment.fish`, through the stable
  `/opt/homebrew/bin/batman` link. Replaces the old bat `MANPAGER`.
- [x] **`vivid generate`** runs only when `LS_COLORS` isn't inherited.
- [x] **`brew shellenv` written out by hand?** Decided against: it already runs
  once per shell tree and is Homebrew's documented setup.
- [x] **fzf: one install, from mise.** fzf.fish plugin removed (files in the
  graveyard) with its fisher records, `fzf_*` variables and bindings block.
  Homebrew's fzf uninstalled (nothing depended on it) and dropped from
  `homebrew/Brewfile` and `Brewfile.versions`. mise's 0.75.0 remains, for
  yazi and rex.
- [x] **Vi key bindings set twice.** Removed from `00-environment.fish`; the
  `set -g` in `config.fish` stays.
- [x] **Formatting.** `fish_indent -w` on the 8 flagged files; every change was
  a missing final newline. `fish_indent --check` passes on all of `fish/`.
  fish_indent has no style options: always 4 spaces, no tabs, no width or
  `.editorconfig` support.
- [x] **curl: keep Homebrew's, remove mise's.** (Done by you.) Three curls are installed:
  Homebrew 8.23.0 (OpenSSL 4.1, HTTP/3, brotli, zstd), mise's
  `aqua:stunnel/static-curl` 8.20.0 (installed but in no config, so its shim
  falls through to Homebrew's), and macOS's 8.7.1 (LibreSSL). Homebrew's is
  newest, patched first and most featureful. Pending: `mise uninstall
  aqua:stunnel/static-curl` to drop the stale install and shim.
- [x] **WezTerm and Ghostty CLIs on PATH.** Kept in fish for now. Moving them
  into each terminal's config wouldn't reach panes the tuios daemon starts
  (the reason Ghostty's went into fish in `2ed12f8`). `fish_add_path` skips
  folders that don't exist, so the lines are already harmless where the app
  isn't installed.
- [x] **ctrl-r goes to atuin.** It has cwd, exit code, duration and
  session/directory/workspace filters; tv's history channel reads plain
  `fish -c history`. Bound to `_atuin_search` in default and insert mode right
  after `atuin init` in `30-interactive.fish`, which runs after `tv init`;
  the dead binds in `fish_user_key_bindings.fish` removed. tv keeps ctrl-t.
- [x] **Orphaned files in `~/.config/fish`.** (Done by you.) 22 real files are owned by no
  fisher plugin and not in the dotfiles. Candidates for removal:
  - `themes/Dracula Official.theme`: dracula plugin gone; Catppuccin is in use.
  - `completions/mdless.fish`: mdless isn't installed.
  - Stale copies that shadow newer Homebrew-shipped completions:
    `completions/doggo.fish`, `fx.fish`, `gcalcli.fish`, `mise.fish`,
    `wezterm.fish`.

  Keep, but consider moving into the dotfiles:
  - Saved aliases: `functions/cx-pipeline.fish`, `pipeline.fish`,
    `terminal-pipeline.fish`, `tt.fish`.
  - Generated completions with no vendor copy: `docker`, `gh`, `glow`, `leaf`,
    `mdcat`, `pingu`, `ppress`, `qsv`, `rgrc`, `sg`.
  - `themes/Catppuccin Mocha.theme` (in use).
- [x] **`LC_ALL` replaced** by `LANG=en_US.UTF-8` and `LC_TIME=en_GB.UTF-8`
  (24-hour time, day before month, English names). Numbers stay English:
  `nb_NO` makes `printf '%.2f' 3.5` fail (decimal comma).
- [x] **Dead PATH entries from `/etc/paths.d`** (`10-cryptex`,
  `10-pmk-global`): won't fix. macOS and managed-device files.
