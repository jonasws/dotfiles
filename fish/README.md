# Fish Configuration

This fish configuration is deployed by the `fish` dotfile group in `mise.toml`.

## Structure

```
fish/                    # deployed to ~/.config/fish/
├── config.fish          # Main config
├── functions/           # Custom functions (auto-loaded on demand)
│   ├── fish_title.fish  # Overrides fish's default terminal title (repo@branch)
│   └── fish_user_key_bindings.fish  # Overrides fish's default key bindings
├── conf.d/              # Configuration files (auto-loaded at startup)
│   ├── 00-environment.fish
│   ├── 10-aliases.fish
│   ├── 20-abbreviations.fish
│   ├── 30-interactive.fish          # mise activate, prompt, tool init
│   ├── 40-fnox-completion.fish
│   ├── 45-rex-herdr.fish            # Rex only; inert elsewhere
│   └── 55-ghostty-quick-terminal.fish  # F19 panel opens tuios's "quick" session
└── completions/         # Custom completions
```

## Setup

From the dotfiles root:

```sh
mise dot apply
```

This links each file under `fish/` into `~/.config/fish/`.

## Usage

Edit files under `fish/` and changes are immediately available.
Functions are loaded on first use; conf.d files are loaded at shell startup.
