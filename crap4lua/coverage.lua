local common = require("crap4lua.common")

local coverage = {}

local function _silent_reporter()
  return {
    case_pass = function() end,
    case_fail = function() end,
    finish = function() end,
  }
end

local function _resolve_hit_lines(line_hits, relative_path)
  local hit_lines = line_hits[relative_path]
  if hit_lines == nil then
    hit_lines = {}
    line_hits[relative_path] = hit_lines
  end
  return hit_lines
end

local function _make_hook(project_root, tracked_sources, line_hits, debug_api)
  local function_cache = setmetatable({}, { __mode = "k" })
  local getinfo = debug_api.getinfo
  local relative_to = common.relative_to

  return function(_, line_no)
    local info = getinfo(2, "f")
    local func = info and info.func
    if func == nil then
      return
    end

    local cached = function_cache[func]
    if cached then
      cached[line_no] = true
      return
    end
    if cached == false then
      return
    end

    local source_info = getinfo(func, "S")
    if source_info == nil or source_info.source == nil then
      function_cache[func] = false
      return
    end

    local normalized = relative_to(project_root, source_info.source)
    normalized = normalized:gsub("^%./", "")
    if tracked_sources[normalized] ~= true then
      function_cache[func] = false
      return
    end

    local hit_lines = _resolve_hit_lines(line_hits, normalized)
    function_cache[func] = hit_lines
    hit_lines[line_no] = true
  end
end

local function _missing_resolve_lane_suites()
  error("coverage.collect requires resolve_lane_suites(lane, mode) injector")
end

local function _missing_run_all()
  error("coverage.collect requires run_all(suites, opts) injector")
end

local function _resolve_dependencies(opts)
  return {
    resolve_lane_suites = opts.resolve_lane_suites or _missing_resolve_lane_suites,
    run_all = opts.run_all or _missing_run_all,
    debug_api = opts.debug_api or debug,
  }
end

function coverage.collect(opts)
  opts = opts or {}
  local deps = _resolve_dependencies(opts)
  local project_root = common.normalize_path(opts.project_root)
  local tracked_sources = {}
  for _, source_path in ipairs(opts.tracked_sources or {}) do
    tracked_sources[common.normalize_path(source_path)] = true
  end

  local line_hits = {}
  local lane_results = {}

  for _, lane in ipairs(opts.lanes or { "behavior" }) do
    local suites, resolved_mode = deps.resolve_lane_suites(lane, opts.mode)
    local hook = _make_hook(project_root, tracked_sources, line_hits, deps.debug_api)
    local result = deps.run_all(suites, {
      mode = resolved_mode,
      capture_logs = true,
      reporter = _silent_reporter(),
      raise_on_failure = false,
      before_case = function()
        deps.debug_api.sethook(hook, "l")
      end,
      after_case = function()
        deps.debug_api.sethook()
      end,
    })
    lane_results[#lane_results + 1] = {
      lane = lane,
      mode = resolved_mode,
      total = result.total,
      failed = result.failed,
      failure_count = #(result.failures or {}),
      failures = result.failures,
    }
  end

  deps.debug_api.sethook()

  return {
    line_hits = line_hits,
    lanes = lane_results,
  }
end

return coverage
