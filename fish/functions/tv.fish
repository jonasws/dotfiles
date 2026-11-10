function tv --wraps tv --description 'television, with the layout chosen by terminal width'
    # tv picks portrait or landscape from config alone, never from the
    # terminal's size. Pass --layout by width unless the call already names
    # one: side by side from $TV_LANDSCAPE_COLUMNS columns (160) up, preview
    # below on anything narrower. Subcommands and help take no layout.
    set -l subcommands list-channels init completions update-channels help
    if contains -- "$argv[1]" $subcommands
        or contains -- --layout $argv
        or string match -q -- '--layout=*' $argv
        or contains -- -h $argv; or contains -- --help $argv
        or contains -- -V $argv; or contains -- --version $argv
        command tv $argv
        return
    end

    set -l min (set -q TV_LANDSCAPE_COLUMNS; and echo $TV_LANDSCAPE_COLUMNS; or echo 160)
    set -l layout portrait
    test "$COLUMNS" -ge $min; and set layout landscape
    command tv --layout $layout $argv
end
