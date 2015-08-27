#!/usr/bin/zsh

link_file () {
    dotfile=$1
    base=$(basename $dotfile)
    directory=$HOME

    if [[ -n $2 ]]; then
        directory=$2
    fi

    location=$directory/$base


    if [[ -f $location ]]; then
        if [[ ! -L $location ]]; then
            echo "Backing up ${location} to ${location}.backup"
            mv $location $location.backup
        fi
    fi

    if [[ $location -ef $dotfile ]]; then
        echo "dotfiles/${dotfile} already symlinked into ${location}"
        continue
    fi

    cd $directory
    echo "Symlinking dotfiles/${dotfile} into ${location}"

    src=dotfiles/$dotfile
    if [[ -n $3 ]]; then
        src=$3$src
    fi
    ln -s $src $base
    cd -
}

# Files that go in $HOME
for dotfile (zsh/.* vim/.*); do
    link_file $dotfile
done

# Atom configuration Files
for dotfile (atom/*.js atom/*.json); do
    link_file $dotfile $HOME/.atom "../"
done
