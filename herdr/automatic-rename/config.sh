# qu8n/herdr-automatic-rename -- tab naming.
#
# Sourced by automatic-rename.sh before its defaults, so anything set here wins.
# Every setting has a working default; only the departures are recorded below.

# Workspaces are already named after their repo and there is no 1-9 binding that
# reaches them -- switch_workspace is unset, and prefix+w plus navigate j/k is
# how they get picked. A "[4] " prefix would spend four columns of a 26-column
# sidebar on a key that does not exist.
AUTO_INDEX_WORKSPACES=0

# Tabs keep their number: switch_tab = "prefix+1..9" is herdr's default and is
# live here, so the digit on the label is the key that jumps to it.
AUTO_INDEX_TABS=1

# Named as it is invoked, not as it is installed. `claude` is a fish function
# wrapping `caveman claude`, and mise shims put a versioned interpreter in the
# foreground for others.
PROGRAM_ALIASES=(
  "lazygit=lg"
)

# Default is MAX_NAME_LEN + 8 = 28, which cuts a Claude topic mid-thought
# ("Whoami endpoint with"). The tab bar spans the full terminal here and rarely
# holds more than a handful of tabs, so it can afford the width.
MAX_TITLE_LEN=40
