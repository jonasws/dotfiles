function tuios-awake --description "Keep the Mac running with the lid closed while the tuios daemon runs (Ctrl-C restores sleep)"
    argparse 'm/min-battery=' 'h/help' -- $argv; or return 2
    if set -q _flag_help
        echo "usage: tuios-awake [-m PERCENT] [MINUTES]"
        echo "  -m  stop when on battery and charge falls below PERCENT (default 15)"
        return 0
    end
    set -l minutes $argv[1]
    set -l floor 15
    set -q _flag_min_battery; and set floor $_flag_min_battery

    # proc list, not proc by: name lookups skip ancestors, and in a tuios pane the daemon is one.
    set -l daemon (proc list --json | jq -r '[.processes[] | select(.name == "tuios" and .command == "tuios daemon")] | max_by(.start_time) | .pid // empty')
    if test -z "$daemon"
        echo "tuios-awake: no tuios daemon running" >&2
        return 1
    end

    # disablesleep is what keeps the machine running with the lid closed; caffeinate alone does not.
    # It is persistent system state, so remember the old value and restore it on every exit path.
    set -l previous (pmset -g | string match -rg 'SleepDisabled\s+(\d)')
    test -n "$previous"; or set previous 0

    echo "tuios-awake: sudo is needed for pmset"
    sudo -v; or return 1

    # Root-owned watchdog restores the setting even if this shell is SIGKILLed or the pane is closed.
    sudo sh -c 'while kill -0 "$1" 2>/dev/null; do sleep 3; done; pmset -a disablesleep "$2"' tuios-awake-watchdog $fish_pid $previous &
    set -l watchdog $last_pid
    disown $watchdog 2>/dev/null

    sudo pmset -a disablesleep 1; or return 1

    set -g __tuios_awake_previous $previous
    function __tuios_awake_restore --on-signal INT --on-signal TERM --on-signal HUP
        # A signal handler replaces the default action, so also stop caffeinate to end the wait loop below.
        kill $__tuios_awake_caf 2>/dev/null
        sudo -n pmset -a disablesleep $__tuios_awake_previous 2>/dev/null
        or pmset -g | string match -q -r "SleepDisabled\s+$__tuios_awake_previous"
        or echo "tuios-awake: could not restore disablesleep=$__tuios_awake_previous; the watchdog will" >&2
    end

    # -i idle sleep, -s system sleep on AC, -w ends it when the daemon exits.
    set -l args -i -s -w $daemon
    test -n "$minutes"; and set -a args -t (math "$minutes * 60")
    caffeinate $args &
    set -l caf $last_pid
    set -g __tuios_awake_caf $caf

    set -l span ""
    test -n "$minutes"; and set span " for $minutes min"
    echo "Awake for tuios daemon $daemon$span. Lid may be closed; stops below $floor% on battery. Ctrl-C to stop."

    while kill -0 $caf 2>/dev/null
        set -l batt (pmset -g batt)
        if string match -q "*discharging*" -- $batt
            set -l pct (string match -rg '(\d+)%' -- $batt)
            if test -n "$pct"; and test $pct -lt $floor
                echo "tuios-awake: battery at $pct%, stopping" >&2
                break
            end
        end
        for i in (seq 15)
            kill -0 $caf 2>/dev/null; or break
            sleep 1
        end
    end

    kill $caf 2>/dev/null
    __tuios_awake_restore
    functions -e __tuios_awake_restore
    set -e __tuios_awake_previous __tuios_awake_caf
    echo "tuios-awake: sleep settings restored"
end
