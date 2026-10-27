-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Inside a herdr session herdr-splits.nvim owns these chords so they cross the
-- Neovim/herdr-pane boundary; outside one smart-splits.nvim does the same job
-- against Rex panes. Both expose move_cursor_* and resize_*, so the bindings below
-- are identical either way — only the backend differs.
local in_herdr = vim.env.HERDR_ENV == "1"
local mc = require("util.multicursor")
local ok, splits = pcall(require, in_herdr and "herdr-splits" or "smart-splits")

if not ok then
  vim.notify("split navigation unavailable: " .. tostring(splits), vim.log.levels.WARN)
else
  -- resizing splits
  -- Use CTRL+SHIFT to match the wezterm smart-splits config. The previous <A-...>
  -- (Option) bindings collided with the us-altgr-intl layout, where Option+l emits
  -- ø — wezterm now forwards resize as CTRL+SHIFT, so nvim must agree.
  vim.keymap.set("n", "<C-S-h>", splits.resize_left)
  vim.keymap.set("n", "<C-S-j>", splits.resize_down)
  vim.keymap.set("n", "<C-S-k>", splits.resize_up)
  vim.keymap.set("n", "<C-S-l>", splits.resize_right)

  -- moving between splits
  vim.keymap.set("n", "<C-h>", splits.move_cursor_left)
  vim.keymap.set("n", "<C-j>", splits.move_cursor_down)
  vim.keymap.set("n", "<C-k>", splits.move_cursor_up)
  -- <C-l> is also the built-in multicursor clear (nvim 0.13+), so it clears
  -- cursors when the buffer has any and only navigates otherwise.
  vim.keymap.set("n", "<C-l>", function()
    if mc.active() then
      mc.clear()
    else
      splits.move_cursor_right()
    end
  end, { desc = "Clear multicursors / go to right split" })

  -- herdr-splits and smart-splits v3 have no previous-pane equivalent.
  if splits.move_cursor_previous then
    vim.keymap.set("n", "<C-\\>", splits.move_cursor_previous)
  end
end
