function fish_tab_title --description 'The tab title: the branch, or folder@branch below the repo root; repo@branch outside its own tuios session'
    # fish sends this as OSC 1 right after fish_title's OSC 0, so the tab title
    # survives the window title that OSC 0 also writes there. tuios labels a
    # workspace with it, and a tuios session is named after its repo, so the
    # repo name would only repeat the session's.
    set -l where (__fish_title_where)
    if set -q TUIOS_SESSION[1]; and test -n "$TUIOS_SESSION"
        set where (string replace -r -- '^'(string escape --style=regex -- $TUIOS_SESSION)'(@|/)' '' $where)
    end
    echo $where
end
