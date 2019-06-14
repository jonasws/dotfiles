if not functions -q fisher
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
    fish -c fisher
end


set -x PATH $PATH /var/lib/snapd/snap/bin $HOME/.kotlin-language-server/bin $HOME/.android-sdk/tools/bin $HOME/.flutter-installation/bin:/home/linuxbrew/.linuxbrew/bin $HOME/.npm-global/bin:$HOME/.maven-installation/apache-maven-3.6.1/bin $HOME/.local/bin /snap/bin /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin:/bin:/usr/games /usr/local/games


set fish_color_command yellow
set fish_color_autosuggestion white

# Vim duh
set -x EDITOR vim

alias vsc "code-insiders ."
alias yi "yarn --ignore-engines"
alias train_nyland "entur_oracle departures NSR:Quay:505"
alias git hub
alias top vtop
alias old_top /usr/bin/top

abbr - "cd -"

abbr -a gupa "git pull --rebase --autostash"

function trigger-lrm-jenkins
    set JOB_NAME $argv[1]
    set JENKINS_BASE http://lrm-dev.tine.no:8080
    set AUTH lrm:melkpaavei
    set CRUMB (http --auth $AUTH $JENKINS_BASE/crumbIssuer/api/json | jq -r .crumb)
    http --auth $AUTH POST $JENKINS_BASE/job/$JOB_NAME/job/master/build Jenkins-Crumb:$CRUMB > /dev/null 2> /dev/null &&\
        echo "Triggered build of $JOB_NAME"
end

function repo-name
   basename (git rev-parse --show-toplevel)
end


function oni2
    npm run-script run --prefix=$HOME/oni2 (realpath $argv)
end
