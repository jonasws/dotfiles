set -x LC_ALL en_US.UTF-8
# set -x PATH ~/.cargo/bin /opt/homebrew/opt/grep/libexec/gnubin /opt/homebrew/opt/gnu-tar/libexec/gnubin ~/go/bin ~/.local/bin /opt/homebrew/bin $PATH
# set -x PATH ~/.local-fish/bin ~/.local-nvim/bin $PATH
set -x PATH /Users/jonasws/.local/bin /Users/jonasws/.nix-profile/bin /etc/profiles/per-user/jonasws/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin /opt/whalebrew/bin /opt/homebrew/bin /opt/homebrew/opt/sphinx-doc/bin /Users/jonasws/.emacs.d/bin /opt/homebrew/opt/libiconv/bin /opt/homebrew/sbin /opt/homebrew/opt/sqlite/bin /opt/homebrew/opt/make/libexec/gnubin /Applications/WezTerm.app/Contents/MacOS /opt/homebrew/opt/jpeg/bin /opt/homebrew/opt/fzf/bin /usr/local/bin /System/Cryptexes/App/usr/bin /usr/bin /bin /usr/sbin /sbin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin /var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin $PATH

set -x XDG_CONFIG_HOME "$HOME/.config"


# set -x TESCONTAINERS_DOCKER_SOCKET_OVERRIDE /var/run/docker.sock
# set -x TESTCONTAINERS_HOST_OVERRIDE 192.168.64.6

fish_config theme choose "Dracula Official"


set -l white f8f8f2
set -l orange ffb86c
set -l green 50fa7b
set -l blue 6272a4
set -l draculaBg 282a36


set -U tide_mise_java_color $draculaBg
set -U tide_mise_java_bg_color $orange

set -U tide_pwd_color_anchors $white
set -U tide_pwd_color_dirs $white
set -U tide_pwd_color_truncated_dirs $white
set -U tide_pwd_bg_color $blue

set -U tide_time_color $draculaBg

set -U tide_git_color $draculaBg
set -U tide_git_bg_color $green
set -U tide_git_color_branch $draculaBg
set -U tide_git_bg_color_unstable $orange
set -U tide_git_color_upsream $draculaBg
set -U tide_git_color_untracked $draculaBg
set -U tide_git_color_stash $draculaBg
set -U tide_git_color_staged $draculaBg
set -U tide_git_color_operation $draculaBg
set -U tide_git_color_dirty $draculaBg
set -U tide_git_color_conflicted $draculaBg
set -U tide_git_color_branch $draculaBg

set -U tide_aws_color $draculaBg
set -U tide_aws_bg_color $white

set -U tide_time_color $draculaBg
set -U tide_time_bg_color $white

set -U tide_character_color 50fa7b
set -U tide_character_color_failure ff5555

set -U tide_right_prompt_items status cmd_duration context jobs node python rustc pulumi go terraform nix_shell time aws mise_java

# tide configure --auto --style=Rainbow --prompt_colors='True color' --show_time='24-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines, character' --prompt_connection=Disconnected --powerline_right_prompt_frame=No --prompt_spacing=Sparse --icons='Few icons' --transient=No

alias grt "cd (git rev-parse --show-toplevel)"
alias top btop

fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el

# set fish_key_bindings fish_hybrid_key_bindings
set fish_key_bindings fish_vi_key_bindings

function fish_user_key_bindings
    bind --preset \ec fzf_cd_directory
    bind --preset -M insert \ec fzf_cd_directory
end


set fish_color_command yellow
set fish_color_autosuggestion white


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

abbr -a - "cd -"
abbr -a gsma "git switch main"

alias as-tree "command tree --fromfile"
alias bg batgrep

alias zp "zed-preview"

set -x BD_OPT insensitive

set -x FZF_DEFAULT_COMMAND "fd --type f"
set -x FZF_CTRL_T_COMMAND "fd --type f"
set -x FZF_OPEN_COMMAND "fd --type f . \$dir"

set -x FZF_ENABLE_OPEN_PREVIEW 1
set -x FZF_LEGACY_KEYBINDINGS 0
set -x FZF_COMPLETE 0

set -x FZF_CTRL_T_OPTS "
  --preview 'bat -n --color=always {}'
"

set -x FZF_ALT_C_OPTS "
   --preview 'eza -l --color=always {}'
"


set -x EZA_COLORS "\
gu=37:\
sn=32:\
sb=32:\
da=34:\
ur=34:\
uw=35:\
ux=36:\
ue=36:\
gr=34:\
gw=35:\
gx=36:\
tr=34:\
tw=35:\
tx=36:"


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

abbr -a lg lazygit
abbr -a lzd lazydocker

abbr -a gp!! "git push --force"


# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'


set fzf_history_opts --with-nth="4.." --preview-window="down,30%,border-top,wrap"

function fzf_cd_directory --description "Change directory Replace the current token with the selected file paths."
    # Inspired by https://github.com/PatrickF1/fzf.fish/blob/main/functions/_fzf_search_directory.fish
    # Directly use fd binary to avoid output buffering delay caused by a fd alias, if any.
    # Debian-based distros install fd as fdfind and the fd package is something else, so
    # check for fdfind first. Fall back to "fd" for a clear error message.
    set -f fd_cmd (command -v fdfind || command -v fd  || echo "fd")
    set -f --append fd_cmd --color=always $fzf_fd_opts

    set -f fzf_arguments --select-1 --preview='eza --all --color=always {}' --ansi $fzf_directory_opts
    set -f token (commandline --current-token)
    # expand any variables or leading tilde (~) in the token
    set -f expanded_token (eval echo -- $token)
    # unescape token because it's already quoted so backslashes will mess up the path
    set -f unescaped_exp_token (string unescape -- $expanded_token)

    # If the current token is a directory and has a trailing slash,
    # then use it as fd's base directory.
    if string match --quiet -- "*/" $unescaped_exp_token && test -d "$unescaped_exp_token"
        set --append fd_cmd --base-directory=$unescaped_exp_token
        # use the directory name as fzf's prompt to indicate the search is limited to that directory
        set --prepend fzf_arguments --prompt="Change Directory $unescaped_exp_token> " --preview="_fzf_preview_file $expanded_token{}"
        set -f dir_path_selected $unescaped_exp_token($fd_cmd --type d 2>/dev/null | _fzf_wrapper $fzf_arguments)
    else
        set --prepend fzf_arguments --prompt="Change Directory> " --query="$unescaped_exp_token" --preview='_fzf_preview_file {}'
        set -f dir_path_selected ($fd_cmd --type d 2>/dev/null | _fzf_wrapper $fzf_arguments)
    end


    if test $status -eq 0
        cd (string escape -- $dir_path_selected | string join ' ')
    end

    commandline --function repaint
end

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

    http --ignore-stdin POST https://api.entur.io/journey-planner/v3/graphql variables:=$variables query=$query "ET-Client-Name: jonas-laptop-cli"  \
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
set -x AWS_CLI_AUTO_PROMPT on-partial
set -x AWS_VAULT_FILE_PASSPHRASE "op://Employee/aws-vault password/password"
set -x AWS_VAULT_BACKEND file

if status --is-interactive
    batman --export-env | source

    zoxide init fish | source
    /opt/homebrew/bin/mise activate fish | source
    source ~/.config/op/plugins.sh
end
