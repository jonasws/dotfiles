-- Our floaters: one per command, each toggled per Rex tab by rex-floaters
-- (https://github.com/enkelm/rex-floaters). Data only, read twice: by
-- floaters/init.lua when the config loads, to register the entries, and by
-- floaters/run.lua inside the floater, to find the command to run.
--
-- `command` runs through the login shell with herdr's command-key variables,
-- as rex/herdr.lua runs herdr's command keys, so the herdr/scripts popups work
-- unchanged. `collect` and `picker` are rex-floaters options; relative paths
-- resolve against the rex-floaters checkout's bundled floaters/ directory.
--
-- Keys sit behind herdr's ctrl+b prefix, like the rest of rex/herdr.lua.
-- Where a key had a herdr popup (a zoomed split) the floater takes it over:
-- the newest binding wins.

local lazygit_repo = {
  -- The bundled collector: the checkout the pane is in, or an fzf pick of
  -- the repositories under it. Its choice becomes HERDR_ACTIVE_PANE_CWD.
  collect = "lazygit/collect.lua",
  picker = { title = "lazygit · choose a repository", multiple = false, skip_single = true },
}

return {
  {
    name = "lazygit",
    title = "lazygit Status",
    binding = "ctrl+b>l",
    command = "~/.config/herdr/scripts/lazygit-popup.sh status",
    keywords = "lg git status floating popup",
    collect = lazygit_repo.collect,
    picker = lazygit_repo.picker,
  },
  {
    name = "lazygit_log",
    title = "lazygit Log",
    binding = "ctrl+b>shift+l",
    command = "~/.config/herdr/scripts/lazygit-popup.sh log",
    keywords = "lg git log history floating popup",
    collect = lazygit_repo.collect,
    picker = lazygit_repo.picker,
  },
  {
    name = "yazi",
    title = "yazi",
    binding = "ctrl+b>y",
    command = "~/.config/herdr/scripts/yazi-popup.sh",
    keywords = "files browse floating popup",
  },
  {
    -- Types the files chosen with Enter into the pane the key was pressed in,
    -- through the herdr socket (rex/herdr/server.lua).
    name = "yazi_pick",
    title = "yazi: Pick Files into Pane",
    binding = "ctrl+b>shift+y",
    command = "~/.config/herdr/scripts/yazi-popup.sh pick",
    keywords = "files pick insert path agent floating popup",
  },
  {
    name = "tsk_notes",
    title = "Edit tsk Notes",
    binding = "ctrl+b>ctrl+e",
    command = "~/.config/herdr/scripts/tsk-notes.sh",
    keywords = "tsk task notes editor floating popup",
  },
  {
    -- A shell per tab that survives being hidden: for a quick command
    -- without disturbing the split layout.
    name = "scratch",
    title = "Scratch Shell",
    binding = "ctrl+b>s",
    command = 'exec "$SHELL" -l',
    keywords = "scratch shell terminal floating popup",
  },
  {
    name = "lazyjira",
    title = "lazyjira",
    binding = "ctrl+b>j",
    command = "lazyjira",
    keywords = "jira issues floating popup",
  },
  {
    name = "btop",
    title = "btop",
    binding = "ctrl+b>b",
    command = "btop",
    keywords = "system monitor top cpu memory floating popup",
  },
}
