function fish_user_key_bindings --description "Custom key bindings"
    bind -M insert ctrl-alt-l clear-screen
    bind -M visual ctrl-alt-l clear-screen
    bind --erase --preset -M insert ctrl-l
    bind --erase --preset ctrl-l
    bind -M insert ctrl-p up-or-search
    bind -M insert ctrl-n down-or-search
end