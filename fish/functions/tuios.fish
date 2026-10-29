# A function rather than a mise [shell_alias]: `mise activate` runs `complete -e`
# for every alias, and fish then never autoloads completions/tuios.fish.
function tuios --wraps tuios --description 'tuios nightly build'
    ~/.local/share/tuios-nightly/bin/tuios $argv
end
