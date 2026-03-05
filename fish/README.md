# Fish Configuration

This fish configuration is managed with GNU stow.

## Structure

```
fish/
└── .config/
    └── fish/
        ├── config.fish          # Main config
        ├── functions/           # Custom functions (auto-loaded on demand)
        ├── conf.d/              # Configuration files (auto-loaded at startup)
        │   ├── 00-environment.fish
        │   ├── 10-aliases.fish
        │   ├── 20-abbreviations.fish
        │   └── 30-interactive.fish
        └── completions/         # Custom completions
```

## Setup

From the dotfiles root:

```sh
stow fish
```

This symlinks `fish/.config/fish/` to `~/.config/fish/`.

## Usage

Edit files under `fish/.config/fish/` and changes are immediately available.
Functions are loaded on first use; conf.d files are loaded at shell startup.
