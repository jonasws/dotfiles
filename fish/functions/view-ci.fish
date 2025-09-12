function view-ci --description "Watch CI run for current commit"
    set -l projectName (basename (pwd))
    set -l rev (git rev-parse HEAD)
    set -l runId (gh run list --commit $rev --json databaseId -q '.[0].databaseId')
    gh run watch $runId
end