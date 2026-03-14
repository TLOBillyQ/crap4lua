local common = require("crap4lua.common")
local json_reader = require("crap4lua.json_reader")
local json_writer = require("crap4lua.json_writer")

local engine = {}

local function _source_path()
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return common.normalize_path(source)
end

local function _repo_root()
  local module_dir = common.parent_dir(_source_path()) or "."
  local absolute_module_dir = common.resolve_path(common.current_dir(), module_dir)
  return common.resolve_path(absolute_module_dir, "../..")
end

local function _binary_name()
  if common.is_windows() then
    return "crap4lua-go.exe"
  end
  return "crap4lua-go"
end

local function _default_binary_path()
  return common.join_path(_repo_root(), "bin/" .. _binary_name())
end

local function _replay_output(output)
  local text = tostring(output or "")
  if text == "" then
    return
  end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      print(line)
    end
  end
end

local function _build_binary(binary_path)
  if not common.command_exists("go") then
    return nil, "crap4lua Go engine is missing and `go` is not available; build it with `go build -o "
      .. tostring(binary_path) .. " ./cmd/crap4lua-go`"
  end
  local ok, err = common.ensure_parent_dir(binary_path)
  if not ok then
    return nil, err
  end
  local result = common.run_command({
    "go", "build", "-o", binary_path, "./cmd/crap4lua-go",
  }, {
    cwd = _repo_root(),
  })
  if result.ok ~= true then
    return nil, "failed to build crap4lua Go engine\n" .. tostring(result.output or "")
  end
  return binary_path
end

function engine.resolve_binary(env)
  env = env or {}
  local explicit = env.engine_binary or os.getenv("CRAP4LUA_GO_BIN")
  if explicit ~= nil and explicit ~= "" then
    local resolved = common.resolve_path(common.current_dir(), explicit)
    if common.path_exists(resolved) then
      return resolved
    end
    return _build_binary(resolved)
  end

  local default_path = env.default_engine_binary or _default_binary_path()
  if common.path_exists(default_path) then
    return default_path
  end
  return _build_binary(default_path)
end

local function _run_binary(args, env)
  local binary_path, binary_err = engine.resolve_binary(env)
  if binary_path == nil then
    return nil, binary_err
  end
  local command = { binary_path }
  for _, value in ipairs(args or {}) do
    command[#command + 1] = value
  end
  local result = common.run_command(command, {
    cwd = env and env.cwd or _repo_root(),
  })
  if result.ok ~= true then
    local output = tostring(result.output or "")
    if output ~= "" then
      return nil, output
    end
    return nil, "crap4lua Go engine command failed"
  end
  _replay_output(result.output)
  return true
end

function engine.run_report(request, env)
  local request_path = common.make_temp_path("crap4lua_request", ".json")
  local response_path = common.make_temp_path("crap4lua_response", ".json")

  local ok, err = common.write_file(request_path, json_writer.encode(request))
  if not ok then
    return nil, nil, err
  end

  local command_ok, command_err = _run_binary({
    "report",
    "--request-json", request_path,
    "--response-json", response_path,
  }, env)
  if not command_ok then
    common.remove_path(request_path)
    common.remove_path(response_path)
    return nil, nil, command_err
  end

  local raw_json, read_err = common.read_file(response_path)
  common.remove_path(request_path)
  common.remove_path(response_path)
  if raw_json == nil then
    return nil, nil, read_err
  end
  return json_reader.decode(raw_json), raw_json, nil
end

function engine.run_viewer(in_json, out_dir, opts, env)
  local args = {
    "viewer",
    "--in-json", in_json,
    "--out-dir", out_dir,
  }
  if opts and opts.open then
    args[#args + 1] = "--open"
  end
  return _run_binary(args, env)
end

function engine.default_binary_path()
  return _default_binary_path()
end

return engine
