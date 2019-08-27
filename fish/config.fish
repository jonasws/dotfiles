#if not functions -q fisher
#    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
#    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
#    fish -c fisher
#end


set -x PATH /var/lib/snapd/snap/bin /home/linuxbrew/.linuxbrew/bin $HOME/.npm-global/bin:$HOME/.maven-installation/apache-maven-3.6.1/bin $HOME/.local/bin $PATH

eval (starship init fish)

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

# yarn abbrevs

alias withjava12 "env JAVA_HOME=/usr/lib/jvm/zulu-12"

abbr - "cd -"

abbr cb clipboard

abbr -a gupa "git pull --rebase --autostash"

function trigger-lrm-jenkins
    set JOB_NAME $argv[1]
    set JENKINS_BASE http://lrm-dev.tine.no:8080
    set AUTH lrm:melkpaavei
    set CRUMB (http --auth $AUTH GET $JENKINS_BASE/crumbIssuer/api/json | jq -r .crumb)
    http --auth $AUTH POST $JENKINS_BASE/job/$JOB_NAME/job/master/build Jenkins-Crumb:$CRUMB > /dev/null 2> /dev/null &&\
        echo "Triggered build of $JOB_NAME"
end

function open-in-jenkins
    set JOB_NAME (repo-name)
    open http://lrm-dev.tine.no:8080/blue/organizations/jenkins/$JOB_NAME/activity
end

function repo-name
   basename (git rev-parse --show-toplevel)
end

alias oni2 /home/jonasws/Onivim2-x86_64.AppImage

thefuck --alias | source


# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[ -f /home/jonasws/.npm-global/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.fish ]; and . /home/jonasws/.npm-global/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.fish

