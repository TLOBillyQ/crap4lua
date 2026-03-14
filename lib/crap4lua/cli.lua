local common = require("crap4lua.common")
local config = require("crap4lua.config")
local report = require("crap4lua.report")
local viewer = require("crap4lua.viewer")

local cli = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _print_migration_notice()
  io.stderr:write("[crap] NOTE: The Lua CLI is deprecated. Use `crap4lua-go` instead:\n")
  io.stderr:write("[crap]   ./bin/crap4lua-go report --config <file> ...\n")
  io.stderr:write("[crap]   ./bin/crap4lua-go viewer --in-json <file> ...\n")
  io.stderr:write("[crap] See docs/migration.md for details.\n\n")
end

local function _usage(command_name)
  local command = tostring(command_name or "bin/crap4lua.lua")
  io.write(_text("用法", "Usage") .. ":\n")
  io.write("  <lua> " .. command .. " report [--config <file>] [--mode <name>] [--lane <name>] [--out <file>] [--top <n>] [--strict-tests] [--project-root <dir>]\n")
  io.write("  <lua> " .. command .. " viewer [--config <file>] [--out-dir <dir>] [--in-json <file>] [--open]\n")
  io.write("  <lua> " .. command .. " --help\n")
  io.write("\n")
  io.write("NOTE: The Lua CLI is deprecated. Please migrate to `crap4lua-go`.\n")
  io.write("  ./bin/crap4lua-go report --config <file> ...\n")
  io.write("  See docs/migration.md\n")
end

local function _parse_top(value)
  if value == nil then
    return 20
  end
  local numeric = common.to_integer(value) or 20
  if numeric < 1 then
    return 1
  end
  return numeric
end

local function _parse_args(args)
  local options = {
    command = args[1],
    config = nil,
    mode = nil,
    lanes = {},
    out = nil,
    out_dir = nil,
    in_json = nil,
    top = 20,
    strict_tests = false,
    open = false,
    project_root = nil,
  }
  local index = 2
  while index <= #args do
    local token = args[index]
    if token == "--config" then
      options.config = args[index + 1]
      index = index + 2
    elseif token == "--mode" then
      options.mode = args[index + 1]
      index = index + 2
    elseif token == "--lane" then
      options.lanes[#options.lanes + 1] = args[index + 1]
      index = index + 2
    elseif token == "--out" then
      options.out = args[index + 1]
      index = index + 2
    elseif token == "--out-dir" then
      options.out_dir = args[index + 1]
      index = index + 2
    elseif token == "--in-json" then
      options.in_json = args[index + 1]
      index = index + 2
    elseif token == "--top" then
      options.top = _parse_top(args[index + 1])
      index = index + 2
    elseif token == "--strict-tests" then
      options.strict_tests = true
      index = index + 1
    elseif token == "--open" then
      options.open = true
      index = index + 1
    elseif token == "--project-root" then
      options.project_root = args[index + 1]
      index = index + 2
    else
      error(_text(
        "未知参数: " .. tostring(token),
        "Unknown flag: " .. tostring(token)
      ))
    end
  end
  return options
end

local function _resolve_paths(options)
  local cwd = common.current_dir()
  local resolve_cli_path = common.resolve_cli_path
  return {
    cwd = cwd,
    project_root = options.project_root and resolve_cli_path(cwd, options.project_root) or nil,
    out_path = options.out and resolve_cli_path(cwd, options.out) or nil,
    out_dir = options.out_dir and resolve_cli_path(cwd, options.out_dir)
      or (options.command == "viewer" and resolve_cli_path(cwd, "tmp/crap_view") or nil),
    in_json = options.in_json and resolve_cli_path(cwd, options.in_json) or nil,
  }
end

local function _load_runtime_config(options, env)
  local loader = env.load_config or config.load
  local loaded, err = loader(options.config, env)
  if loaded == nil then
    error(err .. "\nuse --config <file> or add crap4lua.config.lua in the working directory")
  end
  return loaded
end

local function _active_lanes(options, runtime_config)
  if #options.lanes > 0 then
    return options.lanes
  end
  return runtime_config.coverage.lanes
end

local function _build_report_opts(options, paths, runtime_config)
  return {
    project_root = paths.project_root or runtime_config.project_root,
    project_name = runtime_config.project_name,
    source_roots = runtime_config.source_roots,
    out_path = paths.out_path,
    top = options.top or 20,
    strict_tests = options.strict_tests,
    coverage = {
      adapter = runtime_config.coverage.adapter,
      lanes = _active_lanes(options, runtime_config),
      mode = options.mode or runtime_config.coverage.mode,
      collect = runtime_config.coverage.collect,
    },
  }
end

local function _run_report(options, env)
  local paths = _resolve_paths(options)
  local runtime_config = _load_runtime_config(options, env)
  local runner = env.run_report or report.build
  local result, err = runner(_build_report_opts(options, paths, runtime_config))
  if result == nil then
    error(err)
  end
  if result.exit_code and result.exit_code ~= 0 then
    local exit = env.exit or os.exit
    exit(result.exit_code)
  end
  return true
end

local function _run_viewer(options, env)
  local paths = _resolve_paths(options)
  if paths.out_dir == nil then
    error("viewer requires --out-dir <dir>")
  end

  local view_report = nil
  if paths.in_json ~= nil then
    local loader = env.load_report or viewer.load_report
    local loaded_report, load_err = loader(paths.in_json)
    if loaded_report == nil then
      error(
        _text(
          "viewer input json not found or unreadable: ",
          "viewer input json not found or unreadable: "
        ) .. tostring(paths.in_json)
          .. (load_err and ("\n" .. _text("loader error: ", "loader error: ") .. tostring(load_err)) or "")
      )
    end
    view_report = loaded_report
  else
    local runtime_config = _load_runtime_config(options, env)
    local runner = env.run_report or report.build
    local built_report, build_err = runner(_build_report_opts(options, paths, runtime_config))
    if built_report == nil then
      error(build_err)
    end
    view_report = built_report
  end

  local writer = env.write_viewer or viewer.write
  local ok, err = writer({
    out_dir = paths.out_dir,
  }, view_report, {
    open = options.open,
  })
  if not ok then
    error(err)
  end
  return true
end

function cli.run(args, env)
  env = env or {}
  _print_migration_notice()
  local options = _parse_args(args or {})
  if options.command == "--help" or options.command == "-h" then
    _usage(env.command_name)
    return true
  end
  if options.command == nil then
    _usage(env.command_name)
    return true
  end
  if options.command == "report" then
    return _run_report(options, env)
  end
  if options.command == "viewer" then
    return _run_viewer(options, env)
  end
  _usage(env.command_name)
  error(_text(
    "未知命令: " .. tostring(options.command),
    "Unknown command: " .. tostring(options.command)
  ))
end

return cli
