-- herdr key names → the bytes a terminal sends for them, for pane.send_keys.
-- Names follow herdr's (and tuios's internal/session/herdr_keys.go): Enter,
-- Escape, Tab, Backspace, arrows, Home/End/PageUp/PageDown, F1–F12, single
-- characters, and modifier chords such as ctrl+c, alt+b or C-c. A name that
-- isn't a key is typed as text.

local M = {}

local ESC = "\27"
local NAMED = {
  enter = "\r", ["return"] = "\r", tab = "\t", backtab = ESC .. "[Z", btab = ESC .. "[Z",
  escape = ESC, esc = ESC, backspace = "\127", bs = "\127", space = " ",
  up = ESC .. "[A", down = ESC .. "[B", right = ESC .. "[C", left = ESC .. "[D",
  home = ESC .. "[H", ["end"] = ESC .. "[F", pageup = ESC .. "[5~", pagedown = ESC .. "[6~",
  insert = ESC .. "[2~", delete = ESC .. "[3~",
  minus = "-", comma = ",", period = ".", slash = "/", backslash = "\\", quote = "'",
  double_quote = '"', ["double-quote"] = '"', semicolon = ";", colon = ":", percent = "%",
  ampersand = "&", backtick = "`", plus = "+",
}
local FKEYS = {
  ESC .. "OP", ESC .. "OQ", ESC .. "OR", ESC .. "OS", ESC .. "[15~", ESC .. "[17~",
  ESC .. "[18~", ESC .. "[19~", ESC .. "[20~", ESC .. "[21~", ESC .. "[23~", ESC .. "[24~",
}

local function base(name)
  local lower = name:lower()
  if NAMED[lower] then return NAMED[lower] end
  local f = lower:match("^f(%d+)$")
  if f and FKEYS[tonumber(f)] then return FKEYS[tonumber(f)] end
  if #name == 1 then return name end
  return nil
end

-- One key name → bytes, or nil when it isn't a key.
function M.encode(key)
  if key == "+" then return "+" end
  local ctrl, alt, shift = false, false, false
  local name = key
  local c = key:match("^[Cc]%-(.)$")
  if c then return string.char(c:lower():byte() - 96) end
  local parts = {}
  for part in key:gmatch("[^+]+") do parts[#parts + 1] = part end
  if #parts > 1 then
    name = parts[#parts]
    for i = 1, #parts - 1 do
      local m = parts[i]:lower()
      if m == "ctrl" or m == "control" then ctrl = true
      elseif m == "alt" or m == "option" or m == "meta" then alt = true
      elseif m == "shift" then shift = true
      elseif m ~= "cmd" and m ~= "command" and m ~= "super" and m ~= "hyper" then return nil end
    end
  end
  local bytes = base(name)
  if not bytes then return nil end
  if shift and #bytes == 1 then bytes = bytes:upper() end
  if shift and bytes == "\t" then bytes = ESC .. "[Z" end
  if ctrl and #bytes == 1 then
    local b = bytes:lower():byte()
    if b >= 97 and b <= 122 then bytes = string.char(b - 96)
    elseif bytes == " " or bytes == "@" then bytes = "\0"
    elseif bytes == "[" then bytes = ESC
    elseif bytes == "\\" then bytes = "\28"
    elseif bytes == "]" then bytes = "\29" end
  end
  if alt then bytes = ESC .. bytes end
  return bytes
end

-- A list of herdr key names → one string of bytes.
function M.encode_all(keys)
  local out = {}
  for _, key in ipairs(keys or {}) do out[#out + 1] = M.encode(key) or key end
  return table.concat(out)
end

return M
