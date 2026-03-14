local bootstrap = require("tests.support.bootstrap")
local common = require("crap4lua.common")
local luac_listing = require("crap4lua.luac_listing")
local report = require("crap4lua.report")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_luac_listing_extracts_named_functions()
  helpers.with_temp_fixture({
    ["src/sample.lua"] = table.concat({
      "local function alpha(flag)",
      "  if flag then",
      "    return 1",
      "  end",
      "  return 0",
      "end",
      "",
      "local sample = {}",
      "function sample.beta(n)",
      "  local total = 0",
      "  for i = 1, n do",
      "    total = total + i",
      "  end",
      "  return total",
      "end",
      "",
      "sample.gamma = function(value)",
      "  while value > 0 do",
      "    value = value - 1",
      "  end",
      "  return value",
      "end",
      "",
      "return sample",
    }, "\n"),
  }, function(tmp_root)
    local source_text = assert(common.read_file(tmp_root .. "/src/sample.lua"))
    local functions, err = luac_listing.analyze_module({
      module_id = "src.sample",
      source_path = tmp_root .. "/src/sample.lua",
      relative_source_path = "src/sample.lua",
      source_name = "src/sample",
      source_text = source_text,
    })
    if functions == nil then
      error(err)
    end
    helpers.assert_eq(#functions, 3, "fixture should expose three named functions")
    helpers.assert_eq(functions[1].name, "alpha", "first function should preserve local name")
    helpers.assert_eq(functions[2].name, "sample.beta", "second function should preserve dotted name")
    helpers.assert_eq(functions[3].name, "sample.gamma", "third function should preserve assignment name")
  end)
end

local function _test_report_requires_explicit_source_roots()
  local result, err = report.build({
    project_root = common.current_dir(),
    coverage_result = {
      line_hits = {},
      lanes = {},
    },
  })
  helpers.assert_eq(result, nil, "report should reject missing source_roots")
  helpers.assert_contains(err, "source_roots", "report should explain missing source_roots")
end

local function _test_report_builds_metrics_from_precomputed_coverage()
  helpers.with_temp_fixture({
    ["app/sample.lua"] = table.concat({
      "local function alpha(flag)",
      "  if flag then",
      "    return 1",
      "  end",
      "  return 0",
      "end",
      "",
      "local sample = {}",
      "function sample.beta(n)",
      "  local total = 0",
      "  for i = 1, n do",
      "    total = total + i",
      "  end",
      "  return total",
      "end",
      "",
      "return sample",
    }, "\n"),
  }, function(tmp_root)
    local result, err = report.build({
      project_root = tmp_root,
      project_name = "Synthetic App",
      source_roots = { "app" },
      top = 5,
      coverage_result = {
        line_hits = {
          ["app/sample.lua"] = {
            [1] = true,
            [2] = true,
            [3] = true,
            [9] = true,
            [10] = true,
            [11] = true,
            [12] = true,
          },
        },
        lanes = {
          {
            lane = "unit",
            mode = "synthetic",
            total = 1,
            failed = false,
            failure_count = 0,
            failures = {},
          },
        },
      },
    })
    if result == nil then
      error(err)
    end
    helpers.assert_eq(result.metadata.project_name, "Synthetic App", "report should carry configured project name")
    helpers.assert_eq(result.metadata.source_roots[1], "app", "report should expose configured source roots")
    helpers.assert_eq(result.summary.module_count, 1, "fixture should yield one module")
    helpers.assert_eq(result.summary.function_count, 2, "fixture should yield two functions")
    assert(result.functions[1].crap >= result.functions[2].crap, "functions should sort by crap descending")
  end)
end

return {
  name = "crap4lua.unit.report",
  tests = {
    { name = "luac_listing_extracts_named_functions", run = _test_luac_listing_extracts_named_functions },
    { name = "report_requires_explicit_source_roots", run = _test_report_requires_explicit_source_roots },
    { name = "report_builds_metrics_from_precomputed_coverage", run = _test_report_builds_metrics_from_precomputed_coverage },
  },
}
