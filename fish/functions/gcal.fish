function gcal --wraps=gcalcli --description "Google Calendar CLI with fnox-managed credentials"
    set -l client_id (fnox get -P gcalcli --no-defaults GCALCLI_CLIENT_ID)
    or return 1
    set -l client_secret (fnox get -P gcalcli --no-defaults GCALCLI_CLIENT_SECRET)
    or return 1

    set -lx GCALCLI_CONFIG $XDG_CONFIG_HOME/gcalcli/config.toml
    set -lx COLUMNS (tput cols)
    gcalcli --client-id=$client_id --client-secret=$client_secret \
        $argv | less -S -F -r
end
