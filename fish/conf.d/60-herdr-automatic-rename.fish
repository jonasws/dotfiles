# Live tab naming for herdr: qu8n/herdr-automatic-rename.
#
# The plugin's own [[events]] cover tab/pane/workspace lifecycle, but herdr has
# no "foreground command changed" event -- without this hook a tab that starts
# nvim keeps reading `fish` until the next focus change. The hook binds
# fish_preexec/fish_postexec so the label turns over as the command does.
#
# Loaded at 60 so it lands after 30-interactive.fish installs starship and the
# other prompt integrations; the hook itself no-ops outside a herdr pane.
#
# Globbed rather than hardcoded: `herdr plugin install` puts the checkout in a
# directory suffixed with an install hash, which changes on every update.
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.fish
    test -r "$_f"; and source "$_f"; and break
end
