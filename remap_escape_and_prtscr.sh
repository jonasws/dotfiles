#!/usr/bin/env sh

xmodmap -e "clear lock" #disable caps lock switch              
xmodmap -e "keysym Caps_Lock = Escape" #set caps_lock as escape
xmodmap -e "keysym Print = Super_R"
