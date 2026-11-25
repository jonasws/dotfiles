function lazyjira --wraps lazyjira --description 'lazyjira with its Jira credentials from fnox'
    # The Jira values are env = false in fnox, so only this function and
    # television's jira.sh receive them. lazyjira wants the host with a scheme.
    set -l host (fnox get JIRA_HOST); or return 1
    string match -qr '^https?://' -- $host; or set host https://$host
    set -l email (fnox get JIRA_EMAIL); or return 1
    set -l token (fnox get JIRA_API_TOKEN); or return 1
    JIRA_HOST=$host JIRA_EMAIL=$email JIRA_API_TOKEN=$token command lazyjira $argv
end
