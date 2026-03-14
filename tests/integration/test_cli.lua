local bootstrap = require("tests.support.bootstrap")
local common = require("crap4lua.common")
local crap4lua = require("crap4lua")
local viewer = require("crap4lua.viewer")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_cli_report_generates_json_from_config()
  helpers.with_temp_fixture({}, function(tmp_root)
    local out_path = tmp_root .. "/report.json"
    local ok = crap4lua.run({
      "report",
      "--config", helpers.fixture_path("basic_project/crap4lua.config.lua"),
      "--out", out_path,
      "--top", "5",
    }, {
      exit = function(code)
        error("unexpected exit: " .. tostring(code))
      end,
    })
    assert(ok == true, "cli report should return true")

    local loaded = assert(viewer.load_report(out_path))
    helpers.assert_eq(loaded.metadata.project_name, "Fixture App", "config should feed report metadata")
    helpers.assert_eq(loaded.metadata.source_roots[1], "src", "config should feed source roots")
    helpers.assert_eq(loaded.lanes[1].lane, "unit", "config should feed coverage lanes")
  end)
end

local function _test_cli_viewer_builds_on_demand_from_config()
  helpers.with_temp_fixture({}, function(tmp_root)
    local ok = crap4lua.run({
      "viewer",
      "--config", helpers.fixture_path("basic_project/crap4lua.config.lua"),
      "--out-dir", tmp_root .. "/viewer",
    })
    assert(ok == true, "cli viewer should return true")
    assert(common.path_exists(tmp_root .. "/viewer/index.html"), "viewer command should write index asset")
    assert(common.path_exists(tmp_root .. "/viewer/crap_report.json"), "viewer command should write report json")
  end)
end

local function _test_cli_viewer_renders_existing_json_without_config()
  helpers.with_temp_fixture({}, function(tmp_root)
    local json_path = tmp_root .. "/input.json"
    assert(common.write_file(
      json_path,
      [[{"metadata":{"project_name":"Offline Fixture","source_roots":["src"]},"summary":{"module_count":0,"function_count":0,"total_crap":0,"critical_function_count":0},"lanes":[],"modules":[],"functions":[]}]]
    ))

    local ok = crap4lua.run({
      "viewer",
      "--in-json", json_path,
      "--out-dir", tmp_root .. "/offline-viewer",
    })
    assert(ok == true, "viewer should render from json without config")
    assert(common.path_exists(tmp_root .. "/offline-viewer/index.html"), "viewer should write bundled index")
  end)
end

local function _test_cli_report_requires_config_when_building_reports()
  local ok, err = pcall(function()
    crap4lua.run({ "report" })
  end)
  assert(ok == false, "cli report should fail without config")
  helpers.assert_contains(err, "crap4lua config not found", "cli should explain missing config")
end

return {
  name = "crap4lua.integration.cli",
  tests = {
    { name = "cli_report_generates_json_from_config", run = _test_cli_report_generates_json_from_config },
    { name = "cli_viewer_builds_on_demand_from_config", run = _test_cli_viewer_builds_on_demand_from_config },
    { name = "cli_viewer_renders_existing_json_without_config", run = _test_cli_viewer_renders_existing_json_without_config },
    { name = "cli_report_requires_config_when_building_reports", run = _test_cli_report_requires_config_when_building_reports },
  },
}
