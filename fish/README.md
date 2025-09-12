# Fish Configuration

This fish configuration is modularized for better organization and easier maintenance.

## Structure

```
fish/
├── config.fish          # Main config (minimal, loads everything else)
├── config.fish.backup   # Backup of original monolithic config
├── functions/            # Custom functions (auto-loaded on demand)
│   ├── aws.fish
│   ├── build-screen.fish
│   ├── changeAwsProfileBackground.fish
│   ├── console.fish
│   ├── deployments.fish
│   ├── fish_postexec.fish
│   ├── fish_preexec.fish
│   ├── fish_user_key_bindings.fish
│   ├── gcal.fish
│   ├── nittedal.fish
│   ├── notify.fish
│   ├── view-ci.fish
│   └── y.fish
├── conf.d/               # Configuration files (auto-loaded at startup)
│   ├── 00-environment.fish  # Environment variables, PATH
│   ├── 10-aliases.fish      # Aliases
│   ├── 20-abbreviations.fish # Abbreviations
│   └── 30-interactive.fish  # Interactive shell setup
└── README.md
```

## Benefits

- **Instant updates**: Edit functions directly without rebuild-switch
- **Modular**: Separate concerns for easier maintenance
- **Auto-loading**: Fish automatically loads functions and conf.d files
- **Git-tracked**: All configuration in dotfiles repo
- **Nix-compatible**: Uses symlinks like other dotfiles

## Usage

The entire fish directory is symlinked to `~/.config/fish/` via nix-darwin home-manager.

To modify:
1. Edit files in `~/dotfiles/fish/`
2. Changes are immediately available (no rebuild needed)
3. Functions are loaded on first use
4. conf.d files are loaded at shell startup

## Migration

The original config.fish has been backed up as `config.fish.backup`.