#!/usr/bin/bash

GIT_ROOT=$(git rev-parse --show-toplevel)

ln -s $GIT_ROOT/vim/.vimrc ~/.vimrc
ln -s $GIT_ROOT/tig/.tigrc ~/.tigrc
ln -s $GIT_ROOT/ripgrep/.ripgreprc ~/.ripgreprc

mkdir -p ~/.config/bat
ln -s bat/config $HOME/.config/bat/config

sudo apt-get install -y tig ripgrep bat
