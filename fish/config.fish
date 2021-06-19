set -x LC_ALL en_US.UTF-8

function __fish_describe_command; end

function repo-name
    basename (git rev-parse --show-toplevel)
end

alias grt "cd (git rev-parse --show-toplevel)"

set -x PATH ~/doom-emacs/bin /usr/local/bin $PATH

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
    fish_starship_prompt | \
      perl -p -e "
        s/\(eu-west-1\)/ 🇮🇪 /;    \
        s/\(eu-central-1\)/ 🇩🇪 /; \
        s/\(eu-north-1\)/ 🇸🇪 /"
end

set -g fish_key_bindings fish_hybrid_key_bindings

set fish_color_command yellow
set fish_color_autosuggestion white

# Vim duh
set -x EDITOR vim
# set -x EDITOR "emacsclient --alternate-editor vim"

alias top "vtop --theme nord"
alias oldtop "/usr/bin/top"

abbr -a delete-merged "git branch --merged | grep -v master | grep -v main | grep -v (git branch --show-current) | xargs git branch -d"

abbr -a gsw "git switch"


abbr -a gpsup "git push -u origin (git branch --show-current)"

abbr -a gupa "git pull --rebase --autostash"
abbr -a gsm "git switch master"
abbr -a gsma "git switch main"
abbr -a gpf "git push --force-with-lease"

alias git hub

git config --global alias.newest-tag "describe --abbrev=0"

abbr -a - "cd -"

alias reload-fish-config "source ~/.config/fish/config.fish; and echo \"Fish config reloaded 🐟 🚀\""

function browse-ssm-params
    aws ssm describe-parameters --output=json \
        | jq -r ".Parameters[].Name" \
        | fzf
end


set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"


set -x GOPATH $HOME/.go
set -x GOROOT (brew --prefix golang)/libexec
set -x PATH ~/.flutter/platform-tools ~/.flutter/flutter/bin $GOPATH $GOROOT/bin $HOME/.jenv/bin (dirname (nvm which node)) (brew --prefix)/opt/python/libexec/bin /usr/local/opt/git/share/git-core/contrib/diff-highlight ~/.local/bin $PATH


set -x ANDROID_HOME /Users/jstromsodd/Library/Android/sdk

set -x BD_OPT 'insensitive'

set -U FZF_DEFAULT_COMMAND "fd --type f"
set -U FZF_FIND_FILE_COMMAND "fd --type f . \$dir"
set -U FZF_OPEN_COMMAND "fd --type f . \$dir"

set -U FZF_PREVIEW_FILE_CMD "bat --plain --color=always --line-range :10"
set -U FZF_ENABLE_OPEN_PREVIEW 1
set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_COMPLETE 2

alias fp 'fzf --preview="bat {} --color=always" --print0 | xargs -0 bat'
alias fpd 'fzf --preview="bat {} --color=always" --preview-window down --print0 | xargs -0 | xargs bat'



set -x RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# Exa is cooler than ls, duh
alias ll "exa --long --git"
alias l "exa --long --git"
alias la "exa --long --all"

# Calendar
alias month="gcal --starting-day=1"

# Tig aliases
alias t tig
alias tst "tig status"

alias code code-insiders
alias vsc "code ."

alias tf terraform

pyenv init --path | source

function jq
    if isatty stdout
        command jq -C $argv | less -RXF
    else
        command jq $argv
    end
end

function http
    if isatty stdout; and not contains -- --download $argv; and not contains -- -d $argv
        command http --pretty=all --print=hb $argv | less -RXF;
    else
        command http $argv
    end
end

function jql
    if isatty stdout
        command jql $argv | less -RXF
    else
        command jql $argv
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

function tree
    if isatty stdout
        command exa --tree --color=always $argv |  less -RXF
    else
        command exa --tree $argv
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

complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'


# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/__tabtab.fish ]; and . ~/.config/tabtab/__tabtab.fish; or true

function switch_terraform --on-event fish_postexec
    string match --regex '^cd\s' "$argv" > /dev/null
    set --local is_command_cd $status

    if test $is_command_cd -eq 0
        if count *.tf > /dev/null

        grep -c "required_version" *.tf > /dev/null
        set --local tf_contains_version $status

        if test $tf_contains_version -eq 0
            command tfswitch
        end
        end
    end
end

function switch_nvm --on-event fish_postexec
    string match --regex '^(cd|__z)\s' "$argv" > /dev/null
    set --local is_command_cd $status
    if test $is_command_cd -eq 0; and test -f .nvmrc
        set currentVersion (nvm current)
        set desiredVersion (nvm version (cat .nvmrc))

        if test $desiredVersion != $currentVersion
            nvm use
        end
    end
end

jenv init - | source

function start-my-day
    echo "Updating homebrew 🍺"
    brew update && brew upgrade && brew upgrade --cask

    # git -C ~/.emacs.d pull --rebase
    echo "Updating doom"
    doom upgrade

    echo "Updating intellimacs"
    git -C ~/.intellimacs pull --rebase
end
