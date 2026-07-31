local bootstrap = require("tests.support.bootstrap")
local common = require("crap4lua._internal.common")
local coverage = require("crap4lua.coverage")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

-- Single-file fixture using the real luacov default-reporter format.
-- Column width grows with the largest hit count (3 here → 2-char column).
-- Missed executable lines use `*0` (not `***0` — the real format).
local REPORT_FIXTURE = table.concat({
  "==============================================================================",
  "src/tracked.lua",
  "==============================================================================",
  " 3 local tracked = {}",
  "   ",
  " 2 function tracked.run(flag)",
  " 2   if flag then",
  "*0     return 11",
  "       end",
  " 2   return 20",
  "     end",
  "   ",
  " 1 return tracked",
}, "\n")

-- Multi-file fixture with a Summary section to verify the parser stops
-- at the end of coverage data (real luacov always appends Summary last).
local REPORT_FIXTURE_MULTI = table.concat({
  "==============================================================================",
  "src/a.lua",
  "==============================================================================",
  " 1 local a = {}",
  " 1 return a",
  "==============================================================================",
  "src/b.lua",
  "==============================================================================",
  " 1 local b = {}",
  "*0 return b",
  "==============================================================================",
  "Summary",
  "==============================================================================",
  "",
  "File   Hits Missed Coverage",
  "---------------------------",
  "a.lua  2    0      100.00%",
  "b.lua  1    1      50.00%",
  "---------------------------",
  "Total  3    1      66.67%",
}, "\n")

local function _test_parse_luacov_report_marks_exec_and_hit_lines()
  local files = coverage.parse_luacov_report(REPORT_FIXTURE)
  local tracked = files["src/tracked.lua"]
  assert(tracked ~= nil, "report should expose the file section")

  helpers.assert_eq(tracked.hit[1], true, "line 1 hit")
  helpers.assert_eq(tracked.hit[4], true, "branch line hit")
  helpers.assert_eq(tracked.hit[5], nil, "***0 line is executable but not hit")
  helpers.assert_eq(tracked.exec[5], true, "***0 line still counts as executable")
  helpers.assert_eq(tracked.exec[2], nil, "blank-prefix line is non-executable")
  helpers.assert_eq(tracked.hit[10], true, "return line hit")
end

local function _write_report(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text .. "\n")
  file:close()
end

local function _test_collect_deletes_stale_report_and_parses_fresh_one()
  helpers.with_temp_fixture({}, function(tmp_root)
    local report_path = tmp_root .. "/luacov.report.out"
    _write_report(report_path, "STALE SENTINEL")

    local stale_seen = nil
    local result = coverage.collect({
      project_root = tmp_root,
      lanes = { "unit" },
      adapter = {
        resolve_suites = function()
          return {}, "synthetic"
        end,
        run = function(_, opts)
          -- Upstream discipline: the stale artifact must be gone before the
          -- test run regenerates it.
          local file = io.open(opts.report_path, "r")
          stale_seen = file ~= nil
          if file then file:close() end
          _write_report(opts.report_path, REPORT_FIXTURE)
          return { total = 0, failures = {}, failed = false }
        end,
      },
    })

    helpers.assert_eq(stale_seen, false, "collect should delete the stale report before running tests")
    helpers.assert_eq(result.coverage_available, true, "fresh report should make coverage available")
    local tracked = result.files["src/tracked.lua"]
    assert(tracked ~= nil, "collect should parse the regenerated report")
    helpers.assert_eq(tracked.hit[4], true, "hit lines survive collection")
    helpers.assert_eq(tracked.exec[5], true, "zero-hit lines stay executable")
  end)
end

local function _test_collect_without_report_marks_coverage_unavailable()
  helpers.with_temp_fixture({}, function(tmp_root)
    local result = coverage.collect({
      project_root = tmp_root,
      lanes = { "unit" },
      adapter = {
        resolve_suites = function()
          return {}, "synthetic"
        end,
        run = function()
          return { total = 0, failures = {}, failed = false }
        end,
      },
    })

    helpers.assert_eq(result.coverage_available, false, "missing report means coverage unavailable")
    helpers.assert_eq(next(result.files), nil, "no files parsed without a report")
    helpers.assert_eq(result.lanes[1].mode, "synthetic", "lane results still recorded")
  end)
end

local function _test_collect_remaps_absolute_report_paths()
  helpers.with_temp_fixture({}, function(tmp_root)
    local absolute_report = REPORT_FIXTURE:gsub("src/tracked.lua", tmp_root .. "/src/tracked.lua")
    local result = coverage.collect({
      project_root = tmp_root,
      lanes = { "unit" },
      adapter = {
        resolve_suites = function()
          return {}, "synthetic"
        end,
        run = function(_, opts)
          _write_report(opts.report_path, absolute_report)
          return { total = 0, failures = {}, failed = false }
        end,
      },
    })

    assert(result.files["src/tracked.lua"] ~= nil, "absolute report paths should remap to project-relative")
  end)
end

-- Regression: real luacov reports have multiple file sections; the parser
-- must handle the separator→path transition *between* sections correctly
-- (not drop the second file's path line when the state resets).
local function _test_parse_multi_file_report()
  local files = coverage.parse_luacov_report(REPORT_FIXTURE_MULTI)
  helpers.assert_eq(#common.sorted_keys(files), 2, "two file sections")
  assert(files["src/a.lua"] ~= nil, "first file parsed")
  assert(files["src/b.lua"] ~= nil, "second file parsed")

  -- Verify the *0 line in b.lua is executable but not hit.
  helpers.assert_eq(files["src/b.lua"].exec[2], true, "*0 line is executable")
  helpers.assert_eq(files["src/b.lua"].hit[2], nil, "*0 line is not hit")

  -- Verify no Summary-table content leaked into the files table.
  for path in pairs(files) do
    assert(path:find("Summary") == nil and path:find("Hits") == nil,
      "Summary-table content must not leak into files: " .. path)
  end
end

-- Regression: parse a real, full-fidelity luacov.report.out produced by
-- luacov's default reporter (the fixture was generated by running lua5.4
-- -lluacov + the luacov binary against a small fixture project).
local function _test_parse_real_luacov_report()
  local report_path = helpers.fixture_path("luacov_real/luacov.report.out")
  local content = common.read_file(report_path)
  assert(content ~= nil, "real luacov report fixture must exist")

  local files = coverage.parse_luacov_report(content)
  assert(files["src/example.lua"] ~= nil, "example.lua section parsed")
  assert(files["test_example.lua"] ~= nil, "test_example.lua section parsed")

  -- example.lua: 16 executable lines, 13 hit, 3 missed (*0)
  local ex = files["src/example.lua"]
  local exec_count, hit_count = 0, 0
  for _ in pairs(ex.exec) do exec_count = exec_count + 1 end
  for _ in pairs(ex.hit) do hit_count = hit_count + 1 end
  helpers.assert_eq(exec_count, 16, "executable line count")
  helpers.assert_eq(hit_count, 13, "hit line count")

  -- test_example.lua: 4 executable lines, all hit
  local te = files["test_example.lua"]
  local te_exec, te_hit = 0, 0
  for _ in pairs(te.exec) do te_exec = te_exec + 1 end
  for _ in pairs(te.hit) do te_hit = te_hit + 1 end
  helpers.assert_eq(te_exec, 4, "test executable line count")
  helpers.assert_eq(te_hit, 4, "test hit line count")

  -- No bogus entries from Summary section
  for path in pairs(files) do
    assert(path:find("Summary") == nil and path:find("Hits") == nil,
      "Summary-table content leaked into files: " .. path)
  end
end

return {
  name = "crap4lua.unit.coverage",
  tests = {
    { name = "parse_luacov_report_marks_exec_and_hit_lines", run = _test_parse_luacov_report_marks_exec_and_hit_lines },
    { name = "collect_deletes_stale_report_and_parses_fresh_one", run = _test_collect_deletes_stale_report_and_parses_fresh_one },
    { name = "collect_without_report_marks_coverage_unavailable", run = _test_collect_without_report_marks_coverage_unavailable },
    { name = "collect_remaps_absolute_report_paths", run = _test_collect_remaps_absolute_report_paths },
    { name = "parse_multi_file_report", run = _test_parse_multi_file_report },
    { name = "parse_real_luacov_report", run = _test_parse_real_luacov_report },
  },
}
