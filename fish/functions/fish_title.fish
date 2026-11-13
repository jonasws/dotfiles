function fish_title --argument-names cmdline \
    --description 'The terminal title: the running command, then repo@branch or the folder'
    # stdout is the title; stderr would land in the prompt.
    set -l cmd
    if test -n "$cmdline"
        set cmd (path basename -- (string split -m 1 -f 1 ' ' -- $cmdline))
    end
    string join -n ' · ' -- $cmd (__fish_title_where) | string replace -ra '[[:cntrl:]]' ''
end
