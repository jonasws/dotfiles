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

    # AWS completions
    complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

    # Console command completions
    complete -c console -x -n "not __fish_seen_subcommand_from (aws configure list-profiles)" \
        -a "(aws configure list-profiles | grep -E 'cnops|cargonet|trafficinfo')"
    complete -c console -x -n "__fish_seen_subcommand_from (aws configure list-profiles)" \
        -a 'ecs/v2 cloudwatch codepipeline cloudformation events secretsmanager ec2 vpc s3 states'

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

    if command -q tv
        tv init fish | source

        function tv_autocomplete_with_aws_profiles
            set -l current_prompt (commandline --current-process)
            if string match -qr '(^|\s)aws\s.*--profile\s*$' -- $current_prompt
                printf "\n"
                set -l result (tv aws-profiles --inline --no-status-bar)
                if test -n "$result"
                    commandline -t -- $result' '
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
end
