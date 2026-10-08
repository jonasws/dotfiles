function __fnox_usage_complete \
        --description "fnox's own generated completion, loaded on first use"
    if not functions -q __usage_complete_fnox
        # Drop the generated script's own `complete -c 'fnox' ...` line and keep
        # the function it defines. Registration belongs to
        # conf.d/40-fnox-completion.fish, which splits it against the
        # passthrough; letting the script register unconditionally would put an
        # unguarded third completion back on top of both.
        command fnox completion fish | string match -rv "^complete -c 'fnox'" | source
    end
    __usage_complete_fnox
end
