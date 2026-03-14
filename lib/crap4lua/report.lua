local common = require("crap4lua.common")
local coverage = require("crap4lua.coverage")
local engine = require("crap4lua.engine")

local report = {}

local function _default_project_name(project_root)
  local normalized = common.normalize_path(project_root)
  return normalized:match("([^/]+)/?$") or "project"
end

local function _resolve_coverage_result(opts, project_root)
  if opts.coverage_result ~= nil then
    return opts.coverage_result
  end

  local coverage_opts = opts.coverage
  if type(coverage_opts) ~= "table" then
    return nil, "report.build requires coverage_result or coverage = { adapter = ..., lanes = ... }"
  end

  local tracked_sources = coverage_opts.tracked_sources or {}
  local collector = coverage_opts.collect or coverage.collect
  local ok, result = xpcall(function()
    return collector({
      project_root = project_root,
      tracked_sources = tracked_sources,
      source_roots = opts.source_roots,
      lanes = coverage_opts.lanes,
      mode = coverage_opts.mode,
      adapter = coverage_opts.adapter,
    })
  end, debug.traceback)
  if not ok then
    return nil, result
  end
  return result
end

function report.build(opts)
  opts = opts or {}
  if type(opts.source_roots) ~= "table" or #opts.source_roots == 0 then
    return nil, "report.build requires source_roots = { ... }"
  end

  local project_root = common.resolve_path(common.current_dir(), opts.project_root or common.current_dir())
  local coverage_result, coverage_err = _resolve_coverage_result(opts, project_root)
  if coverage_result == nil then
    return nil, coverage_err
  end

  local result, raw_json, engine_err = engine.run_report({
    project_root = project_root,
    project_name = opts.project_name or _default_project_name(project_root),
    source_roots = opts.source_roots,
    coverage_result = coverage_result,
    top = opts.top or 20,
    strict_tests = opts.strict_tests == true,
  }, opts.engine_env)
  if result == nil then
    return nil, engine_err
  end

  if opts.out_path ~= nil then
    local ok, mkdir_err = common.ensure_parent_dir(opts.out_path)
    if not ok then
      return nil, mkdir_err
    end
    local write_ok, write_err = common.write_file(opts.out_path, raw_json)
    if not write_ok then
      return nil, write_err
    end
    print("[crap] wrote_json=" .. tostring(opts.out_path))
  end

  result.exit_code = result.exit_code or 0
  return result
end

return report
