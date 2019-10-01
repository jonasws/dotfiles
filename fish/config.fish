#if not functions -q fisher
#    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
#    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
#    fish -c fisher
#end


set -x PATH /var/lib/snapd/snap/bin /home/linuxbrew/.linuxbrew/bin $HOME/.nvm/versions/node/v12.10.0/bin $HOME/.npm-global/bin:$HOME/.maven-installation/apache-maven-3.6.1/bin $HOME/.local/bin $PATH

starship init fish | source

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

alias vsc "code-insiders ."
abbr yi "yarn --ignore-engines"
abbr yt "yarn test"
alias train_nyland "entur_oracle departures NSR:Quay:505"
alias git hub
alias top vtop
alias old_top /usr/bin/top


abbr - "cd -"

abbr cb clipboard

abbr -a gupa "git pull --rebase --autostash"


function repo-name
    basename (git rev-parse --show-toplevel)
end

thefuck --alias | source
