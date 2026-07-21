local bootstrap = require("tests.support.bootstrap")
local bridge = require("crap4lua.bridge")
local common = require("crap4lua._internal.common")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_bridge_collect_builds_runtime_payload_from_config()
  local result, err = bridge.collect({
    config = helpers.fixture_path("basic_project/crap4lua.config.lua"),
  })
  if result == nil then
    error(err)
  end

  helpers.assert_eq(result.project_name, "Fixture App", "bridge should expose config project name")
  helpers.assert_eq(result.source_roots[1], "src", "bridge should expose source roots")
  helpers.assert_eq(result.coverage_result.lanes[1].lane, "unit", "bridge should preserve configured lanes")
  assert(result.coverage_result.line_hits["src/sample.lua"] ~= nil, "bridge should capture line hits for tracked sources")
end

local function _test_bridge_write_collect_json_writes_json_file()
  helpers.with_temp_fixture({}, function(tmp_root)
    local out_path = tmp_root .. "/collect.json"
    local result, err = bridge.write_collect_json({
      config = helpers.fixture_path("basic_project/crap4lua.config.lua"),
      out = out_path,
    })
    if result == nil then
      error(err)
    end

    local content = assert(common.read_file(out_path))
    helpers.assert_contains(content, '"project_name":"Fixture App"', "bridge json should include project name")
    helpers.assert_contains(content, '"coverage_result"', "bridge json should include coverage result")
  end)
end

return {
  name = "crap4lua.unit.bridge",
  tests = {
    { name = "bridge_collect_builds_runtime_payload_from_config", run = _test_bridge_collect_builds_runtime_payload_from_config },
    { name = "bridge_write_collect_json_writes_json_file", run = _test_bridge_write_collect_json_writes_json_file },
  },
}
