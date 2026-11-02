function tuios-awake -a minutes --description "Keep the Mac awake while the tuios daemon runs (Ctrl-C to stop)"
    # proc list, not proc by: name lookups skip ancestors, and in a tuios pane the daemon is one.
    set -l pid (proc list --json | jq -r '[.processes[] | select(.name == "tuios" and .command == "tuios daemon")] | max_by(.start_time) | .pid // empty')
    if test -z "$pid"
        echo "tuios-awake: no tuios daemon running" >&2
        return 1
    end

    # -i blocks idle sleep (battery too), -s system sleep on AC; the display still sleeps and locks.
    set -l args -i -s -w $pid
    if test -n "$minutes"
        set -a args -t (math "$minutes * 60")
    end

    echo "Keeping awake for tuios daemon $pid"(test -n "$minutes"; and echo " for $minutes min")". Closing the lid still sleeps. Ctrl-C to stop."
    caffeinate $args
end
