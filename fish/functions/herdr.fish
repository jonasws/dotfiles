function herdr --wraps herdr --description 'herdr, with a wider sidebar when the terminal is wide at connect time'
    # Only a bare `herdr` attaches a client UI; subcommands, nested herdr and an
    # explicit HERDR_CONFIG_PATH go straight through.
    if test (count $argv) -gt 0; or set -q HERDR_ENV; or set -q HERDR_CONFIG_PATH
        command herdr $argv
        return
    end

    set -l wide_cols 220
    set -l wide_sidebar 42
    set -l cols (tput cols 2>/dev/null; or echo 0)
    if test $cols -lt $wide_cols
        command herdr
        return
    end

    # herdr has no include/override mechanism, so the wide variant is a copy of
    # config.toml with one value swapped. It is rebuilt on every wide connect.
    set -l base $HOME/.config/herdr/config.toml
    set -l wide $HOME/.cache/herdr/config.wide.toml
    mkdir -p (path dirname $wide)
    sd '(?m)^sidebar_width = \d+' "sidebar_width = $wide_sidebar" <$base >$wide
    HERDR_CONFIG_PATH=$wide command herdr
end
