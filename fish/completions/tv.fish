# Fish completions for television (tv)

# Disable file completions for tv
complete -c tv -f

# Complete channel names for the first argument
complete -c tv -n __fish_is_first_token -a "dotfiles man-pages procs docker-images git-log git-diff git-branch dirs text fish-history aws-secrets git-repos files env nu-history"

# Complete commands
complete -c tv -n __fish_is_first_token -a list-channels -d "Lists the available channels"
complete -c tv -n __fish_is_first_token -a update-channels -d "Downloads the latest collection of default channel prototypes"

# Options
complete -c tv -l ui-scale -d "UI scale percentage"
complete -c tv -l no-preview -d "Disable preview panel"
complete -c tv -l no-status-bar -d "Disable status bar"
complete -c tv -l watch -d "Enable watch mode"
complete -c tv -l watch-interval -d "Watch interval in seconds"
complete -c tv -l input-text -d "Prefill the prompt with text"
complete -c tv -l input-header -d "Input header text"
complete -c tv -l input-prompt -d "Input prompt text"
complete -c tv -l preview-header -d "Preview header text"
complete -c tv -l preview-footer -d "Preview footer text"
complete -c tv -l source-command -d "Source command for ad-hoc channel"
complete -c tv -l source-display-template -d "Source display template"
complete -c tv -l source-output-template -d "Source output template"
complete -c tv -l preview-command -d "Preview command"
complete -c tv -l inline -d "Show the picker inline"
complete -c tv -l layout -d "Layout orientation" -xa "landscape portrait"
complete -c tv -l smart-channel -d "Guess channel from input prompt"
complete -c tv -l select-one -d "Auto-select if only one entry"
complete -c tv -l select-first -d "Take first entry after loading"
complete -c tv -l select-first-fuzzy -d "Take first fuzzy match"
complete -c tv -l single-channel -d "Run in single-channel mode"
complete -c tv -l no-help -d "Disable help panel"
complete -c tv -l preview-size -d "Preview panel size percentage"
complete -c tv -l global-history -d "Use global history across channels"
complete -c tv -s h -l help -d "Print help"
complete -c tv -s V -l version -d "Print version"
