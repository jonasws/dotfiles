function cwlogs
    nu -l -c "cwlogs $argv | each { \$in | to json --raw } | str join \"\\n\""
end
