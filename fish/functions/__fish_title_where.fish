function __fish_title_where --description 'repo@branch (repo/folder@branch below the root), or the folder outside a repo'
    # fish_title runs this on every prompt draw and before every command, so
    # it starts no process: the repo and branch come from reading .git with
    # builtins.
    set -l where
    set -l root $PWD
    while not test -e $root/.git; and test $root != /
        set root (path dirname -- $root)
    end
    if test $root != /
        set -l gitdir $root/.git
        if test -f $gitdir
            # A worktree or submodule: .git names the real git dir.
            read -l line <$gitdir 2>/dev/null
            set gitdir (string replace -r '^gitdir: ' '' -- $line)
            string match -q '/*' -- $gitdir; or set gitdir $root/$gitdir
        end
        set -l branch
        if read -l head <$gitdir/HEAD 2>/dev/null
            set branch (string replace -r '^ref: refs/heads/' '' -- $head)
            test "$branch" = "$head"; and set branch (string sub -l 7 -- $head)
            set branch (string shorten -m 24 -- $branch)
        end
        set where (path basename -- $root)
        test $PWD != $root; and set where $where/(path basename -- $PWD)
        test -n "$branch"; and set where $where@$branch
    else
        set where (prompt_pwd -d 1 -D 2)
    end

    set -q SSH_TTY; and set where '['(prompt_hostname)'] '$where
    # The result goes into an OSC sequence as is, so a control character in a
    # folder name would end it early.
    string replace -ra '[[:cntrl:]]' '' -- $where
end
