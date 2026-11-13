# Ghostty

The terminal everything runs in, since 2026-11-02 (before that it was WezTerm).
All settings are in [`config.ghostty`](config.ghostty). The `ghostty` dotfile
group links this directory to `~/.config/ghostty`. Homebrew installs Ghostty and
keeps it updated, so Ghostty's own updater is off.

- **Check**: `ghostty +validate-config`
- **Reload**: Cmd+Shift+R

## What it is set up for

Ghostty's main job is hosting tuios. Most settings either let keys through to
tuios or make Ghostty and tuios look the same.

- **Theme**: Ghostty's bundled Catppuccin Mocha, always dark. tuios uses the
  same sixteen colours (`tuios/themes/mocha-ghostty.json`). `themes/` holds
  catppuccin/ghostty's Mocha file, which isn't selected.
- **Font**: JetBrains Mono 18 for text, with the Nerd Font Mono build for
  glyphs. Slashed zero (`zero`), single-storey g (`cv03`), and
  `adjust-font-baseline = 1` for the office ultrawide.
- **Colour**: `display-p3`, `minimum-contrast = 3` and `faint-opacity = 0.75`,
  which keep Claude Code's dim and faint text readable.
- **Window**: 0.9 opacity with blur, no title bar, padding filled with the edge
  colour so the tuios rail and dock reach the border, and windows restored on
  launch (tuios restores the sessions inside them).
- **Option is Alt** on both sides.

## Keys

Ghostty leaves most chords to tuios. tuios's own keys are in
[`../tuios/README.md`](../tuios/README.md).

| Key | Goes to |
| --- | ------- |
| Ctrl+hjkl, Ctrl+Shift+hjkl | The pane: tuios/Neovim split movement and resize (herdr-splits). |
| Cmd+K, Cmd+O, Cmd+P, Cmd+, | tuios: pane navigator, agent sessions, palette, go-to picker. |
| Cmd+T, Cmd+N, Cmd+1..9, Ctrl+(Shift+)Tab | tuios workspaces. |
| Cmd+R, Cmd+D, Cmd+W | tuios: split right, split down, close pane. |
| Cmd+[, Cmd+] | tuios jump list. |
| Cmd+. | tuios pane labels. AppKit swallows this chord, so Ghostty sends tuios the kitty-protocol encoding directly. |
| Shift+Enter | ESC CR, which Claude Code reads as a newline. |
| Option+Left/Right | Passed through as arrows instead of being rewritten to word jumps. |
| Cmd+Shift+P / N / T | Ghostty's palette, new window, new tab. |
| Cmd+L then hjkl | Moves between Ghostty's own splits. |

## Quick terminal

F19 drops a Ghostty panel from the top of the screen, from any app. Something
else has to send F19: a double tap of right Option on the built-in keyboard
(`karabiner-ts/`), or of Home on the Keychron (`keychron/`, which is still
pending). The panel opens tuios's `quick` session
(`fish/conf.d/55-ghostty-quick-terminal.fish`) and hides when it loses focus.
It needs Accessibility permission.
