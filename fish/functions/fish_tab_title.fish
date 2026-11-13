function fish_tab_title --description 'The tab title: repo@branch or the folder, without the running command'
    # fish sends this as OSC 1 right after fish_title's OSC 0, so the tab title
    # survives the window title that OSC 0 also writes there.
    __fish_title_where
end
