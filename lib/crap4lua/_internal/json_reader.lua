-- Minimal self-contained JSON decoder (decode-only counterpart of
-- json_writer). Lua 5.1+ compatible: no external dependencies.
local json_reader = {}

local function _decode_error(message, position)
  error("json decode: " .. message .. " at byte " .. tostring(position), 0)
end

local function _skip_ws(text, index)
  local _, last = text:find("^[ \t\r\n]*", index)
  return (last or index - 1) + 1
end

local function _utf8_encode(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    return string.char(
      0xC0 + math.floor(codepoint / 0x40),
      0x80 + codepoint % 0x40)
  elseif codepoint < 0x10000 then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + math.floor(codepoint / 0x40) % 0x40,
      0x80 + codepoint % 0x40)
  end
  return string.char(
    0xF0 + math.floor(codepoint / 0x40000),
    0x80 + math.floor(codepoint / 0x1000) % 0x40,
    0x80 + math.floor(codepoint / 0x40) % 0x40,
    0x80 + codepoint % 0x40)
end

local _parse_value

local _ESCAPES = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
  b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function _parse_hex4(text, index)
  local code = tonumber(text:sub(index, index + 3), 16)
  if code == nil or #text:sub(index, index + 3) < 4 then
    _decode_error("invalid \\u escape", index)
  end
  return code
end

local function _parse_string(text, index)
  local parts = {}
  index = index + 1
  while true do
    local char = text:sub(index, index)
    if char == "" then
      _decode_error("unterminated string", index)
    elseif char == '"' then
      return table.concat(parts), index + 1
    elseif char == "\\" then
      local escape = text:sub(index + 1, index + 1)
      if escape == "u" then
        local codepoint = _parse_hex4(text, index + 2)
        index = index + 6
        -- combine UTF-16 surrogate pairs
        if codepoint >= 0xD800 and codepoint <= 0xDBFF
            and text:sub(index, index + 1) == "\\u" then
          local low = _parse_hex4(text, index + 2)
          if low >= 0xDC00 and low <= 0xDFFF then
            codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
            index = index + 6
          end
        end
        parts[#parts + 1] = _utf8_encode(codepoint)
      else
        local replacement = _ESCAPES[escape]
        if replacement == nil then
          _decode_error("invalid escape \\" .. escape, index)
        end
        parts[#parts + 1] = replacement
        index = index + 2
      end
    else
      parts[#parts + 1] = char
      index = index + 1
    end
  end
end

local function _parse_number(text, index)
  local literal = text:match("^%-?%d+%.?%d*[eE]?[+%-]?%d*", index)
  local value = tonumber(literal)
  if value == nil then
    _decode_error("invalid number", index)
  end
  return value, index + #literal
end

local function _parse_array(text, index)
  local array = {}
  index = _skip_ws(text, index + 1)
  if text:sub(index, index) == "]" then
    return array, index + 1
  end
  while true do
    local value
    value, index = _parse_value(text, index)
    array[#array + 1] = value
    index = _skip_ws(text, index)
    local char = text:sub(index, index)
    if char == "," then
      index = _skip_ws(text, index + 1)
    elseif char == "]" then
      return array, index + 1
    else
      _decode_error("expected ',' or ']'", index)
    end
  end
end

local function _parse_object(text, index)
  local object = {}
  index = _skip_ws(text, index + 1)
  if text:sub(index, index) == "}" then
    return object, index + 1
  end
  while true do
    if text:sub(index, index) ~= '"' then
      _decode_error("expected string key", index)
    end
    local key
    key, index = _parse_string(text, index)
    index = _skip_ws(text, index)
    if text:sub(index, index) ~= ":" then
      _decode_error("expected ':'", index)
    end
    local value
    value, index = _parse_value(text, _skip_ws(text, index + 1))
    object[key] = value
    index = _skip_ws(text, index)
    local char = text:sub(index, index)
    if char == "," then
      index = _skip_ws(text, index + 1)
    elseif char == "}" then
      return object, index + 1
    else
      _decode_error("expected ',' or '}'", index)
    end
  end
end

_parse_value = function(text, index)
  index = _skip_ws(text, index)
  local char = text:sub(index, index)
  if char == '"' then
    return _parse_string(text, index)
  elseif char == "[" then
    return _parse_array(text, index)
  elseif char == "{" then
    return _parse_object(text, index)
  elseif text:sub(index, index + 3) == "true" then
    return true, index + 4
  elseif text:sub(index, index + 4) == "false" then
    return false, index + 5
  elseif text:sub(index, index + 3) == "null" then
    return nil, index + 4
  end
  return _parse_number(text, index)
end

-- Decodes JSON text into Lua values. Raises an error on malformed input
-- (callers typically wrap with pcall). JSON null decodes to nil.
function json_reader.decode(text)
  text = tostring(text or "")
  local value, index = _parse_value(text, 1)
  index = _skip_ws(text, index)
  if index <= #text then
    _decode_error("trailing data", index)
  end
  return value
end

return json_reader
