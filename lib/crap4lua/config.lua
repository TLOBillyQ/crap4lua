local common = require("crap4lua.common")

local config = {}

local function _load_lua_table(path)
  local chunk, load_err = loadfile(path)
  if chunk == nil then
    return nil, load_err
  end

  local ok, result = xpcall(chunk, debug.traceback)
  if not ok then
    return nil, result
  end
  if type(result) ~= "table" then
    return nil, "crap4lua config must return a table: " .. tostring(path)
  end
  return result
end

local function _default_project_name(project_root)
  local normalized = common.normalize_path(project_root)
  local name = normalized:match("([^/]+)/?$")
  if name == nil or name == "" then
    return "project"
  end
  return name
end

local function _normalize_source_roots(source_roots)
  if type(source_roots) ~= "table" or #source_roots == 0 then
    return nil, "crap4lua config requires source_roots = { ... }"
  end

  local normalized = {}
  for _, root in ipairs(source_roots) do
    local value = common.normalize_path(root)
    value = value:gsub("^%./", "")
    if value ~= "" then
      normalized[#normalized + 1] = value
    end
  end
  if #normalized == 0 then
    return nil, "crap4lua config source_roots cannot be empty"
  end
  return normalized
end

local function _resolve_adapter(adapter, config_dir)
  if adapter == nil then
    return nil
  end
  local value = adapter
  if type(value) == "string" then
    local adapter_path = common.resolve_path(config_dir, value)
    local loaded, load_err = _load_lua_table(adapter_path)
    if loaded == nil then
      return nil, "failed to load coverage adapter: " .. tostring(load_err)
    end
    value = loaded
  end
  if type(value) == "function" then
    value = value()
  end
  if type(value) ~= "table" then
    return nil, "coverage adapter must resolve to a table"
  end
  return value
end

function config.load(path, env)
  env = env or {}
  local cwd = common.current_dir()
  local default_path = env.default_config_path or "crap4lua.config.lua"
  local config_path = common.resolve_cli_path(cwd, path or default_path)
  if not common.path_exists(config_path) then
    return nil, "crap4lua config not found: " .. tostring(config_path)
  end

  local raw, load_err = _load_lua_table(config_path)
  if raw == nil then
    return nil, load_err
  end

  local config_dir = common.parent_dir(config_path) or cwd
  local source_roots, roots_err = _normalize_source_roots(raw.source_roots)
  if source_roots == nil then
    return nil, roots_err
  end

  local coverage = raw.coverage or {}
  if type(coverage) ~= "table" then
    return nil, "crap4lua config coverage must be a table"
  end

  local adapter, adapter_err = _resolve_adapter(coverage.adapter, config_dir)
  if coverage.adapter ~= nil and adapter == nil then
    return nil, adapter_err
  end

  local lanes = coverage.lanes
  if type(lanes) ~= "table" or #lanes == 0 then
    lanes = { "default" }
  end

  local project_root = common.resolve_path(config_dir, raw.project_root or ".")

  return {
    config_path = config_path,
    config_dir = config_dir,
    project_root = project_root,
    project_name = raw.project_name or _default_project_name(project_root),
    source_roots = source_roots,
    coverage = {
      adapter = adapter,
      lanes = lanes,
      mode = coverage.mode,
      collect = coverage.collect,
    },
  }
end

return config
