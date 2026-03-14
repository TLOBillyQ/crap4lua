local common = require("crap4lua.common")
local coverage = require("crap4lua.coverage")
local json_writer = require("crap4lua.json_writer")
local luac_listing = require("crap4lua.luac_listing")
local source_scan = require("crap4lua.source_scan")

local report = {}

local function _count_map_keys(map)
  local count = 0
  for _ in pairs(map or {}) do
    count = count + 1
  end
  return count
end

local function _build_risk_band(crap_score)
  if crap_score > 30 then
    return "critical"
  end
  if crap_score >= 10 then
    return "warning"
  end
  return "low"
end

local function _round_score(value)
  return math.floor(value * 100 + 0.5) / 100
end

local function _default_project_name(project_root)
  local normalized = common.normalize_path(project_root)
  return normalized:match("([^/]+)/?$") or "project"
end

local function _build_scan(project_root, source_roots)
  local scan_result, err = source_scan.scan_with_options({
    source_roots = source_roots,
  }, {
    project_root = project_root,
  })
  if scan_result == nil then
    return nil, err
  end

  local modules = {}
  for _, module_id in ipairs(scan_result.module_list or {}) do
    local module_info = scan_result.modules[module_id]
    local relative_source_path = common.relative_to(project_root, module_info.source_path)
    module_info.relative_source_path = relative_source_path
    module_info.source_name = relative_source_path:gsub("%.lua$", "")
    modules[#modules + 1] = module_info
  end

  table.sort(modules, function(left, right)
    return tostring(left.relative_source_path) < tostring(right.relative_source_path)
  end)

  return modules
end

local function _build_function_rows(modules, hit_lines_by_path)
  local functions = {}
  for _, module_info in ipairs(modules) do
    local luac_functions, err = luac_listing.analyze_module(module_info)
    if luac_functions == nil then
      return nil, err
    end
    local path_hits = hit_lines_by_path[module_info.relative_source_path] or {}
    for _, fn in ipairs(luac_functions) do
      local hit_count = 0
      for _, line_no in ipairs(fn.executable_lines or {}) do
        if path_hits[line_no] == true then
          hit_count = hit_count + 1
        end
      end
      local executable_count = #fn.executable_lines
      local coverage_ratio = 0.0
      if executable_count > 0 then
        coverage_ratio = hit_count / executable_count
      end
      local crap_score = (fn.complexity * fn.complexity * ((1 - coverage_ratio) ^ 3)) + fn.complexity
      functions[#functions + 1] = {
        id = fn.id,
        name = fn.name,
        module_id = fn.module_id,
        source_name = fn.source_name,
        source_path = fn.relative_source_path,
        start_line = fn.start_line,
        end_line = fn.end_line,
        executable_lines = fn.executable_lines,
        executable_line_count = executable_count,
        hit_line_count = hit_count,
        coverage = _round_score(coverage_ratio),
        complexity = fn.complexity,
        decision_line_count = #fn.decision_lines,
        crap = _round_score(crap_score),
        risk_band = _build_risk_band(crap_score),
      }
    end
  end

  table.sort(functions, function(left, right)
    if left.crap == right.crap then
      if left.complexity == right.complexity then
        return tostring(left.id) < tostring(right.id)
      end
      return left.complexity > right.complexity
    end
    return left.crap > right.crap
  end)

  return functions
end

local function _build_module_rows(modules, functions, hit_lines_by_path)
  local functions_by_path = {}
  for _, fn in ipairs(functions) do
    local bucket = functions_by_path[fn.source_path]
    if bucket == nil then
      bucket = {}
      functions_by_path[fn.source_path] = bucket
    end
    bucket[#bucket + 1] = fn
  end

  local rows = {}
  for _, module_info in ipairs(modules) do
    local module_functions = functions_by_path[module_info.relative_source_path] or {}
    local max_crap = 0
    local sum_crap = 0
    for _, fn in ipairs(module_functions) do
      sum_crap = sum_crap + fn.crap
      if fn.crap > max_crap then
        max_crap = fn.crap
      end
    end
    local path_hits = hit_lines_by_path[module_info.relative_source_path] or {}
    rows[#rows + 1] = {
      module_id = module_info.module_id,
      source_name = module_info.source_name,
      source_path = module_info.relative_source_path,
      function_count = #module_functions,
      hit_line_count = _count_map_keys(path_hits),
      max_function_crap = _round_score(max_crap),
      total_crap = _round_score(sum_crap),
    }
  end

  table.sort(rows, function(left, right)
    if left.max_function_crap == right.max_function_crap then
      return tostring(left.source_path) < tostring(right.source_path)
    end
    return left.max_function_crap > right.max_function_crap
  end)

  return rows
end

local function _print_summary(result, top_n)
  print("[crap] analyzed modules=" .. tostring(#(result.modules or {}))
    .. " functions=" .. tostring(#(result.functions or {})))
  for _, lane in ipairs(result.lanes or {}) do
    local status = lane.failed and "failed" or "passed"
    print("[crap] lane=" .. tostring(lane.lane)
      .. " mode=" .. tostring(lane.mode)
      .. " status=" .. status
      .. " total=" .. tostring(lane.total)
      .. " failures=" .. tostring(lane.failure_count))
  end
  print("[crap] top_hotspots")
  local limit = math.min(top_n, #(result.functions or {}))
  for index = 1, limit do
    local fn = result.functions[index]
    print(string.format(
      "  %02d. %s:%s:%s crap=%.2f complexity=%d coverage=%.2f",
      index,
      tostring(fn.source_path),
      tostring(fn.name),
      tostring(fn.start_line),
      fn.crap,
      fn.complexity,
      fn.coverage
    ))
  end
end

local function _resolve_coverage_result(opts, project_root, tracked_sources)
  if opts.coverage_result ~= nil then
    return opts.coverage_result
  end

  local coverage_opts = opts.coverage
  if type(coverage_opts) ~= "table" then
    return nil, "report.build requires coverage_result or coverage = { adapter = ..., lanes = ... }"
  end

  local collector = coverage_opts.collect or coverage.collect
  local ok, result = xpcall(function()
    return collector({
      project_root = project_root,
      tracked_sources = tracked_sources,
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
  local modules, scan_err = _build_scan(project_root, opts.source_roots)
  if modules == nil then
    return nil, scan_err
  end

  local tracked_sources = {}
  for _, module_info in ipairs(modules) do
    tracked_sources[#tracked_sources + 1] = module_info.relative_source_path
  end

  local coverage_result, coverage_err = _resolve_coverage_result(opts, project_root, tracked_sources)
  if coverage_result == nil then
    return nil, coverage_err
  end

  local line_hits = coverage_result.line_hits or {}
  local functions, function_err = _build_function_rows(modules, line_hits)
  if functions == nil then
    return nil, function_err
  end
  local module_rows = _build_module_rows(modules, functions, line_hits)

  local total_crap = 0
  local critical_count = 0
  for _, fn in ipairs(functions) do
    total_crap = total_crap + fn.crap
    if fn.risk_band == "critical" then
      critical_count = critical_count + 1
    end
  end

  local result = {
    metadata = {
      tool = "crap4lua_report",
      schema_version = 2,
      project_root = project_root,
      project_name = opts.project_name or _default_project_name(project_root),
      source_roots = common.copy_array(opts.source_roots),
      generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    },
    summary = {
      module_count = #module_rows,
      function_count = #functions,
      total_crap = _round_score(total_crap),
      critical_function_count = critical_count,
    },
    lanes = coverage_result.lanes or {},
    modules = module_rows,
    functions = functions,
  }

  _print_summary(result, opts.top or 20)

  if opts.out_path ~= nil then
    local ok, mkdir_err = common.ensure_parent_dir(opts.out_path)
    if not ok then
      return nil, mkdir_err
    end
    local write_ok, write_err = common.write_file(opts.out_path, json_writer.encode(result))
    if not write_ok then
      return nil, write_err
    end
    print("[crap] wrote_json=" .. tostring(opts.out_path))
  end

  local should_fail = false
  if opts.strict_tests == true then
    for _, lane in ipairs(result.lanes) do
      if lane.failed then
        should_fail = true
      end
    end
  end
  result.exit_code = should_fail and 1 or 0
  return result
end

return report
