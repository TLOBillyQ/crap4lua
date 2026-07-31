local lu = require("luaunit")
local bootstrap = require("tests.support.bootstrap")
local bridge = require("crap4lua.bridge")
local common = require("crap4lua._internal.common")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

TestBridge = {}

function TestBridge:test_bridge_collect_builds_runtime_payload_from_config()
  local result, err = bridge.collect({
    config = helpers.fixture_path("basic_project/crap4lua.config.lua"),
  })
  if result == nil then
    error(err)
  end

  lu.assertEquals(result.project_name, "Fixture App", "bridge should expose config project name")
  lu.assertEquals(result.source_roots[1], "src", "bridge should expose source roots")
  lu.assertEquals(result.coverage_result.lanes[1].lane, "unit", "bridge should preserve configured lanes")
  lu.assertEquals(result.coverage_result.coverage_available, true, "bridge should have parsed the fixture luacov report")
  lu.assertNotNil(result.coverage_result.files["src/sample.lua"], "bridge should capture luacov hits for tracked sources")
end

function TestBridge:test_bridge_write_collect_json_writes_json_file()
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
    lu.assertNotNil(content:find('"project_name":"Fixture App"', 1, true), "bridge json should include project name")
    lu.assertNotNil(content:find('"coverage_result"', 1, true), "bridge json should include coverage result")
  end)
end

return TestBridge
