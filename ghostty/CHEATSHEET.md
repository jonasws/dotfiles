# Ghostty + Neovim — Keyboard Cheat Sheet

No multiplexer. Ghostty's native splits/tabs handle pane management; neovim
handles its own windows. Seamless `Ctrl+hjkl` flows across both layers.

**Owner** column: Ghostty (the terminal) or Neovim (via smart-splits.nvim).

## How the seamless navigation works

`Ctrl+hjkl` is bound in ghostty as `performable:goto_split`. Ghostty consumes
the key **only if a ghostty split exists** in that direction; otherwise the key
falls through to the running program. Inside neovim, smart-splits.nvim then moves
between nvim windows. One keymap, both layers — no multiplexer.

Caveat: ghostty checks first, so if a ghostty split AND an nvim split both exist
in the same direction, ghostty wins. Run one nvim per ghostty split to avoid it.

## Navigation (splits)

| Keys | Action | Owner |
|---|---|---|
| `Ctrl+h/j/k/l` | Move between splits — ghostty splits and nvim windows, seamlessly | Ghostty (`performable:goto_split`) → falls through to Neovim (smart-splits) |
| `Cmd+[` / `Cmd+]` | Previous / next split | Ghostty |
| `Cmd+Alt+←↑↓→` | Move to split in arrow direction | Ghostty (default) |

## Splitting

| Keys | Action | Owner |
|---|---|---|
| `Cmd+D` | New split **below** (wezterm muscle memory) | Ghostty |
| `Cmd+R` | New split **right** (wezterm muscle memory) | Ghostty |
| `Cmd+Shift+Enter` | Toggle split zoom (maximize current split) | Ghostty (default) |
| `Cmd+Ctrl+=` | Equalize all split sizes | Ghostty (default) |
| `Cmd+Ctrl+←↑↓→` | Resize split in arrow direction | Ghostty (default) |

Zoomed splits stay zoomed while navigating (`split-preserve-zoom = navigation`).

## Resize (inside neovim)

| Keys | Action | Owner |
|---|---|---|
| `Alt+h/j/k/l` | Resize nvim window left/down/up/right | Neovim (smart-splits) |

(`macos-option-as-alt = true` makes Option send Alt so these reach nvim.)

## Tabs (ghostty native)

| Keys | Action | Owner |
|---|---|---|
| `Cmd+T` | New tab | Ghostty (default) |
| `Cmd+W` / `Cmd+Alt+W` | Close tab | Ghostty (default) |
| `Cmd+1`–`8` | Jump to tab N | Ghostty (default) |
| `Cmd+9` | Last tab | Ghostty (default) |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab | Ghostty (default) |
| `Cmd+Shift+[` / `Cmd+Shift+]` | Previous / next tab | Ghostty (default) |

## Terminal-level (Ghostty)

| Keys | Action | Owner |
|---|---|---|
| `Shift+Enter` | Literal newline (Claude Code multiline) | Ghostty |
| `Cmd+Shift+R` | Reload config (custom; avoids mishitting `Cmd+Shift+,`) | Ghostty |
| `Cmd+,` | Open config file | Ghostty (default) |
| `Cmd+click` on URL | Open URL in browser | Ghostty (default) |
| `Cmd+C` / `Cmd+V` | Copy / paste | Ghostty (default) |
| `Cmd+=` / `Cmd+-` / `Cmd+0` | Font size up / down / reset | Ghostty (default) |
| `Cmd+Q` | Quit | Ghostty |

## Neovim window keys (reference)

| Keys | Inside nvim | At nvim edge → ghostty split |
|---|---|---|
| `Ctrl+h/j/k/l` | Move between nvim windows (smart-splits) | Key reached nvim only because ghostty had no split that way |
| `Alt+h/j/k/l` | Resize nvim window | — (resize is nvim-only) |

smart-splits.nvim: `multiplexer_integration = false`, `at_edge = "stop"` — no
mux backend, ghostty owns the outer split layer.

## Notes vs wezterm

- **No multiplexer** — no session persistence across restart, no SSH-side panes.
  Ghostty splits are GPU-native and per-window only.
- **URL keyboard-labels** (wezterm `Cmd+O` QuickSelect): not available. Use
  `Cmd+click`. The `ext+container:` Firefox scheme is not handled.
- **Splits don't survive quit** — closing the window loses the layout.
