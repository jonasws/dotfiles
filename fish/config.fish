set -x LC_ALL en_US.UTF-8

function __fish_describe_command; end

source $HOME/dotfiles/fish/local.fish

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

# some git abbrs that were missing atmw
abbr gsw "git switch"

abbr yi "yarn --ignore-engines"
abbr yt "yarn test"

alias bussen_hjem "entur_oracle departures NSR:Quay:7169"

alias git hub

abbr - "cd -"

abbr cb clipboard

abbr -a gupa "git pull --rebase --autostash"
abbr -a gcm "git checkout master"


function repo-name
    basename (git rev-parse --show-toplevel)
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

complete -f -c assume-aws-role -a "(__aada_profile_completion)"

alias assume assume-aws-role


set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

set -x PATH (dirname (nvm which node)) (dirname (pyenv which python)) /usr/local/opt/git/share/git-core/contrib/diff-highlight ~/.local/bin $PATH
set -x BD_OPT 'insensitive'

set -x FZF_DEFAULT_COMMAND 'fd --type f'
set -x FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"

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

alias fp 'fzf --preview="bat {} --color=always"'
alias fpd 'fzf --preview="bat {} --color=always" --preview-window down'

alias code code-insiders
alias vsc "code ."

pyenv init - | source

function rg
    if isatty stdout
        command rg -p $argv | less -RMFXK
    else
        command rg $argv
    end
end


function jq
    if isatty stdout
        # Because bat, duh
        command jq $argv | bat --language json
    else
        command jq $argv
    end
end

function http
    if isatty stdout
        command http --pretty all $argv | bat
    else
        command http $argv
    end
end

set -x FZF_DEFAULT_COMMAND 'fd --type f'
set -x FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -x FZF_ALT_C_COMMAND $FZF_DEFAULT_COMMAND


complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'
