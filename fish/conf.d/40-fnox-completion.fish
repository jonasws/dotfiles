# fnox completion, extended to complete the command that follows `--`.
#
# fnox's own generated completion is good on the fnox side: `fnox exec -P <TAB>`
# lists profiles dynamically. What it cannot do is the other side of `--`. Asked
# about `fnox exec -P staging -- git sta`, the binary answers with its "files"
# marker, so fish offers filenames where git subcommands belong. Everything
# after `--` is another command's command line, and the command being wrapped is
# the only thing that knows how to complete it.
#
# Why this is a prompt handler and not completions/fnox.fish:
#
#   - That file is never reached. mise owns fnox's completion, and its stub
#     completes in a child `fish --no-config` with an emptied fish_complete_path
#     precisely so the tool's own completion file cannot autoload.
#   - `mise hook-env` reinstalls that stub on every directory change. It saves
#     the rules it finds, erases them, registers `__mise_load_fnox`, and defines
#     __mise_clear_completions to put the saved set back on the way out. So an
#     install that runs once is displaced by the first `cd`, which is why this
#     reinstates itself instead.
#
# Defined here rather than in 30-interactive.fish so that this handler is
# registered after `mise activate`'s, and therefore runs after it on the same
# event, with the last word on what `complete -c fnox` holds.

function __fnox_install_completions --on-event fish_prompt \
        --description "Keep fnox's completions ahead of the stub mise reinstalls"
    set -l rules (complete -c fnox)

    # Nothing to do only when ours are present and mise's stub is not: leaving
    # the stub alongside them would put fish's filename fallback back into the
    # candidate list, which is the whole thing being fixed.
    if string match -q '*__fnox_after_dashdash*' -- $rules
        and not string match -q '*__mise_load_fnox*' -- $rules
        return 0
    end

    complete -c fnox -e

    # `-f` on both: candidates come from these functions, never from fish's
    # filename fallback. The generated completion emits its own path candidates
    # when fnox says paths belong.
    complete -c fnox -f -n 'not __fnox_after_dashdash' -a '(__fnox_usage_complete)'
    complete -c fnox -f -n __fnox_after_dashdash -a '(__fnox_complete_passthrough)'
end
