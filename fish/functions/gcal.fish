function gcal --wraps=gcalcli --description "Google Calendar CLI with 1Password integration"
    set -x GCALCLI_CONFIG $XDG_CONFIG_HOME/gcalcli/config.toml
    set -x COLUMNS (tput cols)
    gcalcli --client-id=(op read "op://Employee/gcalcli/username") --client-secret=(op read "op://Employee/gcalcli/credential") \
        $argv | less -S -F -r
end