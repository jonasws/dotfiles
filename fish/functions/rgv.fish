function rgv
    set tmp (mktemp)
    rg --vimgrep $argv >$tmp
    nvim -q $tmp -c "lua require('trouble').open('qflist')"
    rm $tmp
end
