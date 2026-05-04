function claude --wraps claude
    set -x GITHUB_TOKEN $CLAUDE_GITHUB_TOKEN
    command claude $argv
end
