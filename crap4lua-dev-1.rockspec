package = "crap4lua"
version = "dev-1"
source = {
  url = ".",
}
description = {
  summary = "Lua bridge runtime for the crap4lua CLI",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["crap4lua.bridge"] = "lib/crap4lua/bridge.lua",
    ["crap4lua.config"] = "lib/crap4lua/config.lua",
    ["crap4lua.coverage"] = "lib/crap4lua/coverage.lua",
    ["crap4lua._internal.common"] = "lib/crap4lua/_internal/common.lua",
    ["crap4lua._internal.json_writer"] = "lib/crap4lua/_internal/json_writer.lua",
  },
}
