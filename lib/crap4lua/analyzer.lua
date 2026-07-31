local ast = require("crap4lua.ast")
local common = require("crap4lua._internal.common")
local json_writer = require("crap4lua._internal.json_writer")

local analyzer = {}

local function _relative_source_path(abs_path, project_root)
  local prefix = common.normalize_path(project_root):gsub("/+$", "") .. "/"
  local normalized = common.normalize_path(abs_path)
  if normalized:sub(1, #prefix) == prefix then
    return normalized:sub(#prefix + 1)
  end
  return normalized
end

local function _source_name(relative_path)
  return relative_path:match("([^/]+)$") or relative_path
end

local function _compute_crap(complexity, coverage_ratio)
  return complexity * complexity * (1 - coverage_ratio) ^ 3 + complexity
end

-- Upstream risk bands: 1-5 low / 5-30 moderate / 30+ high.
local function _risk_band(crap_score)
  if crap_score == nil then return "n/a" end
  if crap_score >= 30 then return "high" end
  if crap_score >= 5 then return "moderate" end
  return "low"
end

-- Count executable / hit lines of a luacov file entry inside [start, finish].
local function _coverage_in_range(file_entry, start_line, finish_line)
  if file_entry == nil then
    return 0, 0
  end
  local exec, hit = 0, 0
  for line_no in pairs(file_entry.exec) do
    if line_no >= start_line and line_no <= finish_line then
      exec = exec + 1
      if file_entry.hit[line_no] then
        hit = hit + 1
      end
    end
  end
  return exec, hit
end

local function _format_coverage(hit, exec)
  if exec == 0 then return "N/A" end
  return string.format("%.0f%%", hit / exec * 100)
end

function analyzer.build_report(opts)
  opts = opts or {}
  local project_root = common.normalize_path(opts.project_root or ".")
  local source_roots = opts.source_roots or {}
  local coverage_result = opts.coverage_result or {}
  local coverage_files = coverage_result.files or {}
  local coverage_available = coverage_result.coverage_available == true
  local top = opts.top or 20

  local all_files = {}
  for _, root in ipairs(source_roots) do
    local abs_root = common.resolve_path(project_root, root)
    local files, err = common.collect_files(abs_root, ".lua")
    if files then
      for _, f in ipairs(files) do
        all_files[#all_files + 1] = f
      end
    elseif err then
      io.stderr:write(tostring(err) .. "\n")
    end
  end
  table.sort(all_files)

  local functions = {}
  local modules = {}
  local module_map = {}
  local func_id = 0

  for _, abs_path in ipairs(all_files) do
    local rel_path = _relative_source_path(abs_path, project_root)
    local parsed, parse_err = ast.analyze_file(abs_path)
    if parsed == nil then
      io.stderr:write("skip " .. rel_path .. ": " .. tostring(parse_err) .. "\n")
      goto continue_file
    end

    local file_entry = coverage_files[rel_path]
    local mod_exec = 0
    local mod_hit = 0
    local mod_max_crap = 0
    local mod_func_count = 0

    for _, fn in ipairs(parsed) do
      local exec_count, hit_count = _coverage_in_range(file_entry, fn.start_line, fn.end_line)

      -- N/A discipline: without coverage data the score is null (never 0),
      -- displayed as N/A and sorted last. A function whose file has no
      -- executable lines recorded is equally unmeasurable.
      local measurable = coverage_available and exec_count > 0
      local coverage_ratio = measurable and (hit_count / exec_count) or nil
      local crap_score = nil
      if measurable then
        crap_score = _compute_crap(fn.complexity, coverage_ratio)
        crap_score = math.floor(crap_score * 100 + 0.5) / 100
      end

      func_id = func_id + 1
      functions[#functions + 1] = {
        id = func_id,
        name = fn.name,
        source_path = rel_path,
        source_name = _source_name(rel_path),
        start_line = fn.start_line,
        end_line = fn.end_line,
        crap = crap_score or json_writer.null,
        crap_score = crap_score or json_writer.null,
        complexity = fn.complexity,
        coverage = measurable and _format_coverage(hit_count, exec_count) or "N/A",
        executable_line_count = exec_count,
        hit_line_count = hit_count,
        risk_band = _risk_band(crap_score),
      }

      mod_exec = mod_exec + exec_count
      mod_hit = mod_hit + hit_count
      if crap_score and crap_score > mod_max_crap then
        mod_max_crap = crap_score
      end
      mod_func_count = mod_func_count + 1
    end

    if mod_func_count > 0 then
      module_map[rel_path] = {
        source_path = rel_path,
        source_name = _source_name(rel_path),
        function_count = mod_func_count,
        max_function_crap = mod_max_crap,
        executable_line_count = mod_exec,
        hit_line_count = mod_hit,
      }
    end

    ::continue_file::
  end

  -- CRAP descending, N/A sunk to the bottom; ties by complexity then name.
  table.sort(functions, function(a, b)
    local a_null = a.crap == json_writer.null
    local b_null = b.crap == json_writer.null
    if a_null ~= b_null then return b_null end
    if not a_null and a.crap ~= b.crap then return a.crap > b.crap end
    if a.complexity ~= b.complexity then return a.complexity > b.complexity end
    return a.name < b.name
  end)

  if top > 0 and #functions > top then
    local trimmed = {}
    for i = 1, top do
      trimmed[i] = functions[i]
    end
    functions = trimmed
  end

  for _, path in ipairs(common.sorted_keys(module_map)) do
    modules[#modules + 1] = module_map[path]
  end

  local total_exec = 0
  local total_hit = 0
  local max_crap = 0
  local sum_crap = 0
  local scored_count = 0
  local high_count = 0
  local moderate_count = 0
  local na_count = 0
  for _, fn in ipairs(functions) do
    total_exec = total_exec + fn.executable_line_count
    total_hit = total_hit + fn.hit_line_count
    if fn.crap == json_writer.null then
      na_count = na_count + 1
    else
      scored_count = scored_count + 1
      sum_crap = sum_crap + fn.crap
      if fn.crap > max_crap then max_crap = fn.crap end
      if fn.risk_band == "high" then
        high_count = high_count + 1
      elseif fn.risk_band == "moderate" then
        moderate_count = moderate_count + 1
      end
    end
  end

  return {
    metadata = {
      project_name = opts.project_name or "Project",
      source_roots = source_roots,
      generated_at = os.date("%Y-%m-%dT%H:%M:%S"),
    },
    lanes = coverage_result.lanes or {},
    coverage_available = coverage_available,
    summary = {
      function_count = #functions,
      module_count = #modules,
      avg_crap = scored_count > 0 and (math.floor(sum_crap / scored_count * 100 + 0.5) / 100) or 0,
      max_crap = max_crap,
      high_count = high_count,
      moderate_count = moderate_count,
      na_count = na_count,
    },
    functions = functions,
    modules = modules,
  }
end

return analyzer
