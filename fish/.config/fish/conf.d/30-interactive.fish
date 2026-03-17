# Interactive-only configurations
if status is-interactive
    # Homebrew setup
    if test -x /opt/homebrew/bin/brew
        /opt/homebrew/bin/brew shellenv fish | source
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

    if command -q mise
        mise activate fish | source
    end

    # 1Password plugins
    if test -f ~/.config/op/plugins.sh
        source ~/.config/op/plugins.sh
    end

    alias claude='CLAUDE_SESSION=1 GH_TOKEN=$(op read "op://Employee/Liflig Github PAT/token") command claude'

end
