function view-ci --wraps='gh run ls -b (__git.current_branch) --status in_progress --json databaseId --jq .[].databaseId | xargs -r op plugin run -- gh run watch' --description 'alias view-ci gh run ls -b (__git.current_branch) --status in_progress --json databaseId --jq .[].databaseId | xargs -r op plugin run -- gh run watch'
    gh run ls -b (__git.current_branch) --status in_progress --json databaseId --jq .[].databaseId | xargs -r op plugin run -- gh run watch $argv
end
