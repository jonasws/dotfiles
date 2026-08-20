# Run a one-shot command in a freshly spawned herdr pane.
#
# `herdr pane split` always starts the login shell and has no --command flag,
# so the environment is the only race-free channel for handing a command to a
# new pane. Typing it in with `herdr pane run` is not reliable: keystrokes sent
# before the shell finishes initialising are dropped, and a resend after the
# command finally runs lands in whatever program has taken over the terminal.
#
#   herdr pane split --direction right --env "HERDR_EXEC_CMD=sh /tmp/foo.sh"
#
# The pane closes itself when the command exits, unless HERDR_EXEC_KEEP_OPEN is
# also set, in which case it drops to an interactive prompt.
if status is-interactive; and set -q HERDR_EXEC_CMD
    set -l _herdr_exec_cmd $HERDR_EXEC_CMD
    set -e HERDR_EXEC_CMD
    eval $_herdr_exec_cmd
    set -l _herdr_exec_status $status
    if set -q HERDR_EXEC_KEEP_OPEN
        set -e HERDR_EXEC_KEEP_OPEN
    else
        exit $_herdr_exec_status
    end
end
