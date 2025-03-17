set -x LC_ALL en_US.UTF-8
set -x PATH /Users/jonasws/.local/bin /Users/jonasws/.nix-profile/bin /etc/profiles/per-user/jonasws/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin /opt/whalebrew/bin /opt/homebrew/bin /opt/homebrew/opt/sphinx-doc/bin /Users/jonasws/.emacs.d/bin /opt/homebrew/opt/libiconv/bin /opt/homebrew/sbin /opt/homebrew/opt/sqlite/bin /opt/homebrew/opt/make/libexec/gnubin /Applications/WezTerm.app/Contents/MacOS /opt/homebrew/opt/jpeg/bin /opt/homebrew/opt/fzf/bin /usr/local/bin /System/Cryptexes/App/usr/bin /usr/bin /bin /usr/sbin /sbin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin $PATH

/opt/homebrew/bin/brew shellenv | source

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

fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el

function fish_user_key_bindings
    bind --preset ctrl-alt-l clear-screen
    bind --preset -M insert ctrl-alt-l clear-screen
    bind --preset -M visual ctrl-alt-l clear-screen
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
alias http xh
alias n nvim
abbr -a p pnpm

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

abbr -a dc "docker compose"

# Calendar
alias month="gcal --starting-day=1"

# Git alises
abbr -a gsm "git switch master"

abbr -a tf terraform

alias lzd lazydocker
alias lg lazygit

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

    set -l variables (jq -n --arg numberOfDepartures $numberOfDepartures --arg startTime $startTime '
    {
        stopPlace: "NSR:StopPlace:59872",
        lines: ["VYG:Line:RE30", "VYG:Line:R31"],
        numberOfDepartures: $numberOfDepartures | tonumber,
        startTime: $startTime
    } | @json')

    http --ignore-stdin POST https://api.entur.io/journey-planner/v3/graphql variables:=$variables query=$query "ET-Client-Name: jonas-laptop-cli" \
        | jq -r '
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
set fzf_diff_highlighter delta --paging=never --width=20

set -x GLAMOUR_STYLE dracula
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -x AWS_PAGER "bat --plain --language json"
# set -x AWS_DEFAULT_REGION eu-west-1
set -x AWS_DEFAULT_OUTPUT json
#set -x AWS_CLI_AUTO_PROMPT on-partial
set -x AWS_VAULT_FILE_PASSPHRASE "op://Employee/aws-vault password/password"
set -x AWS_VAULT_OTP "op://Employee/AWS - Capra Auth/one-time password"
set -x AWS_VAULT_BACKEND file

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if set cwd (command cat -- "$tmp"); and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

#eval (zellij setup --generate-auto-start fish | string collect)
batman --export-env | source
starship init fish | source

zoxide init fish | source
/opt/homebrew/bin/mise activate fish | source
source ~/.config/op/plugins.sh
