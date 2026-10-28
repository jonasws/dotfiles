-- herdr ids for Rex objects, as tuios makes them for its own
-- (internal/session/herdr_ids.go): built from the UUIDs, so they hold for as
-- long as the object lives, whatever it is renamed to.
--
--   herdr workspace   Rex session   w<12 hex>
--   herdr tab         Rex window    w<12 hex>:t<12 hex>
--   herdr pane        Rex block     w<12 hex>:p<12 hex>
--
-- herdr scripts check for this shape (herdr-focus.sh, herdr-preview.sh).
-- fish/conf.d/45-rex-herdr.fish derives the same ids for a pane's environment.

local M = {}

-- The last 12 hex digits of a Rex id such as "block:01a10e00-729d-…".
function M.tail(id)
  local hex = tostring(id or ""):gsub("^[^:]*:", ""):gsub("[^%x]", ""):lower()
  return hex:sub(-12)
end

function M.workspace(session_id)
  return "w" .. M.tail(session_id)
end

function M.tab(session_id, window_id)
  return M.workspace(session_id) .. ":t" .. M.tail(window_id)
end

function M.pane(session_id, block_id)
  return M.workspace(session_id) .. ":p" .. M.tail(block_id)
end

-- The parts of a herdr id: kind ("workspace", "tab" or "pane"), the
-- workspace part and the object part.
function M.parse(id)
  if type(id) ~= "string" then return nil end
  local w, kind, rest = id:match("^w(%x+):([tp])(%x+)$")
  if w then return kind == "t" and "tab" or "pane", w, rest end
  w = id:match("^w(%x+)$")
  if w then return "workspace", w, nil end
  return nil
end

return M
