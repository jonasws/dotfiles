set -x LC_ALL en_US.UTF-8

function __fish_describe_command; end

source $HOME/dotfiles/fish/local.fish


# To now slow down Emacs searching/projectile magic while on macOS
if not builtin status is-interactive
    exit
end

starship init fish | source

functions --erase fish_starship_prompt
functions --copy fish_prompt fish_starship_prompt

function fish_prompt
    set gproxyProcess (ps -u root | rg "ssh -f -nNT gitproxy")
    if test -n "$gproxyProcess"
        set gproxyStatusIcon  "📡"
    else
        set gproxyStatusIcon "⛔"
    end

    # Fun with flags
    fish_starship_prompt | \
      perl -p -e "
        s/❯/$gproxyStatusIcon ❯/;    \
        s/\(?eu-west-1\)?/ 🇮🇪 /;    \
        s/\(?eu-central-1\)?/ 🇩🇪 /; \
        s/\(?eu-north-1\)?/ 🇸🇪 /"
end

function hybrid_bindings --description "Vi-style bindings that inherit emacs-style bindings in all modes"
    for mode in default insert visual
        fish_default_key_bindings -M $mode
    end
    fish_vi_key_bindings --no-erase
end

set -g fish_key_bindings hybrid_bindings

set fish_color_command yellow
set fish_color_autosuggestion white

# Vim duh
set -x EDITOR vim

# some git abbrs that were missing atm
abbr gsw "git switch"


abbr gpsup "git push -u origin (git rev-parse --abbrev-ref HEAD)"

abbr -a gupa "git pull --rebase --autostash"
abbr -a gsm "git switch master"

alias bussen_hjem "entur_oracle departures NSR:Quay:7169"

alias git hub

abbr - "cd -"


function repo-name
    basename (git rev-parse --show-toplevel)
end

function current-branch
    git rev-parse --abbrev-ref HEAD
end


alias gproxy "sudo ssh -f -nNT gitproxy 2> /dev/null && echo \"Successfully connected with gproxy 😎\""
alias gproxy-status "sudo ssh -O check gitproxy"
alias gproxy-off "sudo ssh -O exit gitproxy"

alias reload-fish-config "source ~/.config/fish/config.fish && echo \"Fish config reloaded 🐟🚀\""

function __aada_profile_completion
    rg "\[profile (.*?)\]" $HOME/.aws/config -Nor "\$1"
end

function assume-aws-role
    set profile $argv[1]
    aada login --profile $profile \
      && set -gx AWS_PROFILE $profile \
      ;  set -gx AWS_DEFAULT_REGION eu-west-1
end

function get-lb-dns
    aws elbv2  describe-load-balancers --names $argv[1] --query "LoadBalancers[0].DNSName" | xargs dig +short
end

complete -f -c assume-aws-role -a "(__aada_profile_completion)"

alias assume assume-aws-role


set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

set -x PATH (dirname (nvm which node)) (dirname (pyenv which python)) /usr/local/opt/git/share/git-core/contrib/diff-highlight ~/.local/bin $PATH
set -x BD_OPT 'insensitive'

set -U FZF_DEFAULT_COMMAND "fd --type f"
set -U FZF_FIND_FILE_COMMAND "fd --type f . \$dir"
set -U FZF_OPEN_COMMAND "fd --type f . \$dir"

set -U FZF_PREVIEW_FILE_CMD "bat --plain --color=always --line-range :10"
set -U FZF_ENABLE_OPEN_PREVIEW 1
set -U FZF_LEGACY_KEYBINDINGS 0

alias fp 'fzf --preview="bat {} --color=always" --print0 | xargs -0 bat'
alias fpd 'fzf --preview="bat {} --color=always" --preview-window down --print0 | xargs -0 | xargs bat'


set -g fish_user_paths "/usr/local/sbin" $fish_user_paths


set -x RIPGREP_CONFIG_PATH $HOME/.config/ripgrep/rc

# Exa is cooler than ls, duh
alias ll "exa --long --git"
alias l "exa --long --git"
alias la "exa --long --all"
alias tree "exa --tree"

# Tig aliases
alias t tig
alias tst "tig status"

alias code code-insiders
alias vsc "code ."

pyenv init - | source

function jq
    if isatty stdout
        # Because bat, duh
        command jq $argv | bat --plain --language json
    else
        command jq $argv
    end
end

function http
    if isatty stdout
        command http  --check-status --pretty all $argv | bat --plain
    else
        command http $argv
    end
end

function fish_title_once
    echo -ne "\033]0;$argv[1]\a"
end

function bootLocal
    set port $argv[1]
    if test -z $port
        set port 8080

    end

    set jvmArgs "-Dspring.profiles.active=local -Dserver.port=$port"

    set appName (repo-name)
    fish_title_once "🥾 $appName $port"

    mvn spring-boot:run -Dspring-boot.run.jvmArguments="$jvmArgs"
end



complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'
