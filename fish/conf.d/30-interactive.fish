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
    set -l awsProfiles cnops-build-admin cnops-dev-admin cnops-staging-admin cnops-prod-admin trafficinfo-service trafficinfo-dev trafficinfo-test trafficinfo-stage trafficinfo-prod trafficinfo-prod--admin
    complete -c console -x -n "not __fish_seen_subcommand_from $awsProfiles" -a "$awsProfiles"
    complete -c console -x -n "__fish_seen_subcommand_from $awsProfiles" -a 'ecs/v2 cloudwatch codepipeline cloudformation events secretsmanager ec2 vpc s3 states'
    
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
    end
    
    if command -q mise
        mise activate fish | source
    end
    
    # 1Password plugins
    if test -f ~/.config/op/plugins.sh
        source ~/.config/op/plugins.sh
    end
end