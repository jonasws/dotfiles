function tuicr --wraps tuicr
    set -lx GH_TOKEN (op-read-or-fail "op://Employee/ng6rejbxwjz66bjj4vs4mhbkfq/password")
    or return 1

    command tuicr $argv
end
