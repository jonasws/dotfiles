# Pre-push check for the Kotlin/Maven service repo in the focused pane, which
# must be a shell in the repo's main checkout. The checks live in
# tuios/scripts/preflight.sh; this tape types it, waits on the line each stage
# ends on, and stops at the first stage that fails.
#
#   tuios tape exec ~/.config/tuios/tapes/preflight.tape --timeout 45m
#
# WaitFor and Expect read the pane's screen, so it is cleared first: a marker
# left over from an earlier run would otherwise satisfy the waits.

Run "clear"
Run "~/.config/tuios/scripts/preflight.sh"

WaitFor text "preflight git: (ok|FAIL)" 2m
Expect text "preflight git: ok"

WaitFor text "preflight verify: (ok|FAIL)" 30m
Expect text "preflight verify: ok"

WaitFor text "preflight docker: (ok|FAIL)" 15m
Expect text "preflight docker: ok"

WaitFor text "preflight: all passed" 30s
ShowNotification "Preflight passed: ready to push" success
