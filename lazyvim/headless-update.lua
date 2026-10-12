-- Run by `mise run update:nvim` after `Lazy! sync`:
--   nvim --headless '+luafile <this file>'
-- Mason never upgrades installed packages on its own, and TSUpdate only fires
-- from nvim-treesitter's build hook when the plugin itself moved, so both are
-- driven here and awaited before nvim exits.

require("lazy").load({ plugins = { "mason.nvim", "nvim-treesitter" } })

local TIMEOUT = 15 * 60 * 1000

local function log(msg)
  io.stdout:write(msg .. "\n")
end

local function await(label, start)
  local done, ok, err = false, true, nil
  start(function(success, e)
    done, ok, err = true, success ~= false, e
  end)
  if not vim.wait(TIMEOUT, function() return done end, 100) then
    log(("%s: timed out"):format(label))
    return false
  end
  if not ok then
    log(("%s: failed: %s"):format(label, tostring(err)))
  end
  return ok
end

local failed = false

local function mason_update()
  local registry = require("mason-registry")
  if not await("mason registry", function(cb) registry.update(cb) end) then
    failed = true
    return
  end

  local a = require("mason-core.async")
  local outdated = {}
  await("mason versions", function(cb)
    a.run(function()
      for _, pkg in ipairs(registry.get_installed_packages()) do
        local ok, current, latest = pcall(function()
          return pkg:get_installed_version(), pkg:get_latest_version()
        end)
        if ok and current ~= latest then
          table.insert(outdated, { pkg = pkg, from = current, to = latest })
        end
      end
    end, cb)
  end)

  if #outdated == 0 then
    log("mason: all packages up to date")
    return
  end

  for _, item in ipairs(outdated) do
    local label = ("mason %s %s -> %s"):format(item.pkg.name, item.from, item.to)
    log(label)
    if not await(label, function(cb) item.pkg:install({ version = item.to }, cb) end) then
      failed = true
    end
  end
end

local function treesitter_update()
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok then
    return
  end
  local task = ts.update(nil, { summary = true })
  if not task:wait(TIMEOUT) then
    log("treesitter: update timed out")
    failed = true
  end
end

mason_update()
treesitter_update()

vim.cmd(failed and "cquit 1" or "quit")
