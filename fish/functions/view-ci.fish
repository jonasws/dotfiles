function view-ci --description "Watch the GitHub Actions runs for HEAD, or print their results once finished"
    set -l sha (git rev-parse HEAD)
    or return 1

    # One request lists every workflow run for this exact commit, so a push that
    # triggers several workflows, or one still queued, is covered without a picker.
    set -l runs (gh run list --commit $sha \
        --json databaseId,status,conclusion,workflowName \
        --jq '.[] | [.databaseId, .status, .conclusion, .workflowName] | @tsv')
    or return 1

    if test (count $runs) -eq 0
        echo "view-ci: no workflow runs for "(string sub -l 7 $sha)" yet; is it pushed?" >&2
        return 1
    end

    set -l active
    for run in $runs
        set -l fields (string split \t $run)
        test $fields[2] != completed; and set -a active $fields[1]
    end

    if test (count $active) -gt 0
        for id in $active
            gh run watch $id $argv
        end
        return
    end

    set -l failed 0
    for run in $runs
        set -l fields (string split \t $run)
        printf '%-10s %s\n' $fields[3] $fields[4]
        contains -- $fields[3] success skipped neutral; or set failed 1
    end
    return $failed
end
