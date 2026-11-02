# Ghostty's Quick Terminal (ghostty/config.ghostty) opens straight into tuios,
# attached to the most recent session. Panes inside tuios set TUIOS_ENV, so
# they keep a plain shell even when the daemon was started from here.
if status is-interactive; and set -q GHOSTTY_QUICK_TERMINAL; and not set -q TUIOS_ENV
    set -e GHOSTTY_QUICK_TERMINAL
    exec tuios attach
end
