local bootstrap = require("tests.support.bootstrap")
local analyzer = require("crap4lua.analyzer")
local ast = require("crap4lua.ast")
local json_writer = require("crap4lua._internal.json_writer")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local SAMPLE = table.concat({
  "local M = {}",
  "",
  "function M.run(flag)",
  "  if flag then",
  "    return 4",
  "  end",
  "  return 3",
  "end",
  "",
  "local function helper(a, b)",
  "  while a do",
  "    a = a and b",
  "  end",
  "  for i = 1, 3 do",
  "    a = a or i",
  "  end",
  "  return a",
  "end",
  "",
  "return M",
}, "\n")

local function _write_source(tmp_root, rel, text)
  local path = tmp_root .. "/" .. rel
  local file = assert(io.open(path, "w"))
  file:write(text .. "\n")
  file:close()
  return path
end

local function _test_ast_complexity_counts_decision_points()
  helpers.with_temp_fixture({}, function(tmp_root)
    local path = _write_source(tmp_root, "sample.lua", SAMPLE)
    local fns = ast.analyze_file(path)
    helpers.assert_eq(#fns, 2, "two functions extracted")
    helpers.assert_eq(fns[1].name, "M.run", "named function resolved")
    helpers.assert_eq(fns[1].start_line, 3, "function start line")
    helpers.assert_eq(fns[1].end_line, 8, "function end line")
    helpers.assert_eq(fns[1].complexity, 2, "if adds one decision")
    helpers.assert_eq(fns[2].name, "helper", "local function resolved")
    helpers.assert_eq(fns[2].complexity, 5, "while + and + for + or add four")
  end)
end

local function _report_opts(tmp_root, coverage_result)
  return {
    project_root = tmp_root,
    project_name = "T",
    source_roots = { "." },
    coverage_result = coverage_result,
    top = 0,
  }
end

local function _test_build_report_computes_crap_and_bands()
  helpers.with_temp_fixture({}, function(tmp_root)
    _write_source(tmp_root, "sample.lua", SAMPLE)
    -- Full coverage of every executable line of both functions (lines 1-20).
    local exec, hit = {}, {}
    for line = 1, 20 do
      exec[line] = true
      hit[line] = true
    end
    local report = analyzer.build_report(_report_opts(tmp_root, {
      coverage_available = true,
      files = { ["sample.lua"] = { exec = exec, hit = hit } },
    }))

    helpers.assert_eq(report.summary.function_count, 2, "two functions reported")
    local run_fn, helper_fn
    for _, fn in ipairs(report.functions) do
      if fn.name == "M.run" then run_fn = fn else helper_fn = fn end
    end
    helpers.assert_eq(run_fn.crap, 2, "fully covered CC2 scores 2 (low band)")
    helpers.assert_eq(run_fn.risk_band, "low", "CRAP < 5 is low")
    helpers.assert_eq(helper_fn.crap, 5, "fully covered CC5 scores 5 (moderate band)")
    helpers.assert_eq(helper_fn.risk_band, "moderate", "CRAP 5-30 is moderate")
    helpers.assert_eq(report.summary.moderate_count, 1, "one moderate function")
  end)
end

local function _test_build_report_na_when_coverage_unavailable()
  helpers.with_temp_fixture({}, function(tmp_root)
    _write_source(tmp_root, "sample.lua", SAMPLE)
    local report = analyzer.build_report(_report_opts(tmp_root, {
      coverage_available = false,
      files = {},
    }))

    local fn = report.functions[1]
    helpers.assert_eq(fn.crap, json_writer.null, "missing coverage means null CRAP, never 0")
    helpers.assert_eq(fn.coverage, "N/A", "coverage shows N/A")
    helpers.assert_eq(fn.risk_band, "n/a", "band is n/a")
    helpers.assert_eq(report.summary.na_count, 2, "both functions N/A")
    helpers.assert_eq(report.summary.max_crap, 0, "N/A functions do not count toward max")
  end)
end

local function _test_build_report_partial_coverage_scores_high()
  helpers.with_temp_fixture({}, function(tmp_root)
    _write_source(tmp_root, "sample.lua", SAMPLE)
    -- Only M.run's lines executable+hit; helper's lines executable, zero hit.
    local exec, hit = {}, {}
    for line = 1, 8 do exec[line] = true; hit[line] = true end
    for line = 10, 18 do exec[line] = true end
    local report = analyzer.build_report(_report_opts(tmp_root, {
      coverage_available = true,
      files = { ["sample.lua"] = { exec = exec, hit = hit } },
    }))

    local helper_fn
    for _, fn in ipairs(report.functions) do
      if fn.name == "helper" then helper_fn = fn end
    end
    -- CC5, 0% coverage: 25 * 1 + 5 = 30 → high band, sorted first.
    helpers.assert_eq(helper_fn.crap, 30, "uncovered CC5 hits the high band")
    helpers.assert_eq(helper_fn.risk_band, "high", "CRAP 30+ is high")
    helpers.assert_eq(report.functions[1].name, "helper", "highest CRAP sorts first")
    helpers.assert_eq(report.summary.high_count, 1, "one high function")
  end)
end

return {
  name = "crap4lua.unit.analyzer",
  tests = {
    { name = "ast_complexity_counts_decision_points", run = _test_ast_complexity_counts_decision_points },
    { name = "build_report_computes_crap_and_bands", run = _test_build_report_computes_crap_and_bands },
    { name = "build_report_na_when_coverage_unavailable", run = _test_build_report_na_when_coverage_unavailable },
    { name = "build_report_partial_coverage_scores_high", run = _test_build_report_partial_coverage_scores_high },
  },
}
