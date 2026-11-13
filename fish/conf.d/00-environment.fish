# Environment variables and PATH
# English for everything but dates: day-first, 24-hour time. No LC_ALL, so
# one-off overrides like `LC_ALL=C sort` stay the only use of it.
set -x LANG en_US.UTF-8
set -x LC_TIME en_GB.UTF-8
set -e LC_ALL
# System directories come from /etc/paths and /etc/paths.d, which fish's own
# login init reads on macOS (its path_helper emulation); child shells inherit
# them. Homebrew goes in here rather than in an interactive-only block so that
# scripts and `fish -c` see the same tools. Its exported HOMEBREW_PREFIX lets
# child shells skip the brew call.
if not set -q HOMEBREW_PREFIX; and test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
end

# Added after brew so they sit in front of it: keg-only curl over macOS's, and
# the terminals' CLIs. --move keeps the order without duplicating entries.
# Homebrew's own bin dirs are moved too: a child login shell skips brew
# shellenv, and fish's /etc/paths init has put /usr/bin and /bin back in front.
fish_add_path --global --move --path \
    /opt/homebrew/bin \
    /opt/homebrew/sbin \
    /Applications/WezTerm.app/Contents/MacOS \
    /Applications/Ghostty.app/Contents/MacOS \
    /opt/homebrew/opt/curl/bin
fish_add_path --global --move --path $HOME/.local/bin

# Homebrew's mise ships a vendor_conf.d snippet that activates mise in every
# shell. It sorts after these files, too late for the tools 30-interactive.fish
# starts, which activates mise itself; the shims in fish_user_paths serve
# non-interactive shells.
set -gx MISE_FISH_AUTO_ACTIVATE 0

set -x XDG_CONFIG_HOME "$HOME/.config"

# Tool configurations
# vivid's output only changes with the theme; child shells inherit it.
set -q LS_COLORS; or set -x LS_COLORS (vivid generate catppuccin-mocha)
set -x VISUAL nvim
set -x EDITOR nvim
set -x BD_OPT insensitive
set -x RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# Bat and paging configurations
set -x FX_THEME 1
set -x FX_SHOW_SIZE true
set -x FX_INDENT 2
set -x BATDIFF_USE_DELTA true
set -x BAT_THEME "Catppuccin Mocha"
set -x GLAMOUR_STYLE "$HOME/catppuccin/glamour/themes/catppuccin-mocha.json"
# What `batman --export-env` prints, through the stable Homebrew link rather
# than its versioned Cellar path.
set -x MANPAGER "env BATMAN_IS_BEING_MANPAGER=yes bash /opt/homebrew/bin/batman"
set -x MANROFFOPT -c

# Global variables

set -x AWS_VAULT_KEYCHAIN_NAME login
# Every concurrent aws-vault must take the locks, including the ones you run yourself.
set -x AWS_VAULT_PARALLEL_SAFE true
