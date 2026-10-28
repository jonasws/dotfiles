-- Minimal JSON for the harness (rex.json stand-in).
local M = {}
local function esc(s) return (s:gsub('[%c"\\]', function(c)
  local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
  return map[c] or string.format('\\u%04x', c:byte()) end)) end
local function is_array(t)
  local n = 0
  for k in pairs(t) do if type(k) ~= 'number' then return false end n = n + 1 end
  return n > 0 and n == #t
end
function M.encode(v)
  local t = type(v)
  if v == nil then return 'null' end
  if t == 'boolean' then return tostring(v) end
  if t == 'number' then return (v == math.floor(v) and string.format('%d', v)) or tostring(v) end
  if t == 'string' then return '"' .. esc(v) .. '"' end
  if t == 'table' then
    local out = {}
    if is_array(v) then
      for _, x in ipairs(v) do out[#out + 1] = M.encode(x) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local x = v[k]; if x == nil then x = v[tonumber(k)] end
      if type(x) ~= 'function' then out[#out + 1] = '"' .. esc(k) .. '":' .. M.encode(x) end
    end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end
function M.decode(s)
  local i = 1
  local function ws() i = s:find('[^ \t\r\n]', i) or #s + 1 end
  local value
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then i = j + 1; return table.concat(out) end
      if c == '\\' then
        local n = s:sub(j + 1, j + 1)
        local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f', ['/'] = '/', ['\\'] = '\\', ['"'] = '"' }
        if n == 'u' then
          local code = tonumber(s:sub(j + 2, j + 5), 16)
          if code < 128 then out[#out + 1] = string.char(code)
          elseif code < 2048 then out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + code % 64)
          else out[#out + 1] = string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64) end
          j = j + 6
        else out[#out + 1] = map[n] or n; j = j + 2 end
      else out[#out + 1] = c; j = j + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == '{' then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == '}' then i = i + 1; return t end
      while true do
        ws(); local k = str(); ws(); i = i + 1
        t[k] = value(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == '}' then return t end
      end
    elseif c == '[' then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == ']' then i = i + 1; return t end
      while true do
        local v = value(); if v ~= nil then t[#t + 1] = v end; ws()
        local d = s:sub(i, i); i = i + 1
        if d == ']' then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == 'true' then i = i + 4; return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5; return false
    elseif s:sub(i, i + 3) == 'null' then i = i + 4; return nil
    else
      local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i); i = i + #num; return tonumber(num)
    end
  end
  local ok, v = pcall(value)
  if ok then return v end
  return nil, v
end
return M
