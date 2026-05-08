function trim-log-times --description "Strip leading timestamp prefix from `aws logs tail --format short` output, keeping only JSON lines. Pipe to jq."
    grep --line-buffered -E '^[^ ]+ +\{' | gsed -u -E 's/^[^ ]+ +//'
end
