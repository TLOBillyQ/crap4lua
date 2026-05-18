local common = require("crap4lua._internal.common")

local analyzer = {}

local DECISION_OPCODES = {
  EQ = true, LT = true, LE = true,
  TEST = true, TESTSET = true,
  FORLOOP = true, FORPREP = true, TFORLOOP = true,
  EQK = true, EQI = true,
  LTI = true, LEI = true,
  GTI = true, GEI = true,
}

function analyzer.parse_luac_output(text)
  local functions = {}
  local current = nil

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local kind, file, start_line, end_line = line:match("^(%S+)%s+<(.+):(%d+),(%d+)>")
    if kind == "main" or kind == "function" then
      if current then
        functions[#functions + 1] = current
      end
      current = {
        name = kind == "main" and "(main)" or nil,
        source_path = file,
        start_line = tonumber(start_line),
        end_line = tonumber(end_line),
        executable_lines = {},
        decision_lines = {},
      }
    elseif current then
      local line_no, opcode = line:match("%[(%d+)%]%s+(%S+)")
      if line_no and opcode then
        local n = tonumber(line_no)
        current.executable_lines[n] = true
        if DECISION_OPCODES[opcode] then
          current.decision_lines[n] = true
        end
      end
    end
  end

  if current then
    functions[#functions + 1] = current
  end
  return functions
end

local function _count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function _run_luac(abs_path, luac_cmd)
  luac_cmd = luac_cmd or "luac"
  local command = luac_cmd .. " -p -l " .. common.shell_quote(abs_path) .. " 2>&1"
  local handle = io.popen(command)
  if handle == nil then
    return nil, "failed to run luac"
  end
  local output = handle:read("*a")
  handle:close()
  return (output or ""):gsub("^%s+", "")
end

function analyzer.analyze_file(abs_path, opts)
  opts = opts or {}
  local output, err = _run_luac(abs_path, opts.luac_cmd)
  if output == nil then
    return nil, err
  end
  if not output:match("^%S+%s+<") then
    return nil, output:match("^[^\n]*") or "luac failed"
  end
  return analyzer.parse_luac_output(output)
end

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

local function _risk_band(crap_score)
  if crap_score >= 30 then return "critical" end
  if crap_score >= 8 then return "warning" end
  return "low"
end

local function _format_coverage(hit, exec)
  if exec == 0 then return "100%" end
  return string.format("%.0f%%", hit / exec * 100)
end

function analyzer.build_report(opts)
  opts = opts or {}
  local project_root = common.normalize_path(opts.project_root or ".")
  local source_roots = opts.source_roots or {}
  local coverage_result = opts.coverage_result or {}
  local line_hits = coverage_result.line_hits or {}
  local top = opts.top or 20
  local luac_cmd = opts.luac_cmd

  if not common.command_exists(luac_cmd or "luac") then
    return nil, "luac command not found. Install Lua to get luac."
  end

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
    local file_hits = line_hits[rel_path] or {}
    local parsed, parse_err = analyzer.analyze_file(abs_path, { luac_cmd = luac_cmd })
    if parsed == nil then
      io.stderr:write("skip " .. rel_path .. ": " .. tostring(parse_err) .. "\n")
      goto continue_file
    end

    local mod_exec = 0
    local mod_hit = 0
    local mod_max_crap = 0
    local mod_func_count = 0

    for _, fn in ipairs(parsed) do
      local exec_count = _count_keys(fn.executable_lines)
      local hit_count = 0
      for line_no in pairs(fn.executable_lines) do
        if file_hits[line_no] then
          hit_count = hit_count + 1
        end
      end

      local decision_count = _count_keys(fn.decision_lines)
      local complexity = 1 + decision_count
      local coverage_ratio = exec_count > 0 and (hit_count / exec_count) or 1
      local crap_score = _compute_crap(complexity, coverage_ratio)
      crap_score = math.floor(crap_score * 100 + 0.5) / 100

      func_id = func_id + 1
      local name = fn.name or ("function:" .. fn.start_line)

      functions[#functions + 1] = {
        id = func_id,
        name = name,
        source_path = rel_path,
        source_name = _source_name(rel_path),
        start_line = fn.start_line,
        end_line = fn.end_line,
        crap = crap_score,
        crap_score = crap_score,
        complexity = complexity,
        coverage = _format_coverage(hit_count, exec_count),
        decision_line_count = decision_count,
        executable_line_count = exec_count,
        hit_line_count = hit_count,
        risk_band = _risk_band(crap_score),
      }

      mod_exec = mod_exec + exec_count
      mod_hit = mod_hit + hit_count
      if crap_score > mod_max_crap then
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

  table.sort(functions, function(a, b)
    if a.crap ~= b.crap then return a.crap > b.crap end
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
  local critical_count = 0
  local warning_count = 0
  for _, fn in ipairs(functions) do
    total_exec = total_exec + fn.executable_line_count
    total_hit = total_hit + fn.hit_line_count
    sum_crap = sum_crap + fn.crap
    if fn.crap > max_crap then max_crap = fn.crap end
    if fn.risk_band == "critical" then
      critical_count = critical_count + 1
    elseif fn.risk_band == "warning" then
      warning_count = warning_count + 1
    end
  end

  return {
    metadata = {
      project_name = opts.project_name or "Project",
      source_roots = source_roots,
      generated_at = os.date("%Y-%m-%dT%H:%M:%S"),
    },
    lanes = coverage_result.lanes or {},
    summary = {
      function_count = #functions,
      module_count = #modules,
      avg_crap = #functions > 0 and (math.floor(sum_crap / #functions * 100 + 0.5) / 100) or 0,
      max_crap = max_crap,
      critical_count = critical_count,
      warning_count = warning_count,
    },
    functions = functions,
    modules = modules,
  }
end

return analyzer
