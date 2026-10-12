function fish_user_key_bindings --description "Custom key bindings"
    bind -M insert ctrl-alt-l clear-screen
    bind -M visual ctrl-alt-l clear-screen
    bind --erase --preset -M insert ctrl-l
    bind --erase --preset ctrl-l
    bind -M insert ctrl-p up-or-search
    bind -M insert ctrl-n down-or-search

    # Here rather than in conf.d: fzf.fish's conf.d loads later and rebinds
    # ctrl-r to its own history search.
    if functions -q _atuin_search
        bind ctrl-r _atuin_search
        bind -M insert ctrl-r _atuin_search
    end
end