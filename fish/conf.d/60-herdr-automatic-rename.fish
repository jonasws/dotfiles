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
# Globbed rather than hardcoded: `herdr plugin install` puts the checkout in
# <name>-<hash>/<install number>/checkout, and the install number changes on
# every update. Newest first, so a leftover older install is only a fallback.
set -l _hooks $HOME/.config/herdr/plugins/github-installations/herdr-automatic-rename-*/*/checkout/shell/hook.fish
for _f in $_hooks[-1..1]
    test -r "$_f"; and source "$_f"; and break
end

# The plugin's preexec names the tab after the first word of the line. fish
# aliases are functions and abbreviations can reach preexec unexpanded, so both
# arrive as "not a file" and fall back to sampling the foreground process.
# Resolving them here lets `lg` or `n` name the tab straight away.
#
# Redefined after the source above so it replaces the plugin's handler; the
# `functions -q` guard keeps this inert when the plugin is not installed.
if functions -q _har_preexec
    function _har_resolve_word --argument-names word
        # Aliases: `alias g git status` defines a function whose description is
        # "alias g git status".
        if test "$(type --type -- $word 2>/dev/null)" = function
            set -l desc (functions -Dv -- $word 2>/dev/null)[5]
            if string match -q -- "alias $word *" $desc
                string replace -- "alias $word " '' $desc
                return
            end
        end
        # Abbreviations: `abbr --show` prints `abbr -a -- name 'expansion'`.
        set -l abbr_line (abbr --show 2>/dev/null | string match -r -- "^abbr -a -- \Q$word\E (.+)\$")[2]
        and string unescape -- $abbr_line
    end

    function _har_preexec --on-event fish_preexec
        set -l line $argv[1]
        set -l word (string split -m 1 ' ' -- $line)[1]
        for _depth in (seq 5)
            test "$(type --type -- $word 2>/dev/null)" = file; and break
            set -l expanded (_har_resolve_word $word)
            test -n "$expanded"; or break
            set -l next (string split -m 1 ' ' -- $expanded)[1]
            test "$next" = "$word"; and break
            set line (string join ' ' -- $expanded (string split -m 1 ' ' -- $line)[2])
            set word $next
        end
        if test "$(type --type -- $word 2>/dev/null)" = file
            command "$_har_bin" preexec "$line" >/dev/null 2>&1 &
        else
            command "$_har_bin" preexec "$line" shell >/dev/null 2>&1 &
        end
        disown 2>/dev/null
    end
end
