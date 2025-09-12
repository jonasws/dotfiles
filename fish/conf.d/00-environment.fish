# Environment variables and PATH
set -x LC_ALL en_US.UTF-8
set -x PATH /Users/jonasws/.local/bin /etc/profiles/per-user/jonasws/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin /Applications/WezTerm.app/Contents/MacOS /usr/local/bin /System/Cryptexes/App/usr/bin /usr/bin /bin /usr/sbin /sbin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin $PATH

set -x XDG_CONFIG_HOME "$HOME/.config"

# Tool configurations
set -x LS_COLORS (vivid generate catppuccin-mocha)
set -x VISUAL nvim
set -x EDITOR nvim
set -x BD_OPT insensitive
set -x RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# FZF configurations
set fzf_preview_dir_cmd eza --all --color=always
set fzf_history_opts --with-nth="4.." --preview-window="down,30%,border-top,wrap"
set fzf_diff_highlighter delta --paging=never --width=20

# Bat and paging configurations
set -x FX_THEME 1
set -x FX_SHOW_SIZE true
set -x BATDIFF_USE_DELTA true
set -x BAT_THEME "Catppuccin Mocha"
set -x GLAMOUR_STYLE "$HOME/catppuccin/glamour/themes/catppuccin-mocha.json"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

# Global variables
set -g _one_off_aws_command false

# Fish configuration
set fish_key_bindings fish_vi_key_bindings