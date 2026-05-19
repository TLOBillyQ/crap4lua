local common = require("crap4lua._internal.common")

local json_writer = {}

local function _escape_string(value)
  local escaped = tostring(value or "")
  escaped = escaped:gsub("\\", "\\\\")
  escaped = escaped:gsub("\"", "\\\"")
  escaped = escaped:gsub("\r", "\\r")
  escaped = escaped:gsub("\n", "\\n")
  escaped = escaped:gsub("\t", "\\t")
  return escaped
end

local function _is_array(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    local integer = common.to_integer(key)
    if integer == nil or integer ~= key or integer < 1 then
      return false
    end
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

local function _encode(value)
  local value_type = type(value)
  if value == nil then
    return "null"
  end
  if value_type == "string" then
    return "\"" .. _escape_string(value) .. "\""
  end
  if value_type == "boolean" or value_type == "number" then
    return tostring(value)
  end
  if value_type ~= "table" then
    return "\"" .. _escape_string(value) .. "\""
  end

  if _is_array(value) then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = _encode(item)
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local fields = {}
  for key, field_value in common.sorted_pairs(value) do
    fields[#fields + 1] = "\"" .. _escape_string(key) .. "\":" .. _encode(field_value)
  end
  return "{" .. table.concat(fields, ",") .. "}"
end

function json_writer.encode(value)
  return _encode(value)
end

return json_writer
