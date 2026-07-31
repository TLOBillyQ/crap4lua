-- Coverage collection: the host adapter runs its test suite under luacov,
-- crap4lua then parses the standard luacov report artifact (ADR-0003).
-- No coverage mechanism of our own — the debug.sethook adapter contract is
-- gone; only the ecosystem tool's fixed output is interpreted.
local common = require("crap4lua._internal.common")

local coverage = {}

local DEFAULT_REPORT_PATH = "luacov.report.out"

local function _silent_reporter()
  return {
    case_pass = function() end,
    case_fail = function() end,
    finish = function() end,
  }
end

local function _resolve_adapter(opts)
  local adapter = opts.adapter
  if type(adapter) ~= "table" then
    error("coverage.collect requires adapter = { resolve_suites = ..., run = ... }")
  end
  if type(adapter.resolve_suites) ~= "function" then
    error("coverage adapter requires resolve_suites(lane, mode)")
  end
  if type(adapter.run) ~= "function" then
    error("coverage adapter requires run(suites, opts)")
  end
  return adapter
end

-- Parses luacov's default reporter output. Layout per file section:
--   ====... (rule)
--   <path as luacov saw it>
--   ====... (rule)
--   one line per source line: right-aligned hit count (`***0` for a zero-hit
--   executable line, blank prefix for non-executable lines), then the source.
-- Returns files[report_path] = { exec = {line=true}, hit = {line=true} }.
function coverage.parse_luacov_report(text)
  local files = {}
  local current = nil
  -- idle -> (rule) expect_path -> (path line) expect_data_rule -> (rule) data;
  -- a rule inside data closes the section back to idle.
  local state = "idle"

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^=+%s*$") then
      if state == "idle" then
        state = "expect_path"
      elseif state == "expect_data_rule" then
        state = "data"
      else
        state = "idle"
        current = nil
      end
    elseif state == "expect_path" then
      local path = line:match("^%s*(.-)%s*$")
      if path ~= "" then
        current = { exec = {}, hit = {} }
        files[path] = current
        state = "expect_data_rule"
      end
    elseif state == "data" then
      -- luacov emits every source line in order; track our own counter.
      local token = line:match("^%s*(%*+%s*0)%s") or line:match("^%s*(%d+)%s")
      if token then
        current._line = (current._line or 0) + 1
        current.exec[current._line] = true
        local n = tonumber((token:gsub("%*", "")))
        if n and n > 0 then
          current.hit[current._line] = true
        end
      else
        -- Non-executable (blank-prefix) lines still advance the counter.
        current._line = (current._line or 0) + 1
      end
    end
  end

  for _, file in pairs(files) do
    file._line = nil
  end
  return files
end

local function _remap_paths(files, project_root)
  -- luacov records paths as seen at test time (relative to wherever the host
  -- ran, or absolute). Normalize to project-root-relative keys.
  local remapped = {}
  local prefix = common.normalize_path(project_root):gsub("/+$", "") .. "/"
  for path, data in pairs(files) do
    local normalized = common.normalize_path(path):gsub("^%./", "")
    if normalized:sub(1, #prefix) == prefix then
      normalized = normalized:sub(#prefix + 1)
    end
    remapped[normalized] = data
  end
  return remapped
end

function coverage.collect(opts)
  opts = opts or {}
  local adapter = _resolve_adapter(opts)
  local project_root = common.normalize_path(opts.project_root)
  local report_path = opts.report_path
    or common.join_path(project_root, DEFAULT_REPORT_PATH)

  -- Upstream discipline: delete stale coverage artifacts before regenerating.
  os.remove(report_path)

  local lane_results = {}
  for _, lane in ipairs(opts.lanes or { "default" }) do
    local suites, resolved_mode = adapter.resolve_suites(lane, opts.mode)
    local result = adapter.run(suites or {}, {
      mode = resolved_mode or opts.mode or lane,
      capture_logs = true,
      reporter = _silent_reporter(),
      raise_on_failure = false,
      report_path = report_path,
    }) or {}

    lane_results[#lane_results + 1] = {
      lane = lane,
      mode = resolved_mode or opts.mode or lane,
      total = result.total or 0,
      failed = result.failed == true,
      failure_count = #(result.failures or {}),
      failures = result.failures or {},
    }
  end

  local coverage_available = common.path_exists(report_path)
  local files = {}
  if coverage_available then
    local content = common.read_file(report_path)
    if content then
      files = _remap_paths(coverage.parse_luacov_report(content), project_root)
    else
      coverage_available = false
    end
  else
    io.stderr:write("warning: luacov report not found at " .. report_path
      .. " — coverage unavailable, CRAP scores will be N/A\n")
  end

  return {
    files = files,
    lanes = lane_results,
    coverage_available = coverage_available,
    report_path = report_path,
  }
end

return coverage
