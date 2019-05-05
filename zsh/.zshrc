# Path to your oh-my-zsh installation.

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
#ZSH_THEME="refined"
ZSH_THEME="dracula"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(gradle zsh-syntax-highlighting zsh-autosuggestions copydir copyfile dirpersist last-working-dir git colored-man colorize web-search node npm python mvn docker docker-compose thefuck systemd alias-tips z httpie yarn wd brew fd github)




# User configuration
# export PATH="${HOME}/.npm-global/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/platform-tools:${HOME}/.cabal/bin:/opt/cabal/1.22/bin:/opt/ghc/7.10.3/bin:${HOME}/.local/bin:${GOPATH}/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"

if (( ! ${fpath[(I)/home/linuxbrew/.linuxbrew/share/zsh/site-functions]} )); then
	FPATH=/home/linuxbrew/.linuxbrew/share/zsh/site-functions:$FPATH
fi

source $ZSH/oh-my-zsh.sh

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='vim'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
alias zshconfig="vim ~/.zshrc"
alias ohmyzsh="vim ~/.oh-my-zsh"
alias ci="code-insiders"

# Redefine some aliases, adding nocorrect
alias ssh="nocorrect ssh"
alias which="nocorrect which"

# Custom aliases
alias ping_google="ping 8.8.8.8"
alias router_config="xdg-open http://routerlogin.net"
alias ping_router="ping \$(/sbin/ip route | awk '/default/ { print \$3 }')"
alias ping6_router="ping6 \$(/sbin/ip -6 route | awk '/default/ { print \$3 }')"
alias serve_dir="python -m SimpleHTTPServer 9000"
alias tv2_sport="vlc udp://@233.155.107.105:5700"
alias gcd="git checkout develop"
alias pretty="json_pp | colorize"
alias gh="gh-home"
alias ghu="gh-upstream"
alias ab="atom-beta"

alias y="yarn"
alias yi="yarn --ignore-engines"
alias yb="yarn build"
alias ys="yarn start"
alias yt="yarn test"

alias cl="colorize"

# Git stuff
alias gupa="git pull --rebase --autostash"

# ENTUR CLI aliases :)
alias subway_munkelia="entur_oracle departures NSR:Quay:10667"
alias subway_stortinget="entur_oracle departures NSR:Quay:7256 -n 5 --filter Bergkrystallen"
alias train_nyland="entur_oracle departures NSR:Quay:505"

alias android_emulator="$HOME/Android/Sdk/emulator/emulator @Pixel_XL_API_26"


alias paste_without_whitespace="clippaste | sed 's/\s//g'"

# Aliasing vcode nigthly to "code"
alias code="code-insiders"

alias top=vtop
alias oldtop=/usr/bin/top

alias activate_draw_mode="pkill -f xbindkeys && xbindkeys -f $HOME/.xbindkeysrc-draw"
alias activate_presenter_mode="pkill -f xbindkeys && xbindkeys -f $HOME/.xbindkeysrc-presenter"
alias activate_normal_mode="pkill -f xbindkeys && xbindkeys -f $HOME/.xbindkeysrc"


alias quickopen="bat \$(fzf)"

alias build_in_jenkins="$HOME/TINE/Brukerskifte/trigger-jenkins.sh \$(basename \$(git rev-parse --show-toplevel))"
alias boc="$HOME/TINE/Brukerskifte/open-jenkins-pipeline.sh \$(basename \$(git rev-parse --show-toplevel))"
alias bos="get_jenkins_job | xargs $HOME/TINE/Brukerskifte/open-jenkins-pipeline.sh"

alias locjs="fd \.js$ src | xargs cat | wc -l"
alias locjs_notest='fd \.js$ src  -E "*.test.js" -E __mocks__ -E stories| xargs cat | wc -l'

download() {
    http $1 --download --out $2
}

get_jenkins_job() {
    JENKINS_BASE_URL="http://lrm-dev.tine.no:8080"
    AUTH="lrm:melkpaavei"
    http --auth $AUTH GET $JENKINS_BASE_URL/api/json | jq -r ".jobs[].name" | fzf
}

get_jenkins_jobs_as_json() {
    JENKINS_BASE_URL="http://lrm-dev.tine.no:8080"
    AUTH="lrm:melkpaavei"
    http --auth $AUTH GET $JENKINS_BASE_URL/api/json
}

# LastPass ncieties
getpassword() {
    lpass show $1 --password --clip
    echo "Password for $1 copied to clipboard :)"
}

searchpassword() {
    ACCOUNT=$(lpass export --fields=name,username,id | tail -n +2 | fzf | cut -d "," -f 3)
    lpass show $ACCOUNT --password --clip && echo "Copied password to clipboard :)"
}


TIGER_CONFIG_DIR="${HOME}/tigervpn-config"

tigervpn() {
    exp=$1*
    config=$(find $TIGER_CONFIG_DIR -name $exp)
    _ openvpn --cd $TIGER_CONFIG_DIR --config $config
}


# AWS CLI completion
[ -f $HOME/.local/bin/aws_zsh_completer.sh ] && source $HOME/.local/bin/aws_zsh_completer.sh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
[ -f ~/.docker-fzf.zsh ] && source ~/.docker-fzf.zsh
