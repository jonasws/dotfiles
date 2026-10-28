-- Just enough TOML for herdr-plugin.toml: top-level keys, [table] and
-- [[array of tables]] headers, and string, number, boolean and string-array
-- values (arrays may span lines). Comments and blank lines are skipped.

local M = {}

local function unquote(s)
  local q = s:sub(1, 1)
  if q == '"' then
    s = s:sub(2, -2)
    return (s:gsub('\\(.)', { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }))
  elseif q == "'" then
    return s:sub(2, -2)
  end
  return s
end

local function strip_comment(line)
  local out, quote = {}, nil
  for i = 1, #line do
    local c = line:sub(i, i)
    if quote then
      if c == quote and line:sub(i - 1, i - 1) ~= "\\" then quote = nil end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "#" then
      break
    end
    out[#out + 1] = c
  end
  return table.concat(out)
end

local function value(raw)
  raw = raw:match("^%s*(.-)%s*$")
  if raw:sub(1, 1) == "[" then
    local list = {}
    for item in raw:sub(2, -2):gmatch('%s*("[^"]*"%s*)') do list[#list + 1] = unquote(item:match("^%s*(.-)%s*$")) end
    if #list == 0 then
      for item in raw:sub(2, -2):gmatch("%s*('[^']*'%s*)") do list[#list + 1] = unquote(item:match("^%s*(.-)%s*$")) end
    end
    return list
  end
  if raw == "true" then return true end
  if raw == "false" then return false end
  if tonumber(raw) then return tonumber(raw) end
  return unquote(raw)
end

function M.parse(text)
  local root, current = {}, nil
  current = root
  local pending_key, pending = nil, nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = strip_comment(line)
    if pending_key then
      pending = pending .. " " .. line
      if line:find("]") then
        current[pending_key] = value(pending)
        pending_key = nil
      end
    else
      local array_header = line:match("^%s*%[%[%s*([%w_.%-]+)%s*%]%]")
      local table_header = not array_header and line:match("^%s*%[%s*([%w_.%-]+)%s*%]")
      if array_header then
        root[array_header] = root[array_header] or {}
        current = {}
        table.insert(root[array_header], current)
      elseif table_header then
        root[table_header] = root[table_header] or {}
        current = root[table_header]
      else
        local key, raw = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        if key then
          if raw:sub(1, 1) == "[" and not raw:find("]") then
            pending_key, pending = key, raw
          else
            current[key] = value(raw)
          end
        end
      end
    end
  end
  return root
end

return M
