set -x LC_ALL en_US.UTF-8
set -x PATH /Users/jonasws/.local/bin /etc/profiles/per-user/jonasws/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin /Applications/WezTerm.app/Contents/MacOS /usr/local/bin /System/Cryptexes/App/usr/bin /usr/bin /bin /usr/sbin /sbin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin $PATH

/opt/homebrew/bin/brew shellenv fish | source

set -x XDG_CONFIG_HOME "$HOME/.config"

# set -x TESCONTAINERS_DOCKER_SOCKET_OVERRIDE /var/run/docker.sock
# set -x TESTCONTAINERS_HOST_OVERRIDE 192.168.64.6

fish_config theme choose "Catppuccin Mocha"
#
#
#set -l white f8f8f2
#set -l orange ffb86c
#set -l green 50fa7b
#set -l blue 6272a4
#set -l draculaBg 282a36
#
#
#set -U tide_mise_java_color $draculaBg
#set -U tide_mise_java_bg_color $orange
#
#set -U tide_pwd_color_anchors $white
#set -U tide_pwd_color_dirs $white
#set -U tide_pwd_color_truncated_dirs $white
#set -U tide_pwd_bg_color $blue
#
#set -U tide_time_color $draculaBg
#
#set -U tide_git_color $draculaBg
#set -U tide_git_bg_color $green
#set -U tide_git_color_branch $draculaBg
#set -U tide_git_bg_color_unstable $orange
#set -U tide_git_color_upsream $draculaBg
#set -U tide_git_color_untracked $draculaBg
#set -U tide_git_color_stash $draculaBg
#set -U tide_git_color_staged $draculaBg
#set -U tide_git_color_operation $draculaBg
#set -U tide_git_color_dirty $draculaBg
#set -U tide_git_color_conflicted $draculaBg
#set -U tide_git_color_branch $draculaBg
#
#set -U tide_aws_color $draculaBg
#set -U tide_aws_bg_color $white
#
#set -U tide_time_color $draculaBg
#set -U tide_time_bg_color $white
#
#set -U tide_character_color 50fa7b
#set -U tide_character_color_failure ff5555
#
#set -U tide_right_prompt_items status cmd_duration context jobs node python rustc pulumi go terraform nix_shell time aws mise_java
#
# tide configure --auto --style=Rainbow --prompt_colors='True color' --show_time='24-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines, character' --prompt_connection=Disconnected --powerline_right_prompt_frame=No --prompt_spacing=Sparse --icons='Few icons' --transient=No
#
set -x LS_COLORS (vivid generate catppuccin-mocha)

alias grt "cd (git rev-parse --show-toplevel)"
alias top btop
alias tw "tw --theme catppuccin"

fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el

function fish_user_key_bindings
    bind -M insert ctrl-alt-l clear-screen
    bind -M visual ctrl-alt-l clear-screen
    bind --erase --preset -M insert ctrl-l
    bind --erase --preset ctrl-l
end
# set fish_key_bindings fish_hybrid_key_bindings
set fish_key_bindings fish_vi_key_bindings

set -x VISUAL nvim
set -x EDITOR nvim

# # Maven 1password integration goodies
# function mvn
#     if isatty stdout
#         op run -- mvn --color=always $argv
#     else
#         op run -- mvn $argv
#     end
# end

alias vim nvim
alias c clear
alias http xh
alias n nvim
alias dadbod "nvim -c DBUI"
alias sg ast-grep

abbr -a mcv "mvn clean spotless:apply verify"

abbr -a - "cd -"
abbr -a gsma "git switch main"

alias as-tree "command tree --fromfile"
alias bg batgrep

alias zp zed-preview

set -x BD_OPT insensitive

set fzf_preview_dir_cmd eza --all --color=always

set -x RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# Eza is cooler than ls, duh
alias ll "eza --long --icons"
alias l "eza --long --icons"
alias la "eza --long --all --icons"

alias tree "eza --tree --long"

abbr -a dc docker-compose

# Git alises
abbr -a gsm "git switch master"

abbr -a tf terraform

# alias lazygit "TERM=xterm-256color command lazygit"
alias lzd lazydocker
alias lg lazygit
alias lgl "lazygit log"
alias lgs "lazygit status"

abbr -a gp!! "git push --force"

# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

set fzf_history_opts --with-nth="4.." --preview-window="down,30%,border-top,wrap"

function nittedal
    set -l query '
query GetDepartures($stopPlace: String!, $lines: [ID!]!, $timeRange: Int = 86400, $numberOfDepartures: Int = 5, $startTime: DateTime) {
  stopPlace(id: $stopPlace) {
    estimatedCalls(timeRange: $timeRange, numberOfDepartures: $numberOfDepartures, startTime: $startTime, whiteListed: {
            lines: $lines,
    }) {
      expectedDepartureTime
      situations {
      	summary {
      	  language
          value
        }
      }
      serviceJourney {
        journeyPattern {
          quays  {
            name
          }
        }
        line {
          publicCode
        }
      }
      destinationDisplay {
        frontText
      }

      quay {
        publicCode
        stopPlace {
            name
            description
        }
      }
    }
  }
}
    '
    set -l numberOfDepartures $argv[1]
    if test -n "$argv[1]"
        set -f numberOfDepartures $argv[1]
    else
        set -f numberOfDepartures 5
    end

    if test -n "$argv[2]"
        set -l parsedTime (string split : $argv[2])
        set -f startTime (/bin/date -Iminutes -v$parsedTime[1]H -v$parsedTime[2]M)
    else
        set -f startTime (/bin/date -Iminutes)
    end

    set -l variables (jq -r -n --arg numberOfDepartures $numberOfDepartures --arg startTime $startTime '
    {
        stopPlace: "NSR:StopPlace:59872",
        lines: ["VYG:Line:RE30", "VYG:Line:R31"],
        numberOfDepartures: $numberOfDepartures | tonumber,
        startTime: $startTime
    } | @json')

    http --ignore-stdin POST https://api.entur.io/journey-planner/v3/graphql variables:=$variables query=$query "ET-Client-Name: jonas-laptop-cli" \
        | jq -c -r '
            .data.stopPlace.estimatedCalls[]
            | select(.serviceJourney.journeyPattern.quays[] | select(.name == "Nittedal stasjon"))
            | [.expectedDepartureTime, .destinationDisplay.frontText, .quay.publicCode, .serviceJourney.line.publicCode, ([.quay.stopPlace.name, .quay.stopPlace.description] | join(" - ")), .situations[0].summary[0].value]
            | @tsv' \
        # Only show the time, including display Norwegian characters
        | perl -Mutf8 -CS -ne 'print "\e[34m$2\e[0m\t\e[96m$3\e[0m\t\e[92m$4\e[0m\t\e[95m$5\e[0m\t\e[93m$6\e[0m\t$7\n"
              if /(\d{4}-\d{2}-\d{2}T)(\d{2}:\d{2}):\d{2}\+\d{2}:\d{2}\t(\p{L}+)\t(\d+)?\t(.+)\t(.+)\t(.*)/' \
        | column -t -s (echo -n \t)
end

# The following will enable colors when using batpipe with less:
set -x FX_THEME 1
set -x FX_SHOW_SIZE true
set -x BATDIFF_USE_DELTA true
set -x BAT_THEME "Catppuccin Mocha"
set fzf_diff_highlighter delta --paging=never --width=20

set -x GLAMOUR_STYLE "$HOME/catppuccin/glamour/themes/catppuccin-mocha.json"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
# set -x AWS_DEFAULT_REGION eu-west-1
#set -x AWS_CLI_AUTO_PROMPT on-partial
#set -x AWS_VAULT_FILE_PASSPHRASE "op://Employee/aws-vault password/password"
#set -x AWS_VAULT_OTP "op://Employee/AWS - Capra Auth/one-time password"
#set -x AWS_VAULT_BACKEND file
#
#
#
#
#
function console -a profile destination
    set -l color (aws configure get color --profile $profile)
    set -l service $destination
    if test -z $service
        set service ecs/v2
    end
    set -l loginUrl (rain console --profile $profile --service $service --url)
    firefox-container --$color --name $profile $loginUrl
end

set -l awsProfiles cnops-build-admin cnops-dev-admin cnops-staging-admin cnops-prod-admin trafficinfo-service trafficinfo-dev trafficinfo-test trafficinfo-stage trafficinfo-prod trafficinfo-prod--admin
complete -c console -x -n "not __fish_seen_subcommand_from $awsProfiles" -a "$awsProfiles"
complete -c console -x -n "__fish_seen_subcommand_from $awsProfiles" -a 'ecs/v2 cloudwatch codepipeline cloudformation events secretsmanager ec2 vpc s3 states'

function changeAwsProfileBackground -v AWS_PROFILE
    if test -z $AWS_PROFILE
        printf "\033]111\007"
    else
        # Define colors for different AWS profiles
        switch "$AWS_PROFILE"
            case cnops-prod-admin
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case cnops-prod-developer
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case trafficinfo-prod--admin
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case cnops-prod-developer
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case default '*'
                set bg_color "#1E1E2E" # Default Mocha background
        end

        # Emit ANSI escape sequence to set the background color
        printf "\033]11;%s\007" $bg_color
    end
end

function gcal --wraps=gcalcli
    set -x GCALCLI_CONFIG $XDG_CONFIG_HOME/gcalcli/config.toml
    set -x COLUMNS (tput cols)
    gcalcli --client-id=(op read "op://Employee/gcalcli/username") --client-secret=(op read "op://Employee/gcalcli/credential") \
        $argv | less -S -F -r
end

function view-ci
    set -l projectName (basename (pwd))
    set -l rev (git rev-parse HEAD)
    set -l runId (gh run list --commit $rev --json databaseId -q .[0].databaseId)
    gh run watch $runId; and notify "CI finished" "CI finished for $projectName"
end

function mvn --wraps=mvn
    # Check if -f (file) or --file is passed to mvn
    if not contains -- -f $argv; and not contains -- --file $argv
        # Look for the Git root directory
        set -l git_root (command git rev-parse --show-toplevel 2>/dev/null)

        if test -n "$git_root"
            # If Git root is found, construct the path to pom.xml
            set -l pom_path "$git_root/pom.xml"

            # Check if pom.xml exists at the Git root
            if test -f "$pom_path"
                echo "Using pom.xml from Git root: $pom_path"
                command mvn -f "$pom_path" $argv
                return $status
            else
                echo "Warning: pom.xml not found in Git root ($git_root). Aborting"
            end
        else
            echo "Warning: Not in a Git repository. Running mvn without -f."
        end
    end

    # If -f was passed, or if no Git root/pom.xml was found, run mvn directly
    command mvn $argv
end

function mvnu --wraps=mvn
    mvn -Dspotless.check.skip -DskipTests $argv
end

function notify -a title body
    printf "\e]777;notify;%s;%s\e\\" $title $body
end

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        cd "$cwd"
    end
    rm -f -- "$tmp"
end

# function grc.wrap --argument-names executable
#     set executable $argv[1]
#
#     if test (count $argv) -gt 1
#         set arguments $argv[2..(count $argv)]
#     else
#         set arguments
#     end
#
#     set optionsvariable "grcplugin_"$executable
#     set options $$optionsvariable
#
#     command grc -es --colour=auto --pty $executable $options $arguments
# end

#eval (zellij setup --generate-auto-start fish | string collect)
batman --export-env | source
starship init fish | source
# atuin init fish | source

zoxide init fish | source
mise activate fish | source
source ~/.config/op/plugins.sh

function aws --wraps=aws
    # Store original arguments before argparse modifies them
    set -l original_argv $argv
    
    # Parse known AWS CLI arguments we care about
    argparse --ignore-unknown 'output=' -- $argv
    or return
    
    set -l output_format json
    set -l use_pager true
    set -l bat_lang json
    
    # Check if --output was specified
    if set -q _flag_output
        set output_format $_flag_output
    end

    # Determine pager usage and bat language based on output format
    switch $output_format
        case table
            set use_pager false
        case yaml yaml-stream
            set bat_lang yaml
        case text
            set bat_lang txt
        case json
            set bat_lang json
    end

    if test $use_pager = true; and isatty stdout
        command aws $original_argv | bat --language=$bat_lang --style=plain
    else
        command aws $original_argv
    end
end
