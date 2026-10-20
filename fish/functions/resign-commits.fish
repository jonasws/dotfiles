function resign-commits --description "Sign the unsigned commits between a base (default: upstream) and HEAD"
    argparse h/help -- $argv
    or return 2

    if set -q _flag_help; or test (count $argv) -gt 1
        echo "usage: resign-commits [base]   # base defaults to the branch's upstream" >&2
        return 2
    end

    set -l base $argv[1]
    if test -z "$base"
        set base (git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
        or begin
            echo "resign-commits: no upstream; pass a base commit" >&2
            return 2
        end
    end

    # %G? needs gpg.ssh.allowedSignersFile to verify and reports N without it,
    # so look for the signature header instead of verifying it.
    set -l unsigned
    for c in (git rev-list --reverse $base..HEAD)
        git cat-file commit $c | string match -q 'gpgsig*'
        or set -a unsigned $c
    end

    if test (count $unsigned) -eq 0
        echo "resign-commits: every commit in $base..HEAD is signed"
        return 0
    end

    # Commits before the oldest unsigned one keep their hashes; everything after
    # it is rewritten anyway once its parent changes, so all of it gets signed.
    set -l oldest $unsigned[1]
    set -l total (git rev-list --count $oldest^..HEAD 2>/dev/null; or git rev-list --count HEAD)
    echo "resign-commits: "(count $unsigned)" unsigned, signing $total from "(git rev-parse --short $oldest)

    if test $oldest = (git rev-parse HEAD)
        git commit --amend --no-edit --no-verify --gpg-sign
    else if git rev-parse -q --verify $oldest^ >/dev/null
        git rebase --gpg-sign --force-rebase --rebase-merges --autostash $oldest^
    else
        git rebase --gpg-sign --force-rebase --rebase-merges --autostash --root
    end
end
