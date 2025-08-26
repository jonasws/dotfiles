#!/bin/bash
# Set IS_TV user variable for wezterm
printf "\033]1337;SetUserVar=IS_TV=%s\007" $(echo -n "true" | base64)
# Run tv
tv "$@"
# Unset IS_TV when exiting
printf "\033]1337;SetUserVar=IS_TV=%s\007" $(echo -n "false" | base64)