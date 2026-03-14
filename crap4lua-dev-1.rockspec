package = "crap4lua"
version = "dev-1"
source = {
  url = ".",
}
description = {
  summary = "Standalone Lua CRAP hotspot analysis toolchain",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["crap4lua"] = "lib/crap4lua.lua",
    ["crap4lua.cli"] = "lib/crap4lua/cli.lua",
    ["crap4lua.common"] = "lib/crap4lua/common.lua",
    ["crap4lua.config"] = "lib/crap4lua/config.lua",
    ["crap4lua.coverage"] = "lib/crap4lua/coverage.lua",
    ["crap4lua.engine"] = "lib/crap4lua/engine.lua",
    ["crap4lua.json_reader"] = "lib/crap4lua/json_reader.lua",
    ["crap4lua.json_writer"] = "lib/crap4lua/json_writer.lua",
    ["crap4lua.luac_listing"] = "lib/crap4lua/luac_listing.lua",
    ["crap4lua.report"] = "lib/crap4lua/report.lua",
    ["crap4lua.source_names"] = "lib/crap4lua/source_names.lua",
    ["crap4lua.source_scan"] = "lib/crap4lua/source_scan.lua",
    ["crap4lua.viewer"] = "lib/crap4lua/viewer.lua",
  },
  copy_directories = {
    "lib/crap4lua/assets",
  },
  install = {
    bin = {
      crap4lua = "bin/crap4lua.lua",
    },
  },
}
