rockspec_format = "3.0"
package = "crap4lua"
version = "0.1.0-1"
source = {
   url = "git+http://lzxsvn:3000/qinyuanj/crap4lua.git",
   branch = "main",
}
description = {
   summary = "CRAP (Change Risk Anti-Patterns) hotspot analyzer for Lua",
   detailed = [[
      crap4lua computes cyclomatic complexity from luacheck's Lua AST and
      reads line coverage from standard luacov.report.out artifacts, producing
      JSON reports. It is the Lua port of unclebob's crap4clj / crap4go /
      crap4java tools.
   ]],
   homepage = "http://lzxsvn:3000/qinyuanj/crap4lua",
   license = "MIT",
}
dependencies = {
   "lua >= 5.4",
   "luacheck >= 1.1.0",
   "luacov >= 0.17.0",
}
test_dependencies = {
   "luaunit >= 3.4",
}
build = {
   type = "builtin",
   modules = {
      ["crap4lua.cli"] = "lib/crap4lua/cli.lua",
      ["crap4lua.analyzer"] = "lib/crap4lua/analyzer.lua",
      ["crap4lua.bridge"] = "lib/crap4lua/bridge.lua",
      ["crap4lua.config"] = "lib/crap4lua/config.lua",
      ["crap4lua.coverage"] = "lib/crap4lua/coverage.lua",
      ["crap4lua.ast"] = "lib/crap4lua/ast.lua",
      ["crap4lua._internal.json_reader"] = "lib/crap4lua/_internal/json_reader.lua",
      ["crap4lua._internal.json_writer"] = "lib/crap4lua/_internal/json_writer.lua",
      ["crap4lua._internal.common"] = "lib/crap4lua/_internal/common.lua",
   },
}
