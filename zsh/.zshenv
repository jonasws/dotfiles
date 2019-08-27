export ZSH=$HOME/.oh-my-zsh

export PATH="/var/lib/snapd/snap/bin:${HOME}/.kotlin-language-server/bin:${HOME}/.android-sdk/tools/bin:${HOME}/.flutter-installation/bin:/home/linuxbrew/.linuxbrew/bin:${HOME}/.npm-global/bin:${HOME}/.maven-installation/apache-maven-3.6.1/bin:${HOME}/.local/bin:/snap/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"
export MANPATH="/usr/local/man:$MANPATH"

export HISTFILE="${HOME}/.zsh_history"
export FZF_DEFAULT_COMMAND='fd --type f'

export ANDROID_HOME="$HOME/.android-sdk"

export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools


eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
