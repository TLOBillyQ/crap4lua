local bootstrap = require("tests.support.bootstrap")
local coverage = require("crap4lua.coverage")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local REPORT_FIXTURE = table.concat({
  "==============================================================================",
  "src/tracked.lua",
  "==============================================================================",
  "      3 local tracked = {}",
  "        ",
  "      2 function tracked.run(flag)",
  "      2   if flag then",
  "***0     return 11",
  "          end",
  "      2   return 20",
  "        end",
  "        ",
  "      1 return tracked",
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

return {
  name = "crap4lua.unit.coverage",
  tests = {
    { name = "parse_luacov_report_marks_exec_and_hit_lines", run = _test_parse_luacov_report_marks_exec_and_hit_lines },
    { name = "collect_deletes_stale_report_and_parses_fresh_one", run = _test_collect_deletes_stale_report_and_parses_fresh_one },
    { name = "collect_without_report_marks_coverage_unavailable", run = _test_collect_without_report_marks_coverage_unavailable },
    { name = "collect_remaps_absolute_report_paths", run = _test_collect_remaps_absolute_report_paths },
  },
}
