-- The executor behind every floater in floaters/commands.lua. rex-floaters
-- runs it inside the floater's own `rex do` process with (ctx, values): ctx.name
-- picks the command, ctx.origin is the pane the key was pressed in, and
-- values[1] is the collector's pick, if the entry has a collector.
--
-- The command gets what rex/herdr.lua hands herdr's command keys: HERDR_ENV
-- and the pane, tab and directory the key was pressed in. The floater's own
-- HERDR_PANE_ID comes from fish/conf.d/45-rex-herdr.fish and names the
-- floater, which is why the scripts read the HERDR_ACTIVE_* variables.
local ctx, values = ...

local here = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
local ids = dofile(here .. "../herdr/ids.lua")

local command
for _, spec in ipairs(dofile(here .. "commands.lua")) do
  if spec.name == ctx.name then command = spec.command end
end
if not command then error("floaters/commands.lua has no command for " .. tostring(ctx.name), 0) end

local cwd = values and values[1] or ctx.cwd
local origin = ctx.origin or {}
local env = { HERDR_ENV = "1", HERDR_ACTIVE_PANE_CWD = cwd }
if origin.session_id and origin.block_id then
  env.HERDR_ACTIVE_PANE_ID = ids.pane(origin.session_id, origin.block_id)
end
if origin.session_id and origin.window_id then
  env.HERDR_ACTIVE_TAB_ID = ids.tab(origin.session_id, origin.window_id)
end

-- Through the login shell, as herdr runs command keys, so PATH has mise's and
-- Homebrew's tools whatever environment the Rex server started with.
return ctx.exec({ os.getenv("SHELL") or "/bin/zsh", "-l", "-c", command }, { cwd = cwd, env = env })
