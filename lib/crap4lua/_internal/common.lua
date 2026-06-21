local common = {}

local function _normalize_slashes(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _is_windows_path(path)
  return tostring(path or ""):match("^%a:[/\\]") ~= nil
end

local function _is_absolute(path)
  path = tostring(path or "")
  return path:sub(1, 1) == "/" or path:sub(1, 2) == "\\\\" or _is_windows_path(path)
end

local function _shell_quote(value)
  value = tostring(value or "")
  if value:find("%z") then
    error("refusing to quote path containing NUL")
  end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function _is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function _windows_path(path)
  return tostring(path or ""):gsub("/", "\\")
end

local function _cmd_quote(value)
  local text = _windows_path(value)
  return '"' .. text:gsub('"', '""') .. '"'
end

local function _execute_success(ok, code)
  return ok == true or ok == 0 or code == 0
end

local function _capture(command)
  local handle, err = io.popen(command, "r")
  if handle == nil then
    return nil, err
  end
  local output = handle:read("*a") or ""
  local ok = handle:close()
  if ok == nil then
    return nil, output
  end
  return output
end

function common.normalize_path(path)
  local normalized = _normalize_slashes(path)
  local prefix = ""
  if normalized:match("^%a:/") then
    prefix = normalized:sub(1, 3)
    normalized = normalized:sub(4)
  elseif normalized:sub(1, 1) == "/" then
    prefix = "/"
    normalized = normalized:sub(2)
  end

  local parts = {}
  for part in normalized:gmatch("[^/]+") do
    if part == "." or part == "" then
      -- skip
    elseif part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      parts[#parts] = nil
    elseif part == ".." and prefix ~= "" then
      -- stay at filesystem root
    else
      parts[#parts + 1] = part
    end
  end

  local joined = table.concat(parts, "/")
  if prefix == "" then
    return joined == "" and "." or joined
  end
  return joined == "" and prefix:gsub("/$", "") or (prefix .. joined)
end

function common.join_path(...)
  local result = ""
  for index = 1, select("#", ...) do
    local part = tostring(select(index, ...) or "")
    if part ~= "" then
      if result == "" then
        result = part
      elseif result:sub(-1) == "/" then
        result = result .. part:gsub("^/+", "")
      else
        result = result .. "/" .. part:gsub("^/+", "")
      end
    end
  end
  return common.normalize_path(result)
end

function common.current_dir()
  local pwd = os.getenv("PWD")
  if pwd and pwd ~= "" then
    return common.normalize_path(pwd)
  end
  local output = assert(_capture("pwd"))
  return common.normalize_path((output:gsub("%s+$", "")))
end

function common.resolve_path(base, path)
  path = tostring(path or "")
  if path == "" then
    return common.normalize_path(base)
  end
  if _is_absolute(path) then
    return common.normalize_path(path)
  end
  return common.join_path(base, path)
end

function common.resolve_cli_path(base, path)
  return common.resolve_path(base, path)
end

function common.parent_dir(path)
  local normalized = common.normalize_path(path):gsub("/+$", "")
  local parent = normalized:match("^(.*)/[^/]+$")
  if parent == nil or parent == "" then
    return "."
  end
  return parent
end

function common.basename(path)
  return common.normalize_path(path):match("([^/]+)$") or tostring(path or "")
end

function common.system_tmp_dir()
  return common.normalize_path(os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp")
end

function common.make_temp_path(prefix, suffix)
  local name = tostring(prefix or "crap4lua_tmp") .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000000, 9999999))
  return common.join_path(common.system_tmp_dir(), name .. tostring(suffix or ""))
end

function common.shell_quote(value)
  return _shell_quote(value)
end

function common.path_exists(path)
  if _is_windows() then
    local quoted = _cmd_quote(path)
    local ok, _, code = os.execute("if exist " .. quoted .. " (exit /b 0) else (exit /b 1)")
    return _execute_success(ok, code)
  end
  local ok = os.execute("test -e " .. _shell_quote(path) .. " >/dev/null 2>&1")
  return _execute_success(ok)
end

function common.command_exists(command_name)
  if _is_windows() then
    local ok, _, code = os.execute("where.exe " .. _cmd_quote(command_name) .. " >nul 2>nul")
    return _execute_success(ok, code)
  end
  local ok = os.execute("command -v " .. _shell_quote(command_name) .. " >/dev/null 2>&1")
  return _execute_success(ok)
end

function common.ensure_dir(path)
  if _is_windows() then
    local quoted = _cmd_quote(path)
    local ok, _, code = os.execute("if not exist " .. quoted .. " mkdir " .. quoted)
    if _execute_success(ok, code) then
      return true
    end
    return nil, "cannot create directory: " .. tostring(path)
  end
  local ok = os.execute("mkdir -p " .. _shell_quote(path))
  if _execute_success(ok) then
    return true
  end
  return nil, "cannot create directory: " .. tostring(path)
end

function common.ensure_parent_dir(path)
  return common.ensure_dir(common.parent_dir(path))
end

function common.read_file(path)
  local handle, err = io.open(path, "rb")
  if handle == nil then
    return nil, err
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

function common.write_file(path, content)
  local ok, err = common.ensure_parent_dir(path)
  if not ok then
    return nil, err
  end
  local handle, open_err = io.open(path, "wb")
  if handle == nil then
    return nil, open_err
  end
  handle:write(tostring(content or ""))
  handle:close()
  return true
end

function common.remove_path(path)
  if path == nil or path == "" then
    return true
  end
  if _is_windows() then
    local quoted = _cmd_quote(path)
    local dir_marker = _cmd_quote(_windows_path(path) .. "\\NUL")
    local command = "if exist " .. dir_marker .. " (rmdir /s /q " .. quoted .. ") else if exist "
      .. quoted .. " (del /f /q " .. quoted .. ")"
    local ok, _, code = os.execute(command)
    if _execute_success(ok, code) then
      return true
    end
    return nil, "cannot remove path: " .. tostring(path)
  end
  local ok = os.execute("rm -rf " .. _shell_quote(path))
  if _execute_success(ok) then
    return true
  end
  return nil, "cannot remove path: " .. tostring(path)
end

function common.copy_tree(source_path, target_path)
  common.remove_path(target_path)
  local ok = os.execute("cp -R " .. _shell_quote(source_path) .. " " .. _shell_quote(target_path))
  if ok == true or ok == 0 then
    return true
  end
  return nil, "cannot copy tree: " .. tostring(source_path)
end

function common.open_path(path)
  local opener = "xdg-open"
  if package.config:sub(1, 1) == "\\" then
    opener = "start"
  elseif common.command_exists("open") then
    opener = "open"
  end
  local ok = os.execute(opener .. " " .. _shell_quote(path) .. " >/dev/null 2>&1")
  if ok == true or ok == 0 then
    return true
  end
  return nil, "cannot open path: " .. tostring(path)
end

function common.collect_files(root, extension)
  if not common.path_exists(root) then
    return {}, nil
  end
  if _is_windows() then
    local pattern = "*"
    if extension ~= nil and extension ~= "" then
      pattern = "*" .. tostring(extension):gsub('"', "")
    end
    local command = "dir /s /b /a:-d " .. _cmd_quote(common.join_path(root, pattern)) .. " 2>nul"
    local output, err = _capture(command)
    if output == nil then
      return nil, err
    end
    local files = {}
    for line in output:gmatch("[^\r\n]+") do
      files[#files + 1] = common.normalize_path(line)
    end
    table.sort(files)
    return files
  end
  local command = "find " .. _shell_quote(root) .. " -type f"
  if extension ~= nil and extension ~= "" then
    command = command .. " -name '*" .. tostring(extension):gsub("'", "") .. "'"
  end
  local output, err = _capture(command)
  if output == nil then
    return nil, err
  end
  local files = {}
  for line in output:gmatch("[^\r\n]+") do
    files[#files + 1] = common.normalize_path(line)
  end
  table.sort(files)
  return files
end

function common.sorted_keys(values)
  local keys = {}
  for key in pairs(values or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function common.sorted_pairs(values)
  local keys = common.sorted_keys(values)
  local index = 0
  return function()
    index = index + 1
    local key = keys[index]
    if key ~= nil then
      return key, values[key]
    end
  end
end

function common.to_integer(value)
  local number = tonumber(value)
  if number == nil or number ~= math.floor(number) then
    return nil
  end
  return number
end

function common.is_numeric(value)
  return type(value) == "number" or tonumber(value) ~= nil
end

function common.relative_to(base, source)
  local normalized_base = common.normalize_path(base):gsub("/+$", "") .. "/"
  local normalized_source = common.normalize_path(tostring(source or ""):gsub("^@", ""))
  if normalized_source:sub(1, #normalized_base) == normalized_base then
    return normalized_source:sub(#normalized_base + 1)
  end
  return normalized_source
end

return common
