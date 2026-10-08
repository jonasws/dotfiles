# Interactive-only configurations
if status is-interactive
    # Homebrew setup
    if test -x /opt/homebrew/bin/brew
        /opt/homebrew/bin/brew shellenv fish | source
    end

    if command -q mise
        mise activate fish | source
    end

    # Fish theme
    fish_config theme choose "Catppuccin Mocha"

    # FZF key bindings
    if functions -q fzf_configure_bindings
        fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el
    end

    # Ctrl-O: open current prompt in nvim
    for mode in default insert
        bind --mode $mode ctrl-o edit_command_buffer
    end

    # AWS completions
    complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

    set -x OP_ACCOUNT capragroup.1password.eu

    # Initialize external tools
    if command -q batman
        batman --export-env | source
    end

    if command -q starship
        starship init fish | source
    end

    if command -q zoxide
        zoxide init fish | source
    end

    # fnox: auto-load secrets as env vars per directory (prompt + cwd hooks)
    if command -q fnox
        fnox activate fish | source
    end

    if command -q tv
        tv init fish | source

        # All AWS profiles whose name starts with `cn`, matching the
        # aws-profiles television cable channel. Used to validate a --profile
        # token parsed off the command line before querying AWS with it.
        function __aws_cn_profiles
            awk -F'[][]' '/^\[profile cn/ {sub(/^profile /, "", $2); print $2}' \
                (test -n "$AWS_CONFIG_FILE"; and echo $AWS_CONFIG_FILE; or echo ~/.aws/config) 2>/dev/null
        end

        function tv_autocomplete_with_aws_profiles
            set -l current_prompt (commandline --current-process)

            # awslogs: if a valid --profile value is already on the line,
            # complete against that profile's log groups; otherwise fall
            # through to the profile picker below.
            if string match -qr '(^|\s)awslogs\s' -- $current_prompt
                set -l profile (string replace -rf '.*--profile[=\s]+(\S+).*' '$1' -- $current_prompt)
                if test -n "$profile"; and not string match -qr -- '[-]-profile\s*$' $current_prompt; and contains -- $profile (__aws_cn_profiles)
                    printf "\n"
                    # Current token is the partial log-group name being typed
                    # (empty after a trailing space). Prefill the picker with
                    # it for fuzzy filtering; fetch all groups so mid-string
                    # fragments still match (server-side -p is prefix-anchored).
                    set -l prefix (commandline -t)
                    set -l result (awslogs groups --profile $profile 2>/dev/null \
                        | tv --inline --no-status-bar -i "$prefix" \
                            --preview-command "$HOME/dotfiles/utils/aws-log-group-preview.sh $profile {}" \
                            --preview-header "last activity ($profile)")
                    if test -n "$result"
                        commandline -t -- $result' '
                    else
                        commandline -t -- ''
                    end
                    printf "\033[A"
                    commandline -f repaint
                    return
                end
            end

            if string match -qr '(^|\s)(aws|awslogs)\s.*--profile\s*$' -- $current_prompt; or string match -qr '(^|\s)console\s*$' -- $current_prompt
                printf "\n"
                set -l result (tv aws-profiles --inline --no-status-bar)
                if test -n "$result"
                    commandline -t -- $result' '
                else
                    commandline -t -- ''
                end
                printf "\033[A"
                commandline -f repaint
            else
                tv_smart_autocomplete
            end
        end

        for mode in default insert
            bind --mode $mode ctrl-t tv_autocomplete_with_aws_profiles
        end
    end

    # 1Password plugins
    if test -f ~/.config/op/plugins.sh
        source ~/.config/op/plugins.sh
    end

    # Fish completion for taws

    # Disable file completion by default
    complete -c taws -f

    # Dynamic profile completion
    complete -c taws -n "__fish_seen_subcommand_from -p --profile" -xa "(taws list-profiles 2>/dev/null)"
    complete -c taws -s p -l profile -d 'AWS profile to use' -xa "(taws list-profiles 2>/dev/null)"

    # Dynamic region completion  
    complete -c taws -n "__fish_seen_subcommand_from -r --region" -xa "(taws list-regions 2>/dev/null)"
    complete -c taws -s r -l region -d 'AWS region to use' -xa "(taws list-regions 2>/dev/null)"

    # Log level completion
    complete -c taws -l log-level -d 'Log level for debugging' -xa "off error warn info debug trace"

    # Other options
    complete -c taws -l readonly -d 'Run in read-only mode'
    complete -c taws -l endpoint-url -d 'Custom AWS endpoint URL'
    complete -c taws -s h -l help -d 'Print help'
    complete -c taws -s V -l version -d 'Print version'

    # Subcommands
    complete -c taws -n __fish_use_subcommand -a completion -d 'Generate shell completion scripts'
    complete -c taws -n __fish_use_subcommand -a help -d 'Print help for subcommand(s)'

    # Completion subcommand
    complete -c taws -n "__fish_seen_subcommand_from completion" -xa "bash zsh fish powershell elvish"

    herdr completion fish | source
end
