function __fnox_complete_passthrough \
        --description "Complete the command after fnox's `--`"
    # Lazy `.*?`, so a `--` among the wrapped command's own arguments is left
    # alone: only fnox's separator, the first one, is stripped.
    set -l rest (string replace -r '^.*?\s--\s' '' -- (commandline -cp))
    if test -z (string trim -- "$rest")
        # `complete -C ""` returns nothing, so the empty case is handled here:
        # right after `-- ` the candidates are commands.
        __fish_complete_command
        return 0
    end
    # fish completing a command line handed to it: descriptions, flags and
    # subcommands, from whatever completion that command already has.
    complete -C -- $rest
end
