function claude --wraps claude
    set -lx GITHUB_TOKEN "op://Employee/Liflig Github PAT/token"
    op run --no-masking -- command claude $argv
end
