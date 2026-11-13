# Neovim (LazyVim)

A [LazyVim](https://lazyvim.github.io) config, linked as a whole directory to
`~/.config/nvim` (the `lazyvim` dotfile group). The whole directory is linked so
that `lazy-lock.json` changes land in the repo.

- **`nvim`**: Neovim `latest` from mise (0.12 at the moment).
- **`nvn`**: the nightly build (`mise run update:nvim-nightly`). It's needed for
  the built-in multicursor below.
- **Updates**: `mise run update:nvim` runs `Lazy! sync`, then
  [`headless-update.lua`](headless-update.lua), which upgrades Mason packages and
  treesitter parsers. Neither of those upgrades itself. The daily
  `mise run update` includes it.

## Layout

| Path | Holds |
| ---- | ----- |
| [`lazyvim.json`](lazyvim.json) | Enabled LazyVim extras: Claude Code, harpoon2, aerial, dial, yanky, inc-rename, the mini plugins; language extras for Kotlin, TypeScript (+ biome, eslint, prettier), Python, Terraform, SQL, Docker, YAML, TOML, JSON, Markdown, Nushell. |
| [`lua/config/options.lua`](lua/config/options.lua) | `clipboard = ""` (yanks stay out of the system clipboard), `list = false`. |
| [`lua/config/keymaps.lua`](lua/config/keymaps.lua) | Ctrl+hjkl / Ctrl+Shift+hjkl split movement and resize. |
| [`lua/config/autocmds.lua`](lua/config/autocmds.lua) | No autoformat for XML, no diagnostics in SQL and Markdown, and the Rex marker file. |
| [`lua/plugins/`](lua/plugins/) | One file per plugin or override, listed below. |

## Plugins added or changed

- **Colours**: catppuccin with `flavour = "auto"`, so it follows the light/dark
  setting tuios reports. Transparent background and floats, rainbow-delimiters.
- **Split movement**: Ctrl+hjkl crosses between Neovim windows and tuios panes.
  - Inside tuios, panes set `HERDR_ENV=1`, which loads `herdr-splits.nvim`.
    It's loaded from a local fork at `~/herdr-splits.nvim`, which has to exist.
    The fork adds `forward`, which hands a move at the layout's edge to the
    host terminal.
  - Outside tuios, `smart-splits.nvim` loads instead. Its only backend is Rex,
    so with no Rex it moves between Neovim windows only.
- **Multicursor** (`util/multicursor.lua`, `plugins/multicursor.lua`): Neovim
  0.13's built-in multicursor, with a lualine count and which-key labels
  (`Q`, `zq`, `gQ`, `]C`/`[C`). It only shows up when running `nvn`. Ctrl+L
  clears the cursors first and moves to the right split only when there are
  none.
- **claudecode.nvim**: the terminal is on the right at 40%.
  `<leader>ap` picks a file to add to Claude.
- **LSP**: `cdk_lsp`, run through `npx cdk lsp` in projects that have a
  `cdk.json`; taplo with the mise schema for `mise.toml`.
- **Formatting and linting**: sqlfluff for Postgres in conform and nvim-lint,
  and xmlformatter.
- **Small ones**: op.nvim (1Password), mini.align, aerial resizing to fit its
  content, trouble as a 40% split, render-markdown without signs or heading
  icons, and yanky's `<leader>P` to put over a selection.
