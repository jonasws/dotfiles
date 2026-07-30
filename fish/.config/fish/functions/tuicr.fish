function tuicr --wraps tuicr
    set -x GH_TOKEN $(op read "op://Employee/ng6rejbxwjz66bjj4vs4mhbkfq/password" 2>/dev/null); or return 1

    command tuicr $argv
end
