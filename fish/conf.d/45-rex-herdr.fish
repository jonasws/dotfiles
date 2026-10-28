# Rex panes speak herdr. rex/herdr/server.lua answers herdr's socket API from
# Rex (the com.jonasws.rex-herdr LaunchAgent keeps it running), so herdr tools work in a Rex pane once
# they know where it is and which pane they are in, as herdr and tuios tell
# their own panes. The ids follow rex/herdr/ids.lua: w<12 hex of the
# session>:p<12 hex of the block>.
#
# HERDR_ENV=1 is herdr's "inside herdr" marker, which integrations check before
# talking to the socket. Neovim tells Rex from herdr by REX_SESSION instead.
#
# Loaded before 50-herdr-exec.fish and 60-herdr-automatic-rename.fish, which
# then work in Rex panes as they do in herdr's.
set -q REX_SESSION; and set -q REX_BLOCK; or return

function __rex_herdr_tail --argument-names id
    string replace -r '^[^:]*:' '' -- $id | string replace -ra '[^0-9a-fA-F]' '' | string lower | string sub -s -12
end

if set -q REX_HERDR_SOCKET
    set -gx HERDR_SOCKET_PATH $REX_HERDR_SOCKET
else
    set -l state $HOME/.local/state
    set -q XDG_STATE_HOME; and set state $XDG_STATE_HOME
    set -gx HERDR_SOCKET_PATH $state/rex/herdr.sock
end
set -gx HERDR_WORKSPACE_ID w(__rex_herdr_tail $REX_SESSION)
set -gx HERDR_PANE_ID $HERDR_WORKSPACE_ID:p(__rex_herdr_tail $REX_BLOCK)
set -gx HERDR_ENV 1
functions -e __rex_herdr_tail
