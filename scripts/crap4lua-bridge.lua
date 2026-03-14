local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function repo_root()
  local raw_path = arg and arg[0] or "scripts/crap4lua-bridge.lua"
  local normalized = normalize_path(raw_path)
  return normalized:match("^(.*)/scripts/[^/]+$") or "."
end

local root = repo_root()
package.path = root .. "/lib/?.lua;" .. root .. "/lib/?/?.lua;" .. package.path

local bridge = require("crap4lua.bridge")
bridge.run_cli(arg or {}, {
  command_name = "scripts/crap4lua-bridge.lua",
})
