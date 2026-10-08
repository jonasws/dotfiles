# fnox runs one daemon per profile, and only the default profile's starts by
# itself. `fnox exec -P github-mcp` talks to a github-mcp daemon that nothing
# brings up, so every profile-scoped read resolves cold. Cold means age-plugin-se
# decrypts the sync-age blob in the Secure Enclave, which costs a Touch ID prompt
# per profile. Claude Code starts its stdio MCP servers in parallel, so those
# prompts arrive several at once and in whatever order the servers come up.
#
# The guide calls the daemon per-user and says read commands auto-start it. The
# profile scoping appears only in `fnox daemon clear`'s description, and
# auto-start does not extend to it — hence starting them here.
#
# `fnox profiles` rather than reading config.toml: it is fnox's own view of the
# file, so a profile added later is covered without a second parser to keep in
# step. Starting a daemon resolves nothing, so this never prompts on its own.
#
# Backgrounded because the calls total ~200ms, which is small but paid by every
# new shell and every Herdr pane.
if status is-interactive; and command -q fnox
    begin
        fnox profiles 2>/dev/null |
            string replace --filter --regex '^\s+(\S+).*' '$1' |
            while read -l profile
                fnox daemon start -P $profile >/dev/null 2>&1
            end
    end &
    disown $last_pid 2>/dev/null
end
