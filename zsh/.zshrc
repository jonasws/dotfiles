# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"

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
plugins=(copydir copyfile dirpersist last-working-dir vi-mode git colored-man colorize web-search node npm python django docker alias-tips)

# GitHub API access configuration
export GITHUB_USERNAME="jonasws"
export GITHUB_ACCESS_TOKEN="$(cat $HOME/.github_token)"

# User configuration

bindkey -v
bindkey "^R" history-incremental-search-backward


export ANDROID_HOME="${HOME}/android-sdk-linux"
export PATH="${HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"
export MANPATH="/usr/local/man:$MANPATH"

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

# Redefine some aliases, adding nocorrect
alias ssh="nocorrect ssh"
alias which="nocorrect which"

# Custom aliases
alias ping_google="ping 8.8.8.8"
alias router_config="xdg-open http://routerlogin.net"
alias ping_router="ping $(/sbin/ip route | awk '/default/ { print $3 }')"
alias ping6_router="ping6 $(/sbin/ip -6 route | awk '/default/ { print $3 }')"
alias serve_dir="python -m SimpleHTTPServer 9000"
alias tv2_sport="vlc udp://@233.155.107.105:5700"
alias gcd="git checkout develop"

startvm () {
  VBoxManage startvm "$1" --type headless
}

stopvm () {
  VBoxManage controlvm "$1" poweroff
}

xdg-qopen () {
  xdg-open "$1" 2> /dev/null
}

alias stk="startvm \"Kali Linux\""
alias spk="stopvm \"Kali Linux\""
alias download_wav="youtube-dl -x --audio-format \"wav\" "

eval $(thefuck --alias)

rip_spotify_url () {
  spotify-ripper --user jstroemsodd --flat --wav $(spotify_url_to_uri $1)
}

alias aptup="_ apt-get update && _ apt-get upgrade"
alias ghu="$HOME/utils/fetch_github_utils_download_count.py"

alias reload_pipelight="_ pipelight-plugin --disable silverlight && _ pipelight-plugin --enable silverlight"
