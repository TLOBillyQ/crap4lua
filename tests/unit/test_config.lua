local lu = require("luaunit")
local bootstrap = require("tests.support.bootstrap")
local config = require("crap4lua.config")
local helpers = require("tests.support.helpers")

bootstrap.install_package_paths()

TestConfig = {}

function TestConfig:test_config_loads_relative_adapter_and_defaults_project_name()
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
    lu.assertEquals(loaded.source_roots[1], "src", "config should keep declared source root")
    lu.assertEquals(type(loaded.coverage.adapter.resolve_suites), "function", "config should load adapter table")
    lu.assertEquals(type(loaded.coverage.adapter.run), "function", "config should load adapter runner")
    lu.assertNotNil(tostring(loaded.project_name):match("^crap4lua_test_"), "config should default project name from project root")
    lu.assertEquals(loaded.coverage.lanes[1], "default", "config should default lanes")
  end)
end

function TestConfig:test_config_requires_source_roots()
  helpers.with_temp_fixture({
    ["crap4lua.config.lua"] = "return {}\n",
  }, function(tmp_root)
    local loaded, err = config.load(tmp_root .. "/crap4lua.config.lua")
    lu.assertNil(loaded, "config should reject missing source_roots")
    lu.assertNotNil(tostring(err):find("source_roots", 1, true), "config should explain missing source_roots")
  end)
end

return TestConfig
