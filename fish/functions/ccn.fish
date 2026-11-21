function ccn --description 'Claude Code in the nono agent sandbox'
    # Claude Code merges permission rules from every settings source, so a
    # --settings file cannot lift the denies ~/.claude/settings.json keeps for
    # unsandboxed sessions (gh, aws, awslogs). Inside nono those tools are
    # brokered, so this session loads a copy of the user settings without those
    # denies and without Claude Code's own sandbox, which cannot run inside
    # nono's. git is told to fetch GitHub's ssh remotes over HTTPS, where nono's
    # proxy carries the credential.
    set -l state $HOME/.local/state/nono-agent
    set -l settings $state/claude-settings.json
    mkdir -p $state
    jq '
      .permissions.deny -= ["Bash(gh:*)", "Bash(aws *)", "Bash(awslogs *)"]
      | del(.sandbox)
      | (.env.GIT_CONFIG_COUNT | tonumber) as $n
      | .env["GIT_CONFIG_KEY_\($n)"] = "url.https://github.com/.insteadOf"
      | .env["GIT_CONFIG_VALUE_\($n)"] = "git@github.com:"
      | .env["GIT_CONFIG_KEY_\($n + 1)"] = "url.https://github.com/.insteadOf"
      | .env["GIT_CONFIG_VALUE_\($n + 1)"] = "ssh://git@github.com/"
      | .env.GIT_CONFIG_COUNT = "\($n + 2)"
    ' $HOME/.claude/settings.json >$settings.tmp
    or return 1
    mv $settings.tmp $settings

    if not test -s $HOME/.local/share/nono-agent/java-truststore.p12
        echo "ccn: no Java truststore for nono's CA yet; Maven will fail TLS. Run: mise -C ~/dotfiles run nono:java-truststore" >&2
    end

    # A fixed proxy port per session, so Maven's static proxy settings
    # (nono/maven/proxy-settings.xml) can name it. Any free port will do.
    set -l port (random 40000 48999)
    for i in (seq 20)
        nc -z 127.0.0.1 $port 2>/dev/null; or break
        set port (random 40000 48999)
    end
    set -gx NONO_AGENT_PROXY_PORT $port

    # The pane gives up tuios's admin grant, so the agent cannot type into your
    # panes or start unsandboxed ones. It keeps read and write: agent state,
    # mail, TML surfaces, and typing into panes that hold no more than it does.
    if test "$TUIOS_ENV" = 1
        tuios set-pane-grants --grants read,write
        or return 1
    end

    exec nono run --profile liflig-agent --proxy-port $port -- \
        claude --setting-sources project,local --settings $settings $argv
end
