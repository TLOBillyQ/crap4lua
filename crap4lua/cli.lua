local common = require("crap4lua.common")
local report = require("crap4lua.report")
local viewer = require("crap4lua.viewer")

local cli = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _usage()
  io.write(_text("用法", "Usage") .. ":\n")
  io.write("  <lua> bin/crap4lua.lua report [--mode <auto|dev|release_trimmed>] [--lane <behavior|contract>] [--out <file>] [--top <n>] [--strict-tests]\n")
  io.write("  <lua> bin/crap4lua.lua viewer [--out-dir <dir>] [--in-json <file>] [--open]\n")
  io.write("  <lua> bin/crap4lua.lua\n")
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
    if token == "--mode" then
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
  if #options.lanes == 0 then
    options.lanes[1] = "behavior"
  end
  return options
end

local function _resolve_paths(options, env)
  local cwd = common.current_dir()
  local resolve_cli_path = env.resolve_cli_path or common.resolve_cli_path
  local module_root = common.normalize_path(env.module_root or cwd)
  local asset_root = common.normalize_path(env.asset_root or common.join_path(module_root, "viewer"))
  local default_project_root = env.default_project_root or cwd
  return {
    module_root = module_root,
    asset_root = asset_root,
    project_root = resolve_cli_path(cwd, options.project_root or default_project_root),
    out_path = options.out and resolve_cli_path(cwd, options.out) or nil,
    out_dir = options.out_dir and resolve_cli_path(cwd, options.out_dir)
      or (options.command == "viewer" and resolve_cli_path(cwd, "tmp/crap_view") or nil),
    in_json = options.in_json and resolve_cli_path(cwd, options.in_json) or nil,
  }
end

local function _build_report_opts(options, paths, env)
  return {
    project_root = paths.project_root,
    lanes = options.lanes,
    mode = options.mode,
    out_path = paths.out_path,
    top = options.top or 20,
    strict_tests = options.strict_tests,
    resolve_lane_suites = env.resolve_lane_suites,
    run_all = env.run_all,
    debug_api = env.debug_api,
    collect_coverage = env.collect_coverage,
  }
end

local function _run_report(options, env)
  local paths = _resolve_paths(options, env)
  local runner = env.run_report or report.build
  local result, err = runner(_build_report_opts(options, paths, env))
  if result == nil then
    error(err)
  end
  if result.exit_code and result.exit_code ~= 0 then
    os.exit(result.exit_code)
  end
  return true
end

local function _run_viewer(options, env)
  local paths = _resolve_paths(options, env)
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
          .. "\n" .. _text(
            "run `lua bin/crap4lua.lua report --out ",
            "run `lua bin/crap4lua.lua report --out "
          )
          .. tostring(paths.in_json)
          .. _text("` first, or omit `--in-json` to generate the report on demand", "` first, or omit `--in-json` to generate the report on demand")
          .. (load_err and ("\n" .. _text("loader error: ", "loader error: ") .. tostring(load_err)) or "")
      )
    end
    view_report = loaded_report
  else
    local runner = env.run_report or report.build
    view_report = assert(runner(_build_report_opts(options, paths, env)))
  end
  local writer = env.write_viewer or viewer.write
  local ok, err = writer({
    asset_root = paths.asset_root,
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
  local options = _parse_args(args or {})
  if options.command == "--help" or options.command == "-h" then
    _usage()
    return true
  end
  if options.command == nil then
    options.command = "viewer"
    options.open = true
  end
  if options.command == "report" then
    return _run_report(options, env)
  end
  if options.command == "viewer" then
    return _run_viewer(options, env)
  end
  _usage()
  error(_text(
    "未知命令: " .. tostring(options.command),
    "Unknown command: " .. tostring(options.command)
  ))
end

return cli
