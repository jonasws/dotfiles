# Login shells. macOS /etc/profile has already run path_helper, which puts
# /usr/bin first; .bashrc moves Homebrew back in front of it.
[ -r ~/.profile ] && . ~/.profile
[ -r ~/.bashrc ] && . ~/.bashrc
