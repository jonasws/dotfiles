set -x LC_ALL en_US.UTF-8

function __fish_describe_command
end

function repo-name
    basename (git rev-parse --show-toplevel)
end

alias grt "cd (git rev-parse --show-toplevel)"

set -x PATH ~/.emacs.d/bin $HOME/.cargo/bin /opt/homebrew/bin $PATH

# To not slow down Emacs searching/projectile magic while on macOS
if not builtin status is-interactive
    exit
end

test -f $HOME/dotfiles/fish/local.fish; and source $HOME/dotfiles/fish/local.fish

starship init fish | source

# Just for it not to hang. Remove when we don't use this repo on this system anymore
git -C ~/sparkel-cdk-app/ fsmonitor--daemon start 2&>/dev/null; or echo "already running fsmonitor in sparkel-cdk-app"

functions --erase fish_starship_prompt
functions --copy fish_prompt fish_starship_prompt

function fish_prompt
    # Fun with flags
    fish_starship_prompt | perl -p -e "
        s/\(eu-west-1\)/ 🇮🇪 /;    \
        s/\(eu-central-1\)/ 🇩🇪 /; \
        s/\(eu-north-1\)/ 🇸🇪 /"
end

function fish_custom_key_bindings
    fish_hybrid_key_bindings
    fzf_key_bindings
    bind \ec fzf-git-aware-cd-widget
    bind -M insert \ec fzf-git-aware-cd-widget
end

set -g fish_key_bindings fish_custom_key_bindings

set fish_color_command yellow
set fish_color_autosuggestion white

# Vim duh
set -x EDITOR nvim
# set -x EDITOR "emacsclient --alternate-editor vim"

abbr -a delete-merged "git branch --merged | grep -v master | grep -v main | grep -v (git branch --show-current) | xargs git branch -d"

abbr -a gsw "git switch"


abbr -a gpsup "git push -u origin (git branch --show-current)"

abbr -a gupa "git pull --rebase --autostash"
abbr -a gsm "git switch master"
abbr -a gsma "git switch main"
abbr -a gpf "git push --force-with-lease"

git config --global alias.newest-tag "describe --abbrev=0"

abbr -a - "cd -"

alias reload-fish-config "source ~/.config/fish/config.fish; and echo \"Fish config reloaded 🐟 🚀\""

function browse-ssm-params
    aws ssm describe-parameters --output=json \
        | jq -r ".Parameters[].Name" \
        | fzf
end

alias man batman

function git-dir-or-pwd
    git rev-parse --show-toplevel 2>/dev/null; or pwd
end


#set -x GOPATH $HOME/.go
# set -x GOROOT (brew --prefix golang)/libexec
set -x PATH /usr/local/opt/git/share/git-core/contrib/diff-highlight ~/.local/bin $PATH


set -x BD_OPT insensitive

set -U FZF_DEFAULT_COMMAND "fd --type f"
set -U FZF_CTRL_T_COMMAND "fd --type f"
set -U FZF_OPEN_COMMAND "fd --type f . \$dir"
set -U FZF_PREVIEW_DIR_CMD exa

set -U FZF_PREVIEW_FILE_CMD "bat --plain --color=always --line-range :10"
set -U FZF_ENABLE_OPEN_PREVIEW 1
set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_COMPLETE 2

alias fp 'fzf --preview="bat {} --color=always" --print0 | xargs -0 bat'
alias fpd 'fzf --preview="bat {} --color=always" --preview-window down --print0 | xargs -0 | xargs bat'


# This makes the fzf cd widget start from the git root if you're in a git repo
function fzf-git-aware-cd-widget -d "Change directory (git root aware)"
    set -l commandline (__fzf_parse_commandline)
    set -l dir (git-dir-or-pwd)
    echo $dir
    set -l fzf_query $commandline[2]
    set -l prefix $commandline[3]

    test -n "$FZF_TMUX_HEIGHT"; or set FZF_TMUX_HEIGHT 40%
    begin
        set -lx FZF_DEFAULT_OPTS "--height $FZF_TMUX_HEIGHT --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS $FZF_ALT_C_OPTS"
        eval "fd --type d --base-directory $dir | "(__fzfcmd)' +m --query "'$fzf_query'"' | read -l result

        if [ -n "$result" ]
            cd -- $dir/$result

            # Remove last token from commandline.
            commandline -t ""
            commandline -it -- $prefix
        end
    end

    commandline -f repaint
end


set -x RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# Exa is cooler than ls, duh
alias ll "exa --long --git"
alias l "exa --long --git"
alias la "exa --long --all"

abbr -a dc "docker compose"

# Calendar
alias month="gcal --starting-day=1"

# Tig aliases
abbr -a t tig
alias tst "tig status"


abbr -a tf terraform

# pyenv init --path | source

function jq
    if isatty stdout
        command jq -C $argv | less -RXF
    else
        command jq $argv
    end
end

function http
    if isatty stdout; and not contains -- --download $argv; and not contains -- -d $argv
        command http --pretty=all --print=hb $argv | less -RXF
    else
        command http $argv
    end
end

function rg
    if isatty stdout
        command rg -p $argv | less -RXF
    else
        command rg $argv
    end
end


function awslogs
    if isatty stdout
        if contains -- -w $argv or contains -- --watch $argv
            command awslogs $argv --color=always | bat --plain --language log --paging=never
        else
            command awslogs $argv --color=always | bat --plain --language log
        end
    else
        command awslogs $argv
    end
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

# complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'


# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/__tabtab.fish ]; and . ~/.config/tabtab/__tabtab.fish; or true

function switch_terraform --on-event fish_postexec
    string match --regex '^cd\s' "$argv" >/dev/null
    set --local is_command_cd $status

    if test $is_command_cd -eq 0
        if count *.tf >/dev/null

            grep -c required_version *.tf >/dev/null
            set --local tf_contains_version $status

            if test $tf_contains_version -eq 0
                command tfswitch
            end
        end
    end
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

# jenv init - | source

function get-repo-name
    gh repo view --json nameWithOwner --jq .nameWithOwner | string trim
end


function get-branch-codespace
    set repoName (get-repo-name)
    set branch (git rev-parse --abbrev-ref HEAD)
    gh codespace list --json name,repository,gitStatus --jq (printf '.[] | select(.repository == "%s" and .gitStatus.ref == "%s") | .name' $repoName $branch)
end

function tre
    command tre $argv -e; and source /tmp/tre_aliases_$USER ^/dev/null
end

zoxide init fish | source

# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

# pnpm
set -gx PNPM_HOME /Users/jonasws/Library/pnpm
set -gx PATH "$PNPM_HOME" $PATH
# pnpm end

alias fishconfig "nvim ~/dotfiles/fish/config.fish; and reload-fish-config"
# Add gnutar to front of path
set -gx PATH /opt/homebrew/opt/gnu-tar/libexec/gnubin $PATH

set -gx DOCKER_DEFAULT_PLATFORM linux/amd64

alias lg lazygit
test -e {$HOME}/.iterm2_shell_integration.fish; and source {$HOME}/.iterm2_shell_integration.fish

set -gx PATH /Users/jonasws/Library/Caches/fnm_multishells/27328_1681738441313/bin $PATH
set -gx FNM_DIR "/Users/jonasws/Library/Application Support/fnm"
set -gx FNM_VERSION_FILE_STRATEGY local
set -gx FNM_MULTISHELL_PATH /Users/jonasws/Library/Caches/fnm_multishells/27328_1681738441313
set -gx FNM_LOGLEVEL info
set -gx FNM_NODE_DIST_MIRROR "https://nodejs.org/dist"
set -gx FNM_ARCH arm64
function _fnm_autoload_hook --on-variable PWD --description 'Change Node version on directory change'
    status --is-command-substitution; and return
    if test -f .node-version -o -f .nvmrc
        fnm use --log-level=quiet
    end

end


_fnm_autoload_hook
