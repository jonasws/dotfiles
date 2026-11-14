-- Rex server config on the Raspberry Pi, linked to ~/.config/rex/init.lua by
-- the rex dotfile group. Reload with `rex config reload`.
--
-- `tuios integration install rex` (run by the bootstrap task) writes tuios.lua next
-- to this file. The require line below has no "added by tuios integration"
-- marker, so tuios treats it as ours: it keeps it and leaves this file alone.
--
-- The Rex server's PATH has no mise shims, so point tuios.lua at the shim.
require("tuios").setup{
  bin = os.getenv("HOME") .. "/.local/share/mise/shims/tuios",
  harness = "pi",
}
