set -x LC_ALL en_US.UTF-8
set -gx PATH /opt/homebrew/opt/gnu-tar/libexec/gnubin ~/.local/bin /opt/homebrew/bin $PATH

fish_config theme choose "Dracula Official"

function __fish_describe_command
end

function repo-name
    basename (git rev-parse --show-toplevel)

end
alias grt "cd (git rev-parse --show-toplevel)"

# To not slow down Emacs searching/projectile magic while on macOS
if not builtin status is-interactive
    exit
end

test -f $HOME/dotfiles/fish/local.fish; and source $HOME/dotfiles/fish/local.fish

starship init fish | source

functions --erase fish_starship_prompt
functions --copy fish_prompt fish_starship_prompt


function fish_prompt
    # Fun with flags
    fish_starship_prompt | perl -p -e "
        s/\(eu-west-1\)/ 🇮🇪 /;    \
        s/\(eu-central-1\)/ 🇩🇪 /; \
        s/\(eu-north-1\)/ 🇸🇪 /"
end

fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el

set -g fish_key_bindings fish_hybrid_key_bindings

function fish_user_key_bindings
    bind \ec fzf_cd_directory
    bind -M insert \ec fzf_cd_directory
end


set fish_color_command yellow
set fish_color_autosuggestion white

set -x EDITOR nvim
set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"


abbr -a - "cd -"

alias reload-fish-config "source ~/.config/fish/config.fish; and echo \"Fish config reloaded 🐟 🚀\""
alias as-tree "command tree --fromfile"
alias bg batgrep

function browse-ssm-params
    aws ssm describe-parameter --output=json \
        | jq -r ".Parameters[].Name" \
        | fzf
end

alias man batman

function git-dir-or-pwd
    git rev-parse --show-toplevel 2>/dev/null; or pwd
end

set -x BD_OPT insensitive

set -gx FZF_DEFAULT_COMMAND "fd --type f"
set -gx FZF_CTRL_T_COMMAND "fd --type f"
set -gx FZF_OPEN_COMMAND "fd --type f . \$dir"

set -gx FZF_ENABLE_OPEN_PREVIEW 1
set -gx FZF_LEGACY_KEYBINDINGS 0
set -gx FZF_COMPLETE 2

set -gx FZF_CTRL_T_OPTS "
  --preview 'bat -n --color=always {}'
"

set -gx FZF_ALT_C_OPTS "
   --preview 'eza -l --color=always {}'
"


set -gx EZA_COLORS "\
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

# Tig aliases
abbr -a t tig
alias tst "tig status"

# Git alises
abbr -a gsm "git switch master"


abbr -a tf terraform


alias spin tspin

function lambdalogs
    awslogs groups -p /aws/lambda | grep -v suat | fzf -1 -d / --with-nth 4 \
        --bind "ctrl-w:execute(awslogs get {} ALL $argv --watch | tspin),enter:execute(awslogs get {} ALL $argv | tspin)+abort"
end

function test-one
    set testName (fd --type f -e java "" src/test | fzf | xargs -J {} basename {} .java)

    if test -n "$testName"
        commandline "mvn test -Dtest=$testName"
    end
end

function findpass
    set entry (op list items \
        | jq -r ".[] | [.uuid, .overview.url, .overview.title] | @tsv" \
        | fzf)

    set name (printf $entry | cut -f 3)
    set uuid (printf $entry | cut -f 1)

    op get item $uuid \
        | jq -r '.details.fields[] | select(.designation=="password").value' \
        | pbcopy

    echo "Copied password for entry" $name "to clipbaord"
end

# Runs npm start if possible
function s
    if test -f package.json
        if test -f yarn.lock
            command yarn start $argv
        else
            command npm start $argv
        end
    else
        echo "No package.json found"
    end
end

function up
    if test -f docker-compose.yml
        command docker-compose up $argv
    else
        echo "No docker-compose.yml found"
    end
end

zoxide init fish | source

alias fishconfig "nvim ~/dotfiles/fish/config.fish; and reload-fish-config"

alias lg lazygit

abbr -a gp!! "git push --force"


set -gx PATH ~/.local/bin $PATH

# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

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


function check-commits
    git fetch upstream
    ./gradlew -p (git rev-parse --show-toplevel)/frontline-apis toolkits:verifyCommits --source-branch=(git rev-parse HEAD) --target-branch=upstream/master
end


function nittedal
    set -l query '
    query GetDepartures{
      quay(
        id: "NSR:Quay:550"
      ) {
        name
        estimatedCalls(
          timeRange: 7200,
          numberOfDepartures: 10,
          whiteListed: {
            lines: ["GJB:Line:R30", "GJB:Line:L3"]
          }
        ) {
          aimedDepartureTime
          expectedDepartureTime
          destinationDisplay {
            frontText
          }
        }
      }
    }
  '

    http POST https://api.entur.io/journey-planner/v3/graphql query=$query "ET-Client-Name: jonas-laptop-cli" \
        | jq -r '
            .data.quay.estimatedCalls[] 
            | [.expectedDepartureTime, .destinationDisplay.frontText]
            | @tsv' \
        # Only show the time, including display Norwegian characters
        | perl -Mutf8 -CS -ne 'print "\e[34m$2\e[0m\t\e[32m$3\e[0m\n"
              if /(\d{4}-\d{2}-\d{2}T)(\d{2}:\d{2}):\d{2}\+\d{2}:\d{2}\s+(\p{L}+)/'
end

set -gx DOCKER_HOST "unix://$HOME/.colima/default/docker.sock"
# Use fnm
# NOTE: Try to keep  this at the bottom of  the file, to ensure fnm appears at "front" of the PATH variable
fnm env --use-on-cd --corepack-enabled | source
direnv hook fish | source
thefuck --alias | source

batpipe | source
set -gx FX_THEME 2
set -gx BATDIFF_USE_DELTA true
alias man batman

set -gx GLAMOUR_STYLE dracula
set -gx PAGER less

# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true
