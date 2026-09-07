function gcal --wraps=gcalcli --description "Google Calendar CLI with 1Password integration"
    set -l creds (op-read-or-fail "op://Employee/gcalcli/username" "op://Employee/gcalcli/credential")
    or return 1

    set -lx GCALCLI_CONFIG $XDG_CONFIG_HOME/gcalcli/config.toml
    set -lx COLUMNS (tput cols)
    gcalcli --client-id=$creds[1] --client-secret=$creds[2] \
        $argv | less -S -F -r
end
