-- Built-in multicursor (nvim 0.13+, :help multicursor). Cursors are extmarks in
-- the "nvim.multicursor" namespace, which is the public API for reading and
-- clearing them; vim._core.mcursor is internal and may change.
local M = {}

local ns = vim.api.nvim_create_namespace("nvim.multicursor")

-- The buffer-local 'follow' option ships with multicursor, so its presence is
-- the feature check.
M.available = vim.fn.exists("+follow") == 1

---@param buf? integer
function M.count(buf)
  if not M.available then
    return 0
  end
  return #vim.api.nvim_buf_get_extmarks(buf or 0, ns, 0, -1, {})
end

---@param buf? integer
function M.active(buf)
  return M.available and #vim.api.nvim_buf_get_extmarks(buf or 0, ns, 0, -1, { limit = 1 }) > 0
end

---@param buf? integer
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf or 0, ns, 0, -1)
end

return M
