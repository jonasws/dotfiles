function __claude_model --description 'claude with a fixed --model and a default --effort the caller can override'
    # $argv[1] is the model, the rest is the caller's command line. The
    # `effort=&` spec takes --effort out of $argv and $argv_opts, so it is
    # passed once. --move-unknown keeps every other option for claude, and
    # --stop-nonopt leaves the first non-option and everything after it in
    # place, so a prompt or a flag's value never changes order.
    set -l model $argv[1]
    set -e argv[1]
    argparse --strict-longopts --move-unknown --unknown-arguments=none --stop-nonopt 'effort=&' -- $argv
    or return

    set -l effort medium
    set -q _flag_effort; and set effort $_flag_effort[-1]
    command claude --model $model --effort $effort $argv_opts $argv
end
