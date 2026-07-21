local bootstrap = require("tests.support.bootstrap")
local config = require("crap4lua.config")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

local function _test_config_loads_relative_adapter_and_defaults_project_name()
  helpers.with_temp_fixture({
    ["src/sample.lua"] = "return {}\n",
    ["adapter.lua"] = table.concat({
      "return {",
      "  resolve_suites = function() return {}, 'fixture' end,",
      "  run = function() return { total = 0, failures = {}, failed = false } end,",
      "}",
    }, "\n"),
    ["crap4lua.config.lua"] = table.concat({
      "return {",
      "  source_roots = { 'src' },",
      "  coverage = {",
      "    adapter = 'adapter.lua',",
      "  },",
      "}",
    }, "\n"),
  }, function(tmp_root)
    local loaded, err = config.load(tmp_root .. "/crap4lua.config.lua")
    if loaded == nil then
      error(err)
    end
    helpers.assert_eq(loaded.source_roots[1], "src", "config should keep declared source root")
    helpers.assert_eq(type(loaded.coverage.adapter.resolve_suites), "function", "config should load adapter table")
    helpers.assert_eq(type(loaded.coverage.adapter.run), "function", "config should load adapter runner")
    assert(tostring(loaded.project_name):match("^crap4lua_test_") ~= nil, "config should default project name from project root")
    helpers.assert_eq(loaded.coverage.lanes[1], "default", "config should default lanes")
  end)
end

local function _test_config_requires_source_roots()
  helpers.with_temp_fixture({
    ["crap4lua.config.lua"] = "return {}\n",
  }, function(tmp_root)
    local loaded, err = config.load(tmp_root .. "/crap4lua.config.lua")
    helpers.assert_eq(loaded, nil, "config should reject missing source_roots")
    helpers.assert_contains(err, "source_roots", "config should explain missing source_roots")
  end)
end

return {
  name = "crap4lua.unit.config",
  tests = {
    { name = "config_loads_relative_adapter_and_defaults_project_name", run = _test_config_loads_relative_adapter_and_defaults_project_name },
    { name = "config_requires_source_roots", run = _test_config_requires_source_roots },
  },
}
