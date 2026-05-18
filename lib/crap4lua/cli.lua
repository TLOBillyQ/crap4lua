local common = require("crap4lua._internal.common")
local json_writer = require("crap4lua._internal.json_writer")
local coverage_mod = require("crap4lua.coverage")
local analyzer = require("crap4lua.analyzer")
local viewer_mod = require("crap4lua.viewer")

local cli = {}

local function _help_text(command_name)
  return table.concat({
    "Usage:",
    "  lua " .. command_name .. " report [--lane NAME] [--runner NAME] [--out FILE] [--top N] [--strict-tests] [--project-root DIR]",
    "  lua " .. command_name .. " collect [--lane NAME] [--runner NAME] --out FILE [--project-root DIR]",
    "  lua " .. command_name .. " dry-run [--lane NAME] [--runner NAME] [--config FILE]",
    "  lua " .. command_name .. " viewer [--in-json FILE] [--out-dir DIR] [--open]",
    "  lua " .. command_name .. " summary [--in-json FILE] [--tier-config FILE] [--lane NAME] [--out FILE] [--top N] [--gate]",
    "  lua " .. command_name .. "   (bare call = report + viewer --open)",
  }, "\n") .. "\n"
end

local function _resolve_tmp_root(env)
  local env_var = env and env.tmp_env_var or nil
  if env_var then
    local val = os.getenv(env_var)
    if val and val ~= "" then return common.normalize_path(val) end
  end
  local root = env and env.tmp_root or nil
  if root then return common.normalize_path(root) end
  return common.join_path(common.system_tmp_dir(), "crap4lua")
end

local function _resolve_cli_path(base, path, tmp_root)
  local normalized = common.normalize_path(path)
  if normalized == "" then
    return common.resolve_path(base, normalized)
  end
  if normalized == "tmp" or normalized:match("^tmp/") then
    local suffix = normalized == "tmp" and "" or normalized:sub(5)
    return common.resolve_path(tmp_root, suffix)
  end
  return common.resolve_path(base, normalized)
end

local function _copy_array(values)
  local copied = {}
  for _, v in ipairs(values or {}) do
    copied[#copied + 1] = v
  end
  return copied
end

local function _is_array_table(value)
  return type(value) == "table" and #value > 0
end

local function _parse_args(args)
  local options = {
    command = nil, config = nil, out = nil, out_dir = nil,
    in_json = nil, project_root = nil, tier_config = nil,
    lanes = {}, runner = nil, top = nil,
    strict_tests = false, gate = false, open = false, help = false,
    lane = nil,
  }

  local index = 1
  if args[1] and args[1]:sub(1, 2) ~= "--" then
    options.command = args[1]
    index = 2
  end

  while index <= #args do
    local token = args[index]
    if token == "--help" or token == "-h" then
      options.help = true
    elseif token == "--config" then
      index = index + 1; options.config = args[index]
    elseif token == "--out" or token == "--response-json" then
      index = index + 1; options.out = args[index]
    elseif token == "--out-dir" then
      index = index + 1; options.out_dir = args[index]
    elseif token == "--in-json" then
      index = index + 1; options.in_json = args[index]
    elseif token == "--project-root" then
      index = index + 1; options.project_root = args[index]
    elseif token == "--tier-config" then
      index = index + 1; options.tier_config = args[index]
    elseif token == "--lane" then
      index = index + 1
      local lane_val = args[index]
      options.lanes[#options.lanes + 1] = lane_val
      options.lane = lane_val
    elseif token == "--runner" then
      index = index + 1; options.runner = args[index]
    elseif token == "--top" then
      index = index + 1; options.top = common.to_integer(args[index])
    elseif token == "--strict-tests" then
      options.strict_tests = true
    elseif token == "--gate" then
      options.gate = true
    elseif token == "--open" then
      options.open = true
    else
      error("unknown flag: " .. tostring(token))
    end
    index = index + 1
  end
  return options
end

local function _load_raw_config(config_path)
  local ok, loaded = pcall(dofile, config_path)
  if not ok then return nil, loaded end
  if type(loaded) ~= "table" then
    return nil, "crap config must return a table"
  end
  return loaded, nil
end

local function _resolve_adapter(raw_coverage, config_dir, lane, runner)
  local adapter_setting = nil
  if runner and runner ~= "" then
    if runner == "busted" then
      adapter_setting = "busted_adapter.lua"
    else
      return nil, "unsupported runner: " .. tostring(runner)
    end
  end

  if adapter_setting == nil and type(raw_coverage.lanes) == "table"
      and #raw_coverage.lanes == 0 and lane and lane ~= "" then
    adapter_setting = raw_coverage.lanes[lane]
  end
  if adapter_setting == nil then
    adapter_setting = raw_coverage.adapter
  end
  if adapter_setting == nil then
    return nil, "coverage adapter is required"
  end

  local adapter = adapter_setting
  if type(adapter) == "string" then
    local adapter_path = common.resolve_path(config_dir, adapter)
    local ok, loaded = pcall(dofile, adapter_path)
    if not ok then return nil, loaded end
    adapter = loaded
  elseif type(adapter) == "function" then
    adapter = adapter()
  end

  if type(adapter) ~= "table" then
    return nil, "coverage adapter must resolve to a table"
  end
  return adapter, nil
end

local function _resolve_collect_lanes(raw_coverage, cli_lanes)
  if _is_array_table(cli_lanes) then return _copy_array(cli_lanes) end
  local lanes_cfg = raw_coverage and raw_coverage.lanes or nil
  if type(lanes_cfg) == "table" then
    if lanes_cfg.behavior then return { "behavior" } end
    local keys = common.sorted_keys(lanes_cfg)
    if #keys > 0 then return { keys[1] } end
  end
  return { "default" }
end

local function _collect_coverage(options, env)
  local config_path = options.config or env.default_config
  if not config_path or config_path == "" then
    return nil, "missing --config"
  end
  local raw, load_err = _load_raw_config(config_path)
  if not raw then return nil, load_err end

  local config_dir = common.parent_dir(config_path) or env.cwd or common.current_dir()
  local raw_coverage = raw.coverage or {}
  local lanes = _resolve_collect_lanes(raw_coverage, options.lanes)
  local selected_lane = lanes[1]
  local adapter, adapter_err = _resolve_adapter(raw_coverage, config_dir, selected_lane, options.runner)
  if not adapter then return nil, adapter_err end

  local project_root = common.resolve_path(config_dir, raw.project_root or ".")
  if options.project_root and options.project_root ~= "" then
    project_root = options.project_root
  end

  local source_roots = _copy_array(raw.source_roots or {})
  local collect_result = coverage_mod.collect({
    project_root = project_root,
    tracked_sources = _copy_array(raw_coverage.tracked_sources or {}),
    source_roots = source_roots,
    lanes = lanes,
    mode = raw_coverage.mode,
    adapter = adapter,
  })

  return {
    project_root = project_root,
    project_name = raw.project_name or "Monopoly",
    source_roots = source_roots,
    coverage_result = collect_result,
  }, nil
end

local function _build_report(options, env)
  local collected, err = _collect_coverage(options, env)
  if not collected then return nil, err end

  return analyzer.build_report({
    project_root = collected.project_root,
    project_name = collected.project_name,
    source_roots = collected.source_roots,
    coverage_result = collected.coverage_result,
    top = options.top or env.default_top or 20,
    luac_cmd = env.luac_cmd,
  })
end

local function _write_json(path, payload)
  local ok, err = common.write_file(path, json_writer.encode(payload))
  if not ok then return nil, err end
  return true
end

local function _read_json_file(path)
  local content, read_err = common.read_file(path)
  if not content then return nil, read_err end
  local json_reader = require("shared.lib.json_reader")
  local ok_parse, decoded = pcall(json_reader.decode, content)
  if not ok_parse then return nil, "JSON parse error: " .. tostring(decoded) end
  return decoded
end

local function _build_write_report(options, env, out, stderr)
  local report, err = _build_report(options, env)
  if not report then
    stderr:write(tostring(err) .. "\n")
    return nil
  end
  local ok, write_err = _write_json(out, report)
  if not ok then
    stderr:write(tostring(write_err) .. "\n")
    return nil
  end
  return report
end

local function _cov_ratio(hit, exec)
  if exec == 0 then return nil end
  return hit / exec
end

local function _pct_str(hit, exec)
  local r = _cov_ratio(hit, exec)
  if r == nil then return "  N/A " end
  return string.format("%5.1f%%", r * 100)
end

local function _load_tiers(path)
  local ok, result = pcall(dofile, path)
  if not ok then return nil, "Cannot load tier config: " .. tostring(result) end
  if type(result) ~= "table" or type(result.tiers) ~= "table" then
    return nil, "tier config must return { tiers = { ... } }"
  end
  return result.tiers, nil
end

local function _file_tier_index(source_path, tiers)
  for i, tier in ipairs(tiers) do
    for _, prefix in ipairs(tier.includes or {}) do
      local norm = prefix:gsub("/+$", "") .. "/"
      if source_path:sub(1, #norm) == norm then return i end
    end
  end
  return nil
end

local function _aggregate_from_report(report, tiers)
  local tier_stats = {}
  for i, tier in ipairs(tiers) do
    tier_stats[i] = {
      name = tier.name, threshold = tier.threshold or 0,
      exec_lines = 0, hit_lines = 0, file_stats = {},
    }
  end
  local uncategorized = { exec_lines = 0, hit_lines = 0, file_stats = {} }
  for _, func in ipairs(report.functions or {}) do
    local sp = func.source_path or func.source_name
    if sp then
      local exec = func.executable_line_count or 0
      local hit = func.hit_line_count or 0
      local ti = _file_tier_index(sp, tiers)
      local bucket = ti and tier_stats[ti] or uncategorized
      bucket.exec_lines = bucket.exec_lines + exec
      bucket.hit_lines = bucket.hit_lines + hit
      if not bucket.file_stats[sp] then
        bucket.file_stats[sp] = { exec = 0, hit = 0 }
      end
      bucket.file_stats[sp].exec = bucket.file_stats[sp].exec + exec
      bucket.file_stats[sp].hit = bucket.file_stats[sp].hit + hit
    end
  end
  return tier_stats, uncategorized
end

local function _print_coverage_table(tier_stats, uncategorized, options, stdout)
  local lane_label = _is_array_table(options.lanes)
    and table.concat(options.lanes, "+") or "behavior"
  stdout:write("\n Coverage summary (lane: " .. lane_label .. ")\n")
  stdout:write(string.rep("=", 70) .. "\n")
  stdout:write(string.format("%-16s %6s %9s %8s %7s %6s  %s\n",
    "Tier", "Files", "Exec", "Hit", "Cover", "Goal", "Status"))
  stdout:write(string.rep("-", 70) .. "\n")
  local all_pass = true
  for _, ts in ipairs(tier_stats) do
    local file_count = 0
    for _ in pairs(ts.file_stats) do file_count = file_count + 1 end
    local ratio = _cov_ratio(ts.hit_lines, ts.exec_lines)
    local pass = ratio ~= nil and ratio >= ts.threshold
    if not pass then all_pass = false end
    stdout:write(string.format("%-16s %6d %9d %8d %7s %5.0f%%  %s\n",
      ts.name, file_count, ts.exec_lines, ts.hit_lines,
      _pct_str(ts.hit_lines, ts.exec_lines),
      ts.threshold * 100, pass and "PASS" or "FAIL"))
  end
  if uncategorized.exec_lines > 0 then
    local unc_files = 0
    for _ in pairs(uncategorized.file_stats) do unc_files = unc_files + 1 end
    stdout:write(string.format("%-16s %6d %9d %8d %7s   ---  ---\n",
      "(other)", unc_files, uncategorized.exec_lines, uncategorized.hit_lines,
      _pct_str(uncategorized.hit_lines, uncategorized.exec_lines)))
  end
  stdout:write(string.rep("=", 70) .. "\n")
  local top_n = options.top or 10
  if top_n > 0 then
    for _, ts in ipairs(tier_stats) do
      local ratio = _cov_ratio(ts.hit_lines, ts.exec_lines)
      if ratio == nil or ratio < ts.threshold then
        local files = {}
        for path, fs in pairs(ts.file_stats) do
          if fs.exec > 0 then
            files[#files + 1] = { path = path, exec = fs.exec, hit = fs.hit }
          end
        end
        table.sort(files, function(a, b) return (a.exec - a.hit) > (b.exec - b.hit) end)
        local n = math.min(top_n, #files)
        if n > 0 then
          stdout:write("\n Failing [" .. ts.name .. "] — top " .. tostring(n) .. " uncovered:\n")
          for i = 1, n do
            local f = files[i]
            stdout:write(string.format("  %-52s %5d/%5d  %s\n",
              f.path, f.hit, f.exec, _pct_str(f.hit, f.exec)))
          end
        end
      end
    end
  end
  stdout:write("\n")
  return all_pass
end

function cli.run(args, env)
  env = env or {}
  local stdout = env.stdout or io.stdout
  local stderr = env.stderr or io.stderr
  local command_name = env.command_name or "crap4lua"
  local cwd = env.cwd or common.current_dir()
  local tmp_root = _resolve_tmp_root(env)
  local resolve = function(path) return _resolve_cli_path(cwd, path, tmp_root) end
  local options = _parse_args(args or {})

  if options.config then
    options.config = resolve(options.config)
  else
    options.config = env.default_config
  end

  local default_report_out = env.default_report_out or "tmp/crap_report.json"
  local default_view_dir = env.default_view_dir or "tmp/crap_view"

  if options.command == nil then
    options.command = "bare"
    options.open = true
  end

  if options.help then
    stdout:write(_help_text(command_name))
    return 0
  end

  if options.project_root then
    options.project_root = resolve(options.project_root)
  end

  if options.command == "report" then
    local out = options.out and resolve(options.out) or resolve(default_report_out)
    if not _build_write_report(options, env, out, stderr) then return 1 end
    stdout:write("crap report json: " .. common.normalize_path(out) .. "\n")
    return 0
  end

  if options.command == "collect" then
    if not options.out or options.out == "" then
      stderr:write("collect requires --out FILE\n")
      return 1
    end
    local out = resolve(options.out)
    local result, err = _collect_coverage(options, env)
    if not result then
      stderr:write(tostring(err) .. "\n")
      return 1
    end
    local ok, write_err = _write_json(out, result)
    if not ok then
      stderr:write(tostring(write_err) .. "\n")
      return 1
    end
    stdout:write("crap collect json: " .. common.normalize_path(out) .. "\n")
    return 0
  end

  if options.command == "dry-run" then
    local config_path = options.config or env.default_config
    if not config_path or config_path == "" then
      stderr:write("missing --config\n")
      return 1
    end
    local raw, load_err = _load_raw_config(config_path)
    if not raw then
      stderr:write(tostring(load_err) .. "\n")
      return 1
    end
    local config_dir = common.parent_dir(config_path) or cwd
    local raw_coverage = raw.coverage or {}
    local adapter, adapter_err = _resolve_adapter(raw_coverage, config_dir, options.lane or "behavior", options.runner)
    if not adapter then
      stderr:write(tostring(adapter_err) .. "\n")
      return 1
    end
    if type(adapter.discover_specs) ~= "function" then
      stderr:write("adapter does not support dry-run discover_specs(lane)\n")
      return 1
    end
    local ok, spec_files_or_err = pcall(adapter.discover_specs, options.lane or "behavior")
    if not ok then
      stderr:write(tostring(spec_files_or_err) .. "\n")
      return 1
    end
    for _, spec_file in ipairs(spec_files_or_err or {}) do
      stdout:write(tostring(spec_file) .. "\n")
    end
    return 0
  end

  if options.command == "viewer" then
    local out_dir = options.out_dir and resolve(options.out_dir) or resolve(default_view_dir)
    local report_data
    if options.in_json and options.in_json ~= "" then
      local decoded, read_err = _read_json_file(resolve(options.in_json))
      if not decoded then
        stderr:write(tostring(read_err) .. "\n")
        return 1
      end
      report_data = decoded
    else
      local report, err = _build_report(options, env)
      if not report then
        stderr:write(tostring(err) .. "\n")
        return 1
      end
      report_data = report
    end

    local ok, err = viewer_mod.generate(report_data, out_dir, {
      open = options.open,
      open_path = env.open_path,
    })
    if not ok then
      stderr:write(tostring(err) .. "\n")
      return 1
    end
    stdout:write("crap viewer index: " .. common.normalize_path(common.join_path(out_dir, "index.html")) .. "\n")
    return 0
  end

  if options.command == "summary" then
    local in_json = options.in_json and resolve(options.in_json) or nil
    if not in_json then
      local default_path = resolve(default_report_out)
      if common.path_exists(default_path) then
        in_json = default_path
      else
        if not _build_write_report(options, env, default_path, stderr) then return 1 end
        in_json = default_path
      end
    end

    local report, read_err = _read_json_file(in_json)
    if not report then
      stderr:write("Cannot read report: " .. tostring(read_err) .. "\n")
      return 1
    end
    if type(report) ~= "table" then
      stderr:write("JSON parse error: report is not a table\n")
      return 1
    end
    if type(report.functions) ~= "table" then
      stderr:write("crap_report.json missing functions field, run report first\n")
      return 1
    end

    local tier_config_path = options.tier_config and resolve(options.tier_config)
      or env.default_tier_config
    if not tier_config_path then
      stderr:write("missing --tier-config\n")
      return 1
    end
    local tiers, tier_err = _load_tiers(tier_config_path)
    if not tiers then
      stderr:write(tostring(tier_err) .. "\n")
      return 1
    end

    local tier_stats, uncategorized = _aggregate_from_report(report, tiers)
    local all_pass = _print_coverage_table(tier_stats, uncategorized, options, stdout)

    if options.out then
      local out = resolve(options.out)
      local out_rows = {}
      for _, ts in ipairs(tier_stats) do
        local fc = 0
        for _ in pairs(ts.file_stats) do fc = fc + 1 end
        local ratio = _cov_ratio(ts.hit_lines, ts.exec_lines)
        out_rows[#out_rows + 1] = {
          name = ts.name, threshold = ts.threshold,
          file_count = fc, exec_lines = ts.exec_lines,
          hit_lines = ts.hit_lines, coverage = ratio or 0,
          pass = ratio ~= nil and ratio >= ts.threshold,
        }
      end
      local ok_w, w_err = common.write_file(out, json_writer.encode({ tiers = out_rows }))
      if not ok_w then
        stderr:write(tostring(w_err) .. "\n")
      else
        stdout:write("crap summary json: " .. common.normalize_path(out) .. "\n")
      end
    end

    if options.gate and not all_pass then return 1 end
    return 0
  end

  if options.command == "bare" then
    local out = resolve(default_report_out)
    local report = _build_write_report(options, env, out, stderr)
    if not report then return 1 end
    stdout:write("crap report json: " .. common.normalize_path(out) .. "\n")

    local out_dir = resolve(default_view_dir)
    local ok, err = viewer_mod.generate(report, out_dir, {
      open = true,
      open_path = env.open_path,
    })
    if not ok then
      stderr:write(tostring(err) .. "\n")
      return 1
    end
    stdout:write("crap viewer index: " .. common.normalize_path(common.join_path(out_dir, "index.html")) .. "\n")
    return 0
  end

  stderr:write("unknown command: " .. tostring(options.command) .. "\n")
  stderr:write(_help_text(command_name))
  return 1
end

return cli
