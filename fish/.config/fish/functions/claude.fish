function claude --wraps claude
    set -x GITHUB_TOKEN $CLAUDE_GITHUB_TOKEN
    set -x GITHUB_PAT $CLAUDE_GITHUB_TOKEN
    set -x EXA_API_KEY $CLAUDE_EXA_API_KEY

    command claude $argv
end
